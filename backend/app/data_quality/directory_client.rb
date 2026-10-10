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
  WriteResult = Data.define(:ref, :errors) do
    def success? = errors.empty?
  end

  def initialize(lookup: nil, fact_writer: nil)
    @lookup = lookup
    @fact_writer = fact_writer
  end

  # Returns a Ref to the existing record a candidate describes, or nil.
  # Lookup takes one key at a time, so try the strongest identifier first.
  # Other kinds are matched in the match stage issue (#14).
  def find(kind, payload)
    found =
      case kind
      when "organization"
        first_match(payload, %w[name domain]) { |key, value| lookup.organization(key.to_sym => value) }
      when "facility"
        first_match(payload, %w[nrc_docket name]) { |key, value| lookup.facility(key.to_sym => value) }
      end

    Ref.new(type: type_for(kind), id: found.id) if found
  end

  # Writes a candidate as a verified fact, with the source it came from as
  # evidence. A matched candidate updates its record (attributes id:).
  # Returns a WriteResult; never raises on validation problems.
  def write_fact(candidate, confidence:, crawl_run:)
    attributes = candidate.payload.symbolize_keys
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

    if result.ok?
      WriteResult.new(ref: Ref.new(type: type_for(result.kind), id: result.id), errors: [])
    else
      WriteResult.new(ref: nil, errors: Array(result.errors).presence || [ "unknown error" ])
    end
  end

  private
    # Resolved lazily so the module has no load-time dependency on the directory.
    def lookup = @lookup ||= "Directory::Lookup".constantize
    def fact_writer = @fact_writer ||= "Directory::FactWriter".constantize

    def first_match(payload, keys)
      keys.each do |key|
        next if payload[key].blank?

        found = yield key, payload[key]
        return found if found
      end
      nil
    end

    # Fact kind => the record type candidates store, e.g. "facility_relationship"
    # => "FacilityRelationship". Kinds are named after their records.
    def type_for(kind) = kind.to_s.camelize
end
