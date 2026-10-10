# Everything the company page shows (#42), verified facts only. Deals count
# only when the other company is verified too; plant links only when the
# plant is public (DirectoryListing#public_sites, or a verified unit).
#
# Sources are numbered once, in reading order (description, key facts, deals,
# then plants), so chips and the source list agree.
class CompanyProfile
  # Lists longer than this collapse behind "Show all" (#90).
  VISIBLE_ITEMS = 6

  attr_reader :organization, :citations

  # nil unless the company exists and is verified.
  def self.find(slug)
    organization = Organization.verified.find_by(slug:)
    new(organization) if organization
  end

  def initialize(organization)
    @organization = organization
    @citations = CitationIndex.new
    @cited = {}
    number_sources
  end

  delegate :name, :slug, :description, :website, :hq_city, :hq_state, :founded_year, :legal_name, :verified_at, to: :organization

  # [[number, source], ...] for a fact on this page.
  def citations_for(fact) = @cited.fetch(fact) { [] }

  def roles
    @roles ||= organization.organization_roles.verified.includes(:role, evidence: :source).sort_by { |r| r.role.name }
  end

  # Roles to show: a general role is left out when a more specific one under
  # it is there too ("Molten salt coolant", not "Coolant, Molten salt coolant").
  def shown_roles
    parent_ids = roles.map { |r| r.role.parent_id }.compact
    roles.reject { |r| parent_ids.include?(r.role_id) }
  end

  def technologies
    @technologies ||= organization.organization_technologies.verified.includes(:technology, evidence: :source).sort_by { |t| t.technology.name }
  end

  # Deals in both directions, with the other company verified, except
  # "subsidiary of", which the key facts show as the parent company.
  def deals
    @deals ||= Relationship.verified
      .where(from_organization: organization).or(Relationship.verified.where(to_organization: organization))
      .where.not(relationship_type: "subsidiary_of")
      .includes(:from_organization, :to_organization, evidence: :source).to_a
      .select { |deal| other_party(deal).verified? }
      .sort_by { |deal| [ deal.relationship_type, other_party(deal).name ] }
  end

  def parents
    @parents ||= Relationship.verified.subsidiary_of.where(from_organization: organization)
      .includes(:to_organization, evidence: :source).select { |link| link.to_organization.verified? }
  end

  def subsidiaries
    @subsidiaries ||= Relationship.verified.subsidiary_of.where(to_organization: organization)
      .includes(:from_organization, evidence: :source).select { |link| link.from_organization.verified? }
  end

  def plant_links
    @plant_links ||= begin
      organization.facility_relationships.verified
        .where(facility_id: DirectoryListing.new.public_facilities.select(:id))
        .includes(facility: :parent, evidence: :source).to_a
        .sort_by { |link| [ link.relationship_type, link.facility.name ] }
    end
  end

  def other_party(deal) = deal.from_organization_id == organization.id ? deal.to_organization : deal.from_organization

  def aliases
    @aliases ||= organization.aliases.map(&:alias).reject { |name| OrganizationAlias.normalize(name) == OrganizationAlias.normalize(organization.name) }
  end

  # The first category this company falls in, for the breadcrumb.
  def category
    keys = roles.flat_map { |r| [ r.role.key, r.role.parent&.key ] }.compact
    Category.all.find { |c| (c.role_keys & keys).any? } ||
      (Category.find("fusion") if technologies.any? { |t| t.technology.key == "fusion" })
  end

  # Fields DESIGN.md marks "must" that this company doesn't have yet.
  def missing_fields
    [ ("One-line description" if description.blank?), ("Headquarters" if hq_city.blank? && hq_state.blank?) ].compact
  end

  # The record's own evidence backs its description and headquarters.
  def description_citations = description.present? ? citations_for(organization) : []

  private
    # The company record's own evidence backs its description and the key
    # facts stored on it (website, aliases, licensee, headquarters, founded).
    def number_sources
      cite(organization) if description.present? || website.present? || aliases.any? || legal_name.present?
      shown_roles.each { |role| cite(role) }
      technologies.each { |technology| cite(technology) }
      cite(organization) if hq_city.present? || hq_state.present? || founded_year.present?
      (parents + subsidiaries).each { |link| cite(link) }
      deals.each { |deal| cite(deal) }
      plant_links.each { |link| cite(link) }
    end

    def cite(fact)
      @cited[fact] = citations.cite(fact.evidence)
    end
end
