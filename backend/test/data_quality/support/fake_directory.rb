# In-memory stand-ins for Directory::Lookup and Directory::FactWriter, so
# the module's own tests don't depend on directory data. They have the same
# method signatures and return the real value classes (OrganizationRef,
# FacilityRef, FactWriter::Result), and directory_client_test.rb checks the
# signatures still match, so the fakes can't drift from the real thing.
module FakeDirectory
  class Lookup
    def initialize(organizations: {}, facilities: {})
      @organizations = organizations # name => id
      @facilities = facilities
    end

    def organization(id: nil, slug: nil, name: nil, domain: nil)
      one_of!(id:, slug:, name:, domain:)
      Directory::OrganizationRef.new(id: @organizations[name], slug: nil, name: name, domain: nil,
        verification_status: "verified", verified_by: nil, verified_at: nil) if @organizations.key?(name)
    end

    def facility(id: nil, slug: nil, name: nil, nrc_docket: nil, eia_plant_id: nil)
      one_of!(id:, slug:, name:, nrc_docket:, eia_plant_id:)
      Directory::FacilityRef.new(id: @facilities[name], slug: nil, name: name, nrc_docket: nil, parent_id: nil,
        verification_status: "verified", verified_by: nil, verified_at: nil, facility_type: nil, status: nil, state: nil, country_code: nil,
        latitude: nil, longitude: nil) if @facilities.key?(name)
    end

    # The fake knows nothing similar; match tests that need it use the real directory.
    def similar_organizations(name) = []
    def fact_state(type:, id:) = nil
    def similar_facilities(name) = []
    def facility_units(name:, state: nil) = []

    private
      # Same rule as the real Lookup.
      def one_of!(**options)
        raise ArgumentError, "pass exactly one of #{options.keys.join(", ")}" unless options.compact.size == 1
      end
  end

  class FactWriter
    attr_reader :writes

    def initialize(fail_with: nil)
      @fail_with = fail_with
      @writes = []
      @next_id = 1000
    end

    def write(kind, attributes, evidence: [], verification: nil, fill_blank: false, protect_human_verified: false)
      @writes << { kind:, attributes:, evidence:, verification:, fill_blank: }
      return Directory::FactWriter::Result.new(kind: kind.to_sym, id: nil, created: false, errors: [ @fail_with ]) if @fail_with

      id = attributes[:id] || (@next_id += 1)
      Directory::FactWriter::Result.new(kind: kind.to_sym, id: id, created: !attributes[:id], errors: [])
    end

    # The fake directory has no closed facts.
    def while_open(type:, id:)
      yield
      nil
    end

    # The fake directory has no sites to fill.
    def fill_site_from_unit(unit_id, fields:, evidence:) = nil
  end

  def self.client(lookup: Lookup.new, fact_writer: FactWriter.new)
    DataQuality::DirectoryClient.new(lookup: lookup, fact_writer: fact_writer)
  end
end
