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
  # Never taken from a payload: which record, which ends, and the slug.
  PAYLOAD_LOCKED = %w[id slug organization_id facility_id from_organization_id to_organization_id].freeze

  def initialize(lookup: nil, fact_writer: nil)
    @owner_hints = []
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

  # Runs the block with the candidate's attached fact locked, unless it was
  # rejected or unpublished meanwhile: then returns that fact's Record and
  # doesn't run the block. A candidate with no fact just runs the block.
  def unless_closed(candidate, &)
    return yield.then { nil } unless candidate.subject_id

    record(candidate.subject_type, fact_writer.while_open(type: candidate.subject_type, id: candidate.subject_id, &))
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

  # Organizations that are the same brand as name (legal-entity variants).
  def same_brand_organizations(name)
    lookup.same_brand_organizations(name, plants: plant_names).map { |ref| record("Organization", ref) }
  end

  # Company names coming up in this run, so the brand rule treats them as
  # owners from the start, whatever order the candidates are matched in.
  attr_reader :owner_hints

  def owner_hints=(names)
    @owner_hints = Array(names).compact_blank.uniq
    @plant_names = nil
  end

  # The brand a per-plant or regional company name stands for
  # ("NextEra Energy Seabrook, LLC" => "NextEra Energy"), or nil.
  def brand_name(name) = lookup.brand_name(name, plants: plant_names)

  # The brand a name reduces to ("NextEra Energy Seabrook, LLC" => "nextera"), or nil.
  def brand_key(name) = lookup.brand_key(name, plants: plant_names)

  def similar_facilities(name)
    lookup.similar_facilities(name).map { |ref| record("Facility", ref) }
  end

  # NRC units whose names fit name: in a state, or (state: nil) anywhere,
  # by a stricter rule. Returns Records.
  def facility_units(name:, state: nil)
    lookup.facility_units(name:, state:).map { |ref| record("Facility", ref) }
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
  #
  # An enrichment candidate (see enrichment?) sets only its values and leaves
  # the record's verification alone, since it doesn't vouch for the record
  # itself; even when a human approves it, it doesn't overwrite a
  # human-verified value (that comes back as a conflict).
  def write_fact(candidate, confidence:, crawl_run:, by: nil, reason: nil)
    # The record written is the one match attached, never an id, a link end or
    # a slug in the payload (payloads aren't validated; Review locks these too).
    attributes = candidate.payload.except(*LINK_ENDS, *PAYLOAD_LOCKED, ENRICHMENT_KEY).symbolize_keys
    attributes[:id] = candidate.subject_id if candidate.subject_id
    if candidate.kind == "organization"
      # The name it was found under becomes an alias only once a verdict accepts
      # it, and a matched company keeps its own name.
      attributes[:aliases] = [ *attributes[:aliases], attributes[:name] ].compact_blank.uniq
      attributes.delete(:name) if candidate.subject_id
    end
    # A matched plant keeps its own name too: a candidate found under one of its
    # aliases ("Three Mile Island Unit 1") mustn't rename Crane.
    attributes.delete(:name) if candidate.kind == "facility" && candidate.subject_id
    enrichment = enrichment?(candidate)
    verification =
      if enrichment then nil
      elsif by
        { status: "verified", by:, reason:, context: { "candidate_id" => candidate.id, "crawl_run_id" => crawl_run&.id } }.compact
      else
        { status: "verified", by: "agent:verifier/#{crawl_run&.model || 'unknown'}" }
      end
    evidence = [ { source_id: candidate.source_id, quote: candidate.quote, found_by: "crawler", confidence:, crawl_run_id: crawl_run&.id } ]
    return write_alias(candidate, verification:, evidence:, by:) if candidate.kind == "organization_alias"

    result = fact_writer.write(candidate.kind, attributes, evidence:, verification:,
      protect_human_verified: by.nil? || enrichment)
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

  # Payload key of an enrichment candidate: how to find the existing record
  # it adds values to. Enrichment never creates records.
  ENRICHMENT_KEY = "identify"

  def enrichment?(candidate) = candidate.payload.to_h.key?(ENRICHMENT_KEY)

  # Site fields a verified unit can fill in when the site has none.
  SITE_FIELDS_FROM_UNIT = %w[state facility_type status country_code latitude longitude].freeze

  # After a unit is verified, fills its site's blank fields (state, type,
  # status) from the unit, with the unit's quote as evidence. Never
  # overwrites a field the site already has, and leaves the site's
  # verification alone. Returns nil when the unit has no site or nothing is
  # left to fill, else a WriteResult: success; an error when a human rejected
  # the site; or a conflict when the unit disagrees with a value a human
  # recorded for the site (nothing written, even if no field was blank). The
  # quote is evidence just for the fields it fills.
  # The values come from the unit as stored, not from the candidate, since
  # a curated unit may have kept its own values over the candidate's.
  # Only a unit that ended up verified speaks for its site (a human may have
  # kept it rejected); FactWriter checks that, and which fields are blank,
  # with both records locked.
  # Only the fields this candidate states are filled, so the site's evidence
  # is the document that stated them (an NRC row doesn't vouch for EIA's
  # coordinates; the EIA candidate fills those when it's published).
  def fill_site_from_unit(facility_id, candidate, crawl_run:)
    stated = candidate.payload.keys & SITE_FIELDS_FROM_UNIT
    return if stated.empty?

    result = fact_writer.fill_site_from_unit(facility_id, fields: stated,
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

  # Whether a fact has any evidence (a source) at all.
  def sourced?(type:, id:) = lookup.sourced?(type:, id:)

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
    # "X is also known as Y": the alias goes on its company, which must be
    # published already (approving an alias doesn't publish a company).
    def write_alias(candidate, verification:, evidence:, by:)
      ends = candidate.payload["organization"].to_h
      company = (organization(name: ends["name"]) if ends["name"].present?) ||
        (organization(domain: ends["domain"]) if ends["domain"].present?)
      unless company
        return WriteResult.new(ref: nil, errors: [ "no company named #{(ends['name'] || ends['domain']).to_s.inspect} to add the alias to" ])
      end
      unless company.verification_status == "verified"
        return WriteResult.new(ref: company.ref, errors: [ "#{company.name} isn't published; approve it first, then this alias" ])
      end
      return WriteResult.new(ref: company.ref, errors: [ "only a human adds an alias" ]) unless by

      alias_name = candidate.payload["alias"].to_s.strip
      return WriteResult.new(ref: company.ref, errors: [ "the alias is blank" ]) if alias_name.empty?

      write_result(fact_writer.write("organization", { id: company.id, aliases: [ alias_name ] }, evidence:,
        verification:, protect_human_verified: false))
    end

    # Resolved lazily so the module has no load-time dependency on the directory.
    def lookup = @lookup ||= "Directory::Lookup".constantize
    def fact_writer = @fact_writer ||= "Directory::FactWriter".constantize

    # Read once and reused for every brand check, until a facility or company is written.
    def plant_names = @plant_names ||= lookup.plant_names(owners: owner_hints)

    def record(type, ref, values: nil)
      Record.new(type:, id: ref.id, name: ref.name, domain: ref.try(:domain), nrc_docket: ref.try(:nrc_docket), parent_id: ref.try(:parent_id),
        facility_type: ref.try(:facility_type), status: ref.try(:status), state: ref.try(:state),
        country_code: ref.try(:country_code), verification_status: ref.verification_status,
        verified_by: ref.try(:verified_by), verified_at: ref.try(:verified_at), values:) if ref
    end

    def write_result(result)
      # Plant names depend on facilities and on company names (owner prefixes).
      @plant_names = nil if result.ok? && %w[facility organization].include?(result.kind.to_s)
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
