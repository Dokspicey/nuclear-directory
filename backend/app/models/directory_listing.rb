# What the directory and search results page lists (#40). Browsing and
# searching are the same thing here: a category, a query and the filters all
# narrow one list. Only verified records are listed, and connection counts
# only count verified links.
#
#   listing = DirectoryListing.new(category: "fuel", q: "enrich", state: "TN")
#   listing.companies  # => Organizations, each with #connections_count
#   listing.plants     # => Facilities (sites, not units)
class DirectoryListing
  SORTS = { "name" => "A to Z", "connections" => "Most connected" }.freeze

  attr_reader :category, :query, :technology, :state, :sort

  # Unknown values are ignored rather than raising: these come from the URL.
  def initialize(category: nil, q: nil, technology: nil, state: nil, sort: nil)
    @category = Category.find(category)
    @query = q.to_s.strip.first(100).presence
    # A filter value that isn't one of the options is dropped, so a stale or
    # mistyped URL can't silently narrow the list behind an "Any" control.
    @technology = technology.to_s.presence&.presence_in(technology_options.map(&:last))
    @state = state.to_s.strip.upcase.presence&.presence_in(state_options)
    @sort = SORTS.key?(sort.to_s) ? sort.to_s : "name"
  end

  # Number of verified companies or plants in each category, for the pills.
  def self.category_counts
    Category.all.to_h do |category|
      listing = new(category: category.key)
      [ category.key, category.plants ? listing.plant_scope.count : listing.company_scope.count ]
    end
  end

  # Each with #connections_count, in the chosen order.
  def companies
    ordered(company_scope.select("organizations.*", "(#{company_connections_sql}) AS connections_count"), "organizations.name")
  end

  # Each site also gets #units_count and #units_capacity_mw, from its verified units.
  def plants
    ordered(plant_scope.select("facilities.*", "(#{plant_connections_sql}) AS connections_count",
      "(#{units_sql("COUNT(*)")}) AS units_count", "(#{units_sql("SUM(u.capacity_mw)")}) AS units_capacity_mw"), "facilities.name")
  end

  # Companies are listed unless the Plants and sites category is chosen.
  def company_scope
    return Organization.none if category&.plants

    scope = Organization.verified
    scope = in_category(scope) if category
    scope = matching_companies(scope) if query
    scope = with_technology(scope) if technology
    scope = scope.where(hq_state: state) if state
    scope
  end

  # Plants show for the Plants and sites category, and alongside companies in
  # search results. Only sites are listed; reactor units sit under them. A
  # site is public when it's verified, or when at least one of its units is
  # (#73: sites created from NRC units go public with their first verified unit).
  def plant_scope
    return Facility.none if category && !category.plants
    return Facility.none if category.nil? && query.nil?

    sites = Facility.where(parent_id: nil)
    scope = sites.verified.or(sites.where(id: Facility.verified.where.not(parent_id: nil).select(:parent_id)))
    scope = matching_plants(scope) if query
    scope = scope.where(state:) if state
    scope
  end

  def searching? = query.present?
  def filtered? = technology.present? || state.present?

  # Filter choices that actually occur in verified data.
  def technology_options
    @technology_options ||= begin
      used = Technology.where(id: OrganizationTechnology.verified.select(:technology_id))
      # A parent of a technology in use is offered too: SMR in use offers Fission.
      techs = Technology.where(id: used.select(:id)).or(Technology.where(id: used.select(:parent_id)))
        .order(:name).map { |t| [ t.name, t.key ] }
      coolants = Role.where(parent: Role.find_by(key: "coolant")).where(id: OrganizationRole.verified.select(:role_id))
        .order(:name).map { |r| [ "#{r.name} coolant", r.key ] }
      techs + coolants
    end
  end

  def state_options
    @state_options ||= (Organization.verified.distinct.pluck(:hq_state) + Facility.verified.distinct.pluck(:state))
      .compact_blank.uniq.sort
  end

  private
    def in_category(scope)
      matches = []
      if category.role_keys.any?
        roles = Role.where(key: category.role_keys)
        role_ids = Role.where(id: roles.select(:id)).or(Role.where(parent_id: roles.select(:id))).select(:id)
        matches << OrganizationRole.verified.where(role_id: role_ids).select(:organization_id)
      end
      if category.technology_key
        technologies = Technology.where(key: category.technology_key)
        tech_ids = Technology.where(id: technologies.select(:id)).or(Technology.where(parent_id: technologies.select(:id))).select(:id)
        matches << OrganizationTechnology.verified.where(technology_id: tech_ids).select(:organization_id)
      end
      matches << Relationship.verified.invests_in.select(:from_organization_id) if category.investors

      matches.map { |ids| scope.where(id: ids) }.reduce { |all, one| all.or(one) } || scope.none
    end

    # Name or any alias (compared normalized, as the matcher does); a role or
    # technology whose name or key matches ("SMR", "enrichment"); or any
    # party to a verified deal or plant link whose description matches
    # ("HALEU"). Role descriptions aren't searched: they're too general to
    # point at anyone.
    def matching_companies(scope)
      by_role = OrganizationRole.verified.joins(:role)
        .where("roles.name ILIKE :q OR roles.key ILIKE :q", q: like(query)).select(:organization_id)
      by_tech = OrganizationTechnology.verified.joins(:technology)
        .where("technologies.name ILIKE :q OR technologies.key ILIKE :q", q: like(query)).select(:organization_id)
      deals = Relationship.verified.where("relationships.description ILIKE ?", like(query))
      plant_links = FacilityRelationship.verified.where("facility_relationships.description ILIKE ?", like(query))
      matches = [ by_role, by_tech, deals.select(:from_organization_id), deals.select(:to_organization_id), plant_links.select(:organization_id) ]

      # A query of only punctuation normalizes to "", which would match every alias.
      normalized = OrganizationAlias.normalize(query)
      matches << OrganizationAlias.where("normalized_alias LIKE ?", like(normalized)).select(:organization_id) if normalized.present?

      matches.reduce(scope.where("organizations.name ILIKE ?", like(query))) { |all, ids| all.or(scope.where(id: ids)) }
    end

    # The site's name, a verified unit's name ("Vogtle Unit 3" finds Plant
    # Vogtle), or a verified link to the site or a unit whose description matches.
    def matching_plants(scope)
      units = Facility.verified.where.not(parent_id: nil).where("facilities.name ILIKE ?", like(query)).select(:parent_id)
      linked = Facility.where(id: FacilityRelationship.verified.where("facility_relationships.description ILIKE ?", like(query)).select(:facility_id))
      linked_sites = Facility.where(id: linked.select(:id)).or(Facility.where(id: linked.select(:parent_id))).select(:id)

      scope.where("facilities.name ILIKE ?", like(query)).or(scope.where(id: units)).or(scope.where(id: linked_sites))
    end

    # A technology key (fission, smr) or a coolant sub-role key (molten_salt).
    # A technology includes its sub-technologies: Fission includes SMR.
    def with_technology(scope)
      if (technology_record = Technology.find_by(key: technology))
        tech_ids = Technology.where(id: technology_record.id).or(Technology.where(parent_id: technology_record.id)).select(:id)
        scope.where(id: OrganizationTechnology.verified.where(technology_id: tech_ids).select(:organization_id))
      elsif (coolant = Role.where(parent: Role.find_by(key: "coolant")).find_by(key: technology))
        scope.where(id: OrganizationRole.verified.where(role: coolant).select(:organization_id))
      else
        scope
      end
    end

    def company_connections_sql
      <<~SQL.squish
        SELECT COUNT(*) FROM relationships r WHERE r.verification_status = 'verified'
          AND (r.from_organization_id = organizations.id OR r.to_organization_id = organizations.id)
        ) + (
        SELECT COUNT(*) FROM facility_relationships fr WHERE fr.verification_status = 'verified'
          AND fr.organization_id = organizations.id
      SQL
    end

    # Links to the site itself or to any of its units.
    def plant_connections_sql
      <<~SQL.squish
        SELECT COUNT(*) FROM facility_relationships fr WHERE fr.verification_status = 'verified'
          AND fr.facility_id IN (SELECT u.id FROM facilities u WHERE u.id = facilities.id OR u.parent_id = facilities.id)
      SQL
    end

    # An aggregate over a site's verified units.
    def units_sql(aggregate)
      "SELECT #{aggregate} FROM facilities u WHERE u.parent_id = facilities.id AND u.verification_status = 'verified'"
    end

    def ordered(scope, name_column)
      sort == "connections" ? scope.order(Arel.sql("connections_count DESC"), name_column) : scope.order(name_column)
    end

    def like(text) = "%#{ActiveRecord::Base.sanitize_sql_like(text.to_s)}%"
end
