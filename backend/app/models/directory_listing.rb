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
    @technology = technology.to_s.presence
    @state = state.to_s.strip.upcase.presence
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

  def plants
    ordered(plant_scope.select("facilities.*", "(#{plant_connections_sql}) AS connections_count"), "facilities.name")
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
  # search results. Only sites are listed; reactor units sit under them.
  def plant_scope
    return Facility.none if category && !category.plants
    return Facility.none if category.nil? && query.nil?

    scope = Facility.verified.where(parent_id: nil)
    scope = scope.where("facilities.name ILIKE ?", like(query)) if query
    scope = scope.where(state:) if state
    scope
  end

  def searching? = query.present?
  def filtered? = technology.present? || state.present?

  # Filter choices that actually occur in verified data.
  def technology_options
    techs = Technology.where(id: OrganizationTechnology.verified.select(:technology_id)).order(:name).map { |t| [ t.name, t.key ] }
    coolants = Role.where(parent: Role.find_by(key: "coolant")).where(id: OrganizationRole.verified.select(:role_id))
      .order(:name).map { |r| [ "#{r.name} coolant", r.key ] }
    techs + coolants
  end

  def state_options
    (Organization.verified.distinct.pluck(:hq_state) + Facility.verified.distinct.pluck(:state)).compact_blank.uniq.sort
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
    # technology whose name or key matches ("SMR", "enrichment"); or either
    # side of a verified deal whose description matches ("HALEU"). Role
    # descriptions aren't searched: they're too general to point at anyone.
    def matching_companies(scope)
      normalized = OrganizationAlias.normalize(query)
      by_alias = OrganizationAlias.where("normalized_alias LIKE ?", like(normalized)).select(:organization_id)
      by_role = OrganizationRole.verified.joins(:role)
        .where("roles.name ILIKE :q OR roles.key ILIKE :q", q: like(query)).select(:organization_id)
      by_tech = OrganizationTechnology.verified.joins(:technology)
        .where("technologies.name ILIKE :q OR technologies.key ILIKE :q", q: like(query)).select(:organization_id)
      deals = Relationship.verified.where("relationships.description ILIKE ?", like(query))

      [ by_alias, by_role, by_tech, deals.select(:from_organization_id), deals.select(:to_organization_id) ]
        .reduce(scope.where("organizations.name ILIKE ?", like(query))) { |all, ids| all.or(scope.where(id: ids)) }
    end

    # A technology key (fission, smr) or a coolant sub-role key (molten_salt).
    def with_technology(scope)
      if (technology_record = Technology.find_by(key: technology))
        scope.where(id: OrganizationTechnology.verified.where(technology: technology_record).select(:organization_id))
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

    def ordered(scope, name_column)
      sort == "connections" ? scope.order(Arel.sql("connections_count DESC"), name_column) : scope.order(name_column)
    end

    def like(text) = "%#{ActiveRecord::Base.sanitize_sql_like(text.to_s)}%"
end
