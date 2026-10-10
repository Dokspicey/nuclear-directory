# Stand-ins for Directory::Lookup and Directory::FactWriter (#32), so the
# module is tested without the directory. They follow the interface
# DataQuality::DirectoryClient expects; when #32 lands, the real classes
# must satisfy the same calls (see app/data_quality/README.md).
module FakeDirectory
  Found = Data.define(:id)
  WriteResult = Data.define(:record_type, :record_id, :errors) do
    def success? = errors.empty?
  end

  class Lookup
    def initialize(organizations: {}, facilities: {})
      @organizations = organizations # name => id
      @facilities = facilities
    end

    def find_organization(name: nil, domain: nil)
      Found.new(id: @organizations[name]) if @organizations.key?(name)
    end

    def find_facility(name: nil, nrc_docket: nil)
      Found.new(id: @facilities[name]) if @facilities.key?(name)
    end
  end

  class FactWriter
    TYPES = { "organization" => "Organization", "facility" => "Facility" }.freeze

    attr_reader :writes

    def initialize(fail_with: nil)
      @fail_with = fail_with
      @writes = []
      @next_id = 1000
    end

    def write(kind:, attributes:, subject:, evidence:, verified_by:)
      @writes << { kind:, attributes:, subject:, evidence:, verified_by: }
      return WriteResult.new(record_type: nil, record_id: nil, errors: [ @fail_with ]) if @fail_with

      id = subject ? subject[:id] : (@next_id += 1)
      WriteResult.new(record_type: TYPES.fetch(kind, kind.camelize), record_id: id, errors: [])
    end
  end

  def self.client(lookup: Lookup.new, fact_writer: FactWriter.new)
    DataQuality::DirectoryClient.new(lookup: lookup, fact_writer: fact_writer)
  end
end
