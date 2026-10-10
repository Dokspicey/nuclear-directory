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
  # values: a link's stored values ({ "ownership_pct" => 45.7, ... }), else nil.
  Record = Data.define(:type, :id, :name, :domain, :nrc_docket, :parent_id, :facility_type, :status, :state, :country_code,
    :verification_status, :verified_by, :verified_at, :values) do
    def ref = Ref.new(type:, id:)
    def rejected? = verification_status == "rejected"
    def unpublished? = verification_status == "unpublished"
    # Rejected or unpublished: a decision the pipeline never reopens on its own.
    def closed? = rejected? || unpublished?
    def decision = "#{verification_status} by #{verified_by || 'review'}#{" on #{verified_at.to_date}" if verified_at}"
  end
  # conflicts: { "state" => [stored, incoming] } when the write disagreed with
  # a human-verified fact; nothing was written, and ref points at that fact.
  WriteResult = Data.define(:ref, :errors, :created, :conflicts) do
    def initialize(ref:, errors:, created: false, conflicts: {}) = super
    def success? = errors.empty? && conflicts.empty?
    def conflict? = conflicts.any?
  end

  # Kinds whose payload names other records instead of carrying attributes;
  # the match stage resolves those names to ids and writes the fact.
  LINK_KINDS = %w[organization_role organization_technology relationship facility_relationship].freeze
  LINK_ENDS = %w[organization facility from_organization to_organization].freeze

  def initialize(lookup: nil, fact_writer: nil)
    @lookup = lookup
    @fact_writer = fact_writer
  end

  # Exact lookups. Pass one keyword; returns a Record or nil.
  def organization(name: nil, domain: nil)
    record("Organization", lookup.organization(name:, domain:))
  end

  def facility(id: nil, name: nil, nrc_docket: nil)
    record("Facility", lookup.facility(id:, name:, nrc_docket:))
  end

  # The fact a candidate is attached to (any kind, links included), with its
  # current decision, or nil when it has none, with the values verify and the
  # admin compare (a link's in `values`).
  def attached_record(candidate)
    return unless candidate.subject_id

    case candidate.subject_type
    when "Organization" then record("Organization", lookup.organization(id: candidate.subject_id))
    when "Facility" then record("Facility", lookup.facility(id: candidate.subject_id))
    else fact(type: candidate.subject_type, id: candidate.subject_id)
    end
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
  # new fact starts pending and an existing one keeps its status. A fact a
  # human has verified only gets its blanks filled; one a human rejected or
  # unpublished isn't changed (the result has an error).
  # evidence: false writes only the record (a link that may already exist
  # gets its evidence on publish, so nothing unverified lands on it early).
  def write_pending(kind, attributes, candidate:, crawl_run:, evidence: true)
    items = evidence ? [ { source_id: candidate.source_id, quote: candidate.quote, found_by: "crawler", crawl_run_id: crawl_run.id } ] : []
    result = fact_writer.write(kind, attributes, protect_human_verified: true, evidence: items)
    write_result(result)
  end

  # Writes a candidate as a verified fact, with the source it came from as
  # evidence. A matched candidate updates its record (attributes id:); for
  # link kinds the ends were resolved by match, so the rest of the payload is
  # sent. A fact a human has verified is never overwritten: only its blank
  # attributes are filled and its verification stays. A fact a human rejected
  # or unpublished isn't changed at all; the result has an error instead (FactWriter
  # protect_human_verified). Returns a WriteResult; never raises on
  # validation problems.
  #
  # by: a human ("human:tosin") approving it in the admin
  # (DataQuality::Review). A human is the authority, so their write isn't
  # protected: it applies the candidate's values even over a human-verified
  # fact, and records the candidate and run in the audit trail. Without by:,
  # it's the automated writer described above.
  def write_fact(candidate, confidence:, crawl_run:, by: nil, reason: nil)
    attributes = candidate.payload.except(*LINK_ENDS).symbolize_keys
    attributes[:id] = candidate.subject_id if candidate.subject_id
    if candidate.kind == "organization"
      # The name it was found under becomes an alias only once a verdict accepts
      # it, and a matched company keeps its own name.
      attributes[:aliases] = [ *attributes[:aliases], attributes[:name] ].compact_blank.uniq
      attributes.delete(:name) if candidate.subject_id
    end

    verification =
      if by
        { status: "verified", by:, reason:, context: { "candidate_id" => candidate.id, "crawl_run_id" => crawl_run&.id } }.compact
      else
        { status: "verified", by: "agent:verifier/#{crawl_run&.model || 'unknown'}" }
      end

    result = fact_writer.write(
      candidate.kind,
      attributes,
      evidence: [ {
        source_id: candidate.source_id,
        quote: candidate.quote,
        found_by: "crawler",
        confidence: confidence,
        crawl_run_id: crawl_run&.id
      } ],
      verification: verification,
      protect_human_verified: by.nil?
    )
    write_result(result)
  end

  # Marks a record match proposed as rejected, once its candidate is
  # rejected, so lookups stop treating it as a live record. A record a human
  # has reviewed is left alone.
  def retire(candidate, crawl_run:)
    result = fact_writer.write(candidate.kind, { id: candidate.subject_id }, protect_human_verified: true,
      verification: { status: "rejected", by: "agent:verifier/#{crawl_run.model || 'unknown'}" })
    write_result(result)
  end

  # Site fields a verified unit can fill in when the site has none.
  SITE_FIELDS_FROM_UNIT = %w[state facility_type status country_code].freeze

  # After a unit is verified, fills its site's blank fields (state, type,
  # status) from the unit, with the unit's quote as evidence. Never
  # overwrites a field the site already has, and leaves the site's
  # verification alone. Returns a WriteResult, or nil when the unit has no site
  # or the site has nothing blank to fill. Only the site's blank fields are
  # sent, so the quote is evidence just for what it fills, and the write is
  # protected like any automated one: a site a human rejected isn't changed
  # (the result has an error).
  # The values come from the unit as stored, not from the candidate, since
  # a curated unit may have kept its own values over the candidate's.
  # Only a unit that ended up verified speaks for its site (a human may have
  # kept it rejected); FactWriter checks that, and which fields are blank,
  # with both records locked.
  def fill_site_from_unit(facility_id, candidate, crawl_run:)
    result = fact_writer.fill_site_from_unit(facility_id, fields: SITE_FIELDS_FROM_UNIT,
      evidence: [ { source_id: candidate.source_id, quote: candidate.quote, found_by: "crawler", crawl_run_id: crawl_run&.id } ])
    write_result(result) if result
  end

  # For the review screens (DataQuality::Review, #85).

  # The six fact kinds, e.g. "organization", "facility_relationship".
  def fact_kinds = "Directory::Lookup::FACT_KINDS".constantize

  # Any fact (links included) with its decision and stored values, or nil.
  def fact(type:, id:)
    state = lookup.fact_state(type:, id:) or return
    record(type, state, values: lookup.fact_attributes(type:, id:))
  end

  # Facts of one kind waiting for a human (Directory::PendingFactRef), oldest first.
  def pending_facts(kind:, after_id: nil, limit: 50) = lookup.pending_facts(kind:, after_id:, limit:)

  # Every verification decision on a fact, newest first (Directory::VerificationEventRef).
  def verification_history(type:, id:) = lookup.verification_history(type:, id:)

  # A human's decision on a directory fact: status "verified" (approve or
  # republish, optionally with edited attributes), "rejected" or
  # "unpublished". Human writes aren't protected; the reason and context go
  # to the audit trail. Returns a WriteResult.
  def decide_fact(kind, id:, status:, by:, reason: nil, attributes: {}, context: nil)
    result = fact_writer.write(kind, attributes.to_h.symbolize_keys.merge(id:),
      verification: { status:, by:, reason:, context: }.compact)
    write_result(result)
  end

  private
    # Resolved lazily so the module has no load-time dependency on the directory.
    def lookup = @lookup ||= "Directory::Lookup".constantize
    def fact_writer = @fact_writer ||= "Directory::FactWriter".constantize

    def record(type, ref, values: nil)
      Record.new(type:, id: ref.id, name: ref.name, domain: ref.try(:domain), nrc_docket: ref.try(:nrc_docket), parent_id: ref.try(:parent_id),
        facility_type: ref.try(:facility_type), status: ref.try(:status), state: ref.try(:state),
        country_code: ref.try(:country_code), verification_status: ref.verification_status,
        verified_by: ref.try(:verified_by), verified_at: ref.try(:verified_at), values:) if ref
    end

    def write_result(result)
      if result.ok?
        WriteResult.new(ref: Ref.new(type: type_for(result.kind), id: result.id), errors: [], created: result.created)
      elsif result.conflict?
        WriteResult.new(ref: Ref.new(type: type_for(result.kind), id: result.id), errors: Array(result.errors),
          conflicts: result.conflicts)
      else
        WriteResult.new(ref: nil, errors: Array(result.errors).presence || [ "unknown error" ])
      end
    end

    # Fact kind => the record type candidates store, e.g. "facility_relationship"
    # => "FacilityRelationship". Kinds are named after their records.
    def type_for(kind) = kind.to_s.camelize
end
