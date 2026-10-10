# What the directory and search results page lists (#40). Browsing and
# searching are the same thing here: a category, a query and the filters all
# narrow one list. Only published records are listed, and connection counts
# only count published links: a fact is published when it's verified and the
# company or plant it hangs on is published too (see each model's .published),
# so unpublishing a company or plant hides everything that hangs on it.
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

  # Number of published companies or plants in each category, for the pills.
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

  # Each site also gets #units_count and #units_capacity_mw, from its published units.
  def plants
    ordered(plant_scope.select("facilities.*", "(#{plant_connections_sql}) AS connections_count",
      "(#{units_sql("COUNT(*)")}) AS units_count", "(#{units_sql("SUM(u.capacity_mw)")}) AS units_capacity_mw"), "facilities.name")
  end

  # Companies are listed unless the Plants and sites category is chosen.
  def company_scope
    return Organization.none if category&.plants

    scope = Organization.published
    scope = in_category(scope) if category
    scope = matching_companies(scope) if query
    scope = with_technology(scope) if technology
    scope = scope.where(hq_state: state) if state
    scope
  end

  # Plants show for the Plants and sites category, and alongside companies in
  # search results. Only sites are listed; reactor units sit under them. A
  # site is public when it's verified, or when at least one of its units is
  # published (#73: a site made from NRC units goes public with its first one).
  def plant_scope
    return Facility.none if category && !category.plants
    return Facility.none if category.nil? && query.nil?

    scope = public_sites
    scope = matching_plants(scope) if query
    scope = scope.where(state:) if state
    scope = plants_with_technology(scope) if technology
    scope
  end

  def searching? = query.present?
  def filtered? = technology.present? || state.present?

  # Filter choices that actually occur in published data.
  # Technologies used by published companies, plants or units, plus their
  # parents (SMR in use offers Fission); then coolant types, which only
  # apply to companies and so aren't offered on the plants list.
  def technology_options
    @technology_options ||= begin
      used = Technology.where(id: OrganizationTechnology.published.select(:technology_id))
        .or(Technology.where(id: Facility.published.where.not(technology_id: nil).select(:technology_id)))
      techs = Technology.where(id: used.select(:id)).or(Technology.where(id: used.select(:parent_id)))
        .order(:name).map { |t| [ t.name, t.key ] }
      coolants = Role.where(parent: Role.find_by(key: "coolant")).where(id: OrganizationRole.published.select(:role_id))
        .order(:name).map { |r| [ "#{r.name} coolant", r.key ] }
      category&.plants ? techs : techs + coolants
    end
  end

  # States of published companies and of the public sites the filter checks
  # (not units), so every option can match something.
  def state_options
    @state_options ||= (Organization.published.distinct.pluck(:hq_state) + public_sites.distinct.pluck(:state))
      .compact_blank.uniq.sort
  end

  # Sites the public can see: verified ones, and pending ones with at least
  # one published unit (#73). A rejected or unpublished site never shows.
  def public_sites = Facility.published.where(parent_id: nil)

  private
    def in_category(scope)
      matches = []
      if category.role_keys.any?
        roles = Role.where(key: category.role_keys)
        role_ids = Role.where(id: roles.select(:id)).or(Role.where(parent_id: roles.select(:id))).select(:id)
        matches << OrganizationRole.published.where(role_id: role_ids).select(:organization_id)
      end
      if category.technology_key
        technologies = Technology.where(key: category.technology_key)
        tech_ids = Technology.where(id: technologies.select(:id)).or(Technology.where(parent_id: technologies.select(:id))).select(:id)
        matches << OrganizationTechnology.published.where(technology_id: tech_ids).select(:organization_id)
      end
      matches << Relationship.published.invests_in.select(:from_organization_id) if category.investors

      matches.map { |ids| scope.where(id: ids) }.reduce { |all, one| all.or(one) } || scope.none
    end

    # Name or any alias (compared normalized, as the matcher does); a role or
    # technology whose name or key matches ("SMR", "enrichment"); or any
    # party to a published deal or plant link whose description matches
    # ("HALEU"). Role descriptions aren't searched: they're too general to
    # point at anyone.
    def matching_companies(scope)
      by_role = OrganizationRole.published.joins(:role)
        .where("roles.name ILIKE :q OR roles.key ILIKE :q", q: like(query)).select(:organization_id)
      by_tech = OrganizationTechnology.published.joins(:technology)
        .where("technologies.name ILIKE :q OR technologies.key ILIKE :q", q: like(query)).select(:organization_id)
      deals = Relationship.published.where("relationships.description ILIKE ?", like(query))
      plant_links = FacilityRelationship.published.where("facility_relationships.description ILIKE ?", like(query))
      matches = [ by_role, by_tech, deals.select(:from_organization_id), deals.select(:to_organization_id), plant_links.select(:organization_id) ]

      # A query of only punctuation normalizes to "", which would match every alias.
      normalized = OrganizationAlias.normalize(query)
      matches << OrganizationAlias.where("normalized_alias LIKE ?", like(normalized)).select(:organization_id) if normalized.present?

      matches.reduce(scope.where("organizations.name ILIKE ?", like(query))) { |all, ids| all.or(scope.where(id: ids)) }
    end

    # The site's name, a published unit's name ("Vogtle Unit 3" finds Plant
    # Vogtle), or a published link to the site or a unit whose description matches.
    def matching_plants(scope)
      units = Facility.published.where.not(parent_id: nil).where("facilities.name ILIKE ?", like(query)).select(:parent_id)
      linked = Facility.where(id: FacilityRelationship.published.where("facility_relationships.description ILIKE ?", like(query)).select(:facility_id))
      linked_sites = Facility.where(id: linked.select(:id)).or(Facility.where(id: linked.select(:parent_id))).select(:id)

      scope.where("facilities.name ILIKE ?", like(query)).or(scope.where(id: units)).or(scope.where(id: linked_sites))
    end

    # A technology key (fission, smr) or a coolant sub-role key (molten_salt).
    # Sites whose own technology, or a published unit's, is the chosen one or a
    # sub-technology of it. Coolant is a company role, so it hides plants.
    def plants_with_technology(scope)
      technology_record = Technology.find_by(key: technology)
      return scope.none unless technology_record

      tech_ids = Technology.where(id: technology_record.id).or(Technology.where(parent_id: technology_record.id)).select(:id)
      units = Facility.published.where.not(parent_id: nil).where(technology_id: tech_ids).select(:parent_id)
      scope.where(technology_id: tech_ids).or(scope.where(id: units))
    end

    # A technology includes its sub-technologies: Fission includes SMR.
    def with_technology(scope)
      if (technology_record = Technology.find_by(key: technology))
        tech_ids = Technology.where(id: technology_record.id).or(Technology.where(parent_id: technology_record.id)).select(:id)
        scope.where(id: OrganizationTechnology.published.where(technology_id: tech_ids).select(:organization_id))
      elsif (coolant = Role.where(parent: Role.find_by(key: "coolant")).find_by(key: technology))
        scope.where(id: OrganizationRole.published.where(role: coolant).select(:organization_id))
      else
        scope
      end
    end

    def company_connections_sql
      <<~SQL.squish
        SELECT COUNT(*) FROM relationships r WHERE r.id IN (#{Relationship.published.select(:id).to_sql})
          AND (r.from_organization_id = organizations.id OR r.to_organization_id = organizations.id)
        ) + (
        SELECT COUNT(*) FROM facility_relationships fr WHERE fr.id IN (#{FacilityRelationship.published.select(:id).to_sql})
          AND fr.organization_id = organizations.id
      SQL
    end

    # Links to the site itself or to any of its units.
    def plant_connections_sql
      <<~SQL.squish
        SELECT COUNT(*) FROM facility_relationships fr WHERE fr.id IN (#{FacilityRelationship.published.select(:id).to_sql})
          AND fr.facility_id IN (SELECT u.id FROM facilities u WHERE u.id = facilities.id OR u.parent_id = facilities.id)
      SQL
    end

    # An aggregate over a site's published units.
    def units_sql(aggregate)
      "SELECT #{aggregate} FROM facilities u WHERE u.parent_id = facilities.id " \
        "AND u.id IN (#{Facility.published.where.not(parent_id: nil).select(:id).to_sql})"
    end

    def ordered(scope, name_column)
      sort == "connections" ? scope.order(Arel.sql("connections_count DESC"), name_column) : scope.order(name_column)
    end

    def like(text) = "%#{ActiveRecord::Base.sanitize_sql_like(text.to_s)}%"
end
