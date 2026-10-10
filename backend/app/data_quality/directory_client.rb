# The module's only door into the directory. Reads go through
# Directory::Lookup, writes through Directory::FactWriter (contract in
# app/directory/README.md); nothing else in DataQuality may reference
# directory code or models (enforced by test/data_quality/boundary_test.rb).
#
# Keeping the calls in one file means that if the directory interfaces
# change, or the module moves to its own service and talks to the
# directory over an API, only this file changes.
class DataQuality::DirectoryClient
  # A pointer to a directory record, e.g. Ref.new(type: "Organization", id: 12).
  # type is what candidates store in subject_type.
  Ref = Data.define(:type, :id)
  # What a lookup found: enough to match on and to explain a match.
  Record = Data.define(:type, :id, :name, :nrc_docket) do
    def ref = Ref.new(type:, id:)
  end
  WriteResult = Data.define(:ref, :errors, :created) do
    def initialize(ref:, errors:, created: false) = super
    def success? = errors.empty?
  end

  # Kinds whose payload names other records instead of carrying attributes;
  # the match stage resolves those names to ids and writes the fact.
  LINK_KINDS = %w[organization_role organization_technology relationship facility_relationship].freeze

  def initialize(lookup: nil, fact_writer: nil)
    @lookup = lookup
    @fact_writer = fact_writer
  end

  # Exact lookups. Pass one keyword; returns a Record or nil.
  def organization(name: nil, domain: nil)
    record("Organization", lookup.organization(name:, domain:))
  end

  def facility(name: nil, nrc_docket: nil)
    record("Facility", lookup.facility(name:, nrc_docket:))
  end

  # Likely duplicates an exact lookup misses. Returns Records.
  def similar_organizations(name)
    lookup.similar_organizations(name).map { |ref| record("Organization", ref) }
  end

  def similar_facilities(name)
    lookup.similar_facilities(name).map { |ref| record("Facility", ref) }
  end

  # Writes a fact the match stage found or proposed, with the candidate's
  # source as evidence (found_by: crawler). Verification is left alone, so a
  # new fact starts pending and an existing one keeps its status.
  def write_pending(kind, attributes, candidate:, crawl_run:)
    result = fact_writer.write(kind, attributes,
      evidence: [ { source_id: candidate.source_id, quote: candidate.quote, found_by: "crawler", crawl_run_id: crawl_run.id } ])
    write_result(result)
  end

  # Writes a candidate as a verified fact, with the source it came from as
  # evidence. A matched candidate updates its record (attributes id:); for
  # link kinds the match stage already wrote the attributes, so only the
  # verification and evidence are sent. Returns a WriteResult; never raises
  # on validation problems.
  def write_fact(candidate, confidence:, crawl_run:)
    attributes = LINK_KINDS.include?(candidate.kind) ? {} : candidate.payload.symbolize_keys
    attributes[:id] = candidate.subject_id if candidate.subject_id

    result = fact_writer.write(
      candidate.kind,
      attributes,
      evidence: [ {
        source_id: candidate.source_id,
        quote: candidate.quote,
        found_by: "crawler",
        confidence: confidence,
        crawl_run_id: crawl_run.id
      } ],
      verification: { status: "verified", by: "agent:verifier/#{crawl_run.model || 'unknown'}" }
    )
    write_result(result)
  end

  private
    # Resolved lazily so the module has no load-time dependency on the directory.
    def lookup = @lookup ||= "Directory::Lookup".constantize
    def fact_writer = @fact_writer ||= "Directory::FactWriter".constantize

    def record(type, ref)
      Record.new(type:, id: ref.id, name: ref.name, nrc_docket: ref.try(:nrc_docket)) if ref
    end

    def write_result(result)
      if result.ok?
        WriteResult.new(ref: Ref.new(type: type_for(result.kind), id: result.id), errors: [], created: result.created)
      else
        WriteResult.new(ref: nil, errors: Array(result.errors).presence || [ "unknown error" ])
      end
    end

    # Fact kind => the record type candidates store, e.g. "facility_relationship"
    # => "FacilityRelationship". Kinds are named after their records.
    def type_for(kind) = kind.to_s.camelize
end
