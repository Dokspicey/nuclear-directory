# Read side of the directory boundary. Finds organizations and facilities
# and returns plain value objects (OrganizationRef, FacilityRef), so code
# outside the directory never holds an ActiveRecord model. Facts of every
# verification status are returned; check verification_status if it matters.
#
#   Directory::Lookup.organization(name: "TerraPower, Inc.")  # => OrganizationRef or nil
#   Directory::Lookup.facility(nrc_docket: "05000424")        # => FacilityRef or nil
module Directory
  module Lookup
    extend self

    # Pass exactly one of id, slug, name or domain.
    # name matches the organization's name or any alias, compared after
    # OrganizationAlias.normalize, so "TerraPower, LLC" finds "TerraPower".
    # domain accepts a bare domain or a URL.
    def organization(id: nil, slug: nil, name: nil, domain: nil)
      scope =
        case one_of!(id:, slug:, name:, domain:)
        in [ :id, value ] then Organization.where(id: value)
        in [ :slug, value ] then Organization.where(slug: value)
        in [ :name, value ]
          Organization.joins(:aliases).where(organization_aliases: { normalized_alias: OrganizationAlias.normalize(value) })
        in [ :domain, value ] then Organization.where(domain: Organization.domain_from(value))
        end

      record = scope.first
      OrganizationRef.from(record) if record
    end

    # Pass exactly one of id, slug, name or nrc_docket.
    # name is matched case-insensitively; names aren't unique, so the oldest
    # match wins.
    def facility(id: nil, slug: nil, name: nil, nrc_docket: nil)
      scope =
        case one_of!(id:, slug:, name:, nrc_docket:)
        in [ :id, value ] then Facility.where(id: value)
        in [ :slug, value ] then Facility.where(slug: value)
        in [ :name, value ] then Facility.where("lower(name) = ?", value.to_s.strip.downcase)
        in [ :nrc_docket, value ] then Facility.where(nrc_docket: value)
        end

      record = scope.order(:id).first
      FacilityRef.from(record) if record
    end

    private
      def one_of!(**options)
        given = options.compact
        raise ArgumentError, "pass exactly one of #{options.keys.join(", ")}" unless given.size == 1

        given.first
      end
  end
end
