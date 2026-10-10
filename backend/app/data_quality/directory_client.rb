# The module's only door into the directory. Reads go through
# Directory::Lookup, writes through Directory::FactWriter (#32); nothing
# else in DataQuality may reference directory code or models
# (enforced by test/data_quality/boundary_test.rb).
#
# Keeping the calls in one file means that if the directory interfaces
# change, or the module moves to its own service and talks to the
# directory over an API, only this file changes.
class DataQuality::DirectoryClient
  # A pointer to a directory record, e.g. Ref.new(type: "Organization", id: 12).
  Ref = Data.define(:type, :id)
  WriteResult = Data.define(:ref, :errors) do
    def success? = errors.empty?
  end

  # Candidate kind => directory record type, for kinds Lookup can find.
  # The other kinds are matched in the match stage issue (#14).
  LOOKUP_TYPES = { "organization" => "Organization", "facility" => "Facility" }.freeze

  def initialize(lookup: nil, fact_writer: nil)
    @lookup = lookup
    @fact_writer = fact_writer
  end

  # Returns a Ref to the existing record a candidate describes, or nil.
  def find(kind, payload)
    found =
      case kind
      when "organization" then lookup.find_organization(name: payload["name"], domain: payload["domain"])
      when "facility" then lookup.find_facility(name: payload["name"], nrc_docket: payload["nrc_docket"])
      end

    Ref.new(type: LOOKUP_TYPES.fetch(kind), id: found.id) if found
  end

  # Writes a candidate as a verified fact, with the source it came from as
  # evidence. Returns a WriteResult; never raises on validation problems.
  def write_fact(candidate, confidence:, crawl_run:)
    result = fact_writer.write(
      kind: candidate.kind,
      attributes: candidate.payload,
      subject: candidate.subject_id && { type: candidate.subject_type, id: candidate.subject_id },
      evidence: {
        source_id: candidate.source_id,
        quote: candidate.quote,
        found_by: "crawler",
        confidence: confidence,
        crawl_run_id: crawl_run.id
      },
      verified_by: "agent:verifier/#{crawl_run.model || 'unknown'}"
    )

    if result.success?
      WriteResult.new(ref: Ref.new(type: result.record_type, id: result.record_id), errors: [])
    else
      WriteResult.new(ref: nil, errors: Array(result.errors).presence || [ "unknown error" ])
    end
  end

  private
    # Resolved lazily so the module loads before #32 lands.
    def lookup = @lookup ||= "Directory::Lookup".constantize
    def fact_writer = @fact_writer ||= "Directory::FactWriter".constantize
end
