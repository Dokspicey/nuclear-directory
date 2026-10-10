# Links each new candidate to the directory record it describes, so the
# directory never gets duplicates. Shared by all plug-ins.
#
# For every new candidate, one of three things happens:
# - Found: an exact match on NRC docket, domain or name/alias. The candidate
#   is attached to that record and nothing is written yet: its quote becomes
#   evidence (and, for an organization, its name an alias) only when a human
#   approves it (DataQuality::Review.approve).
# - Not found: a new pending record is proposed with the quote as evidence.
# - Ambiguous: identifiers point at different records, or a similar record
#   exists ("Vogtle 3" vs "Plant Vogtle Units 3 & 4"). The candidate goes to
#   needs_review with the reason. Never merged automatically.
#
# Either way a matched candidate ends up with a subject. Verify then
# recommends, and a human decides whether that fact is published. Records go first, so links (who operates
# what) can find records proposed earlier in the same run.
#
# Payload for links: each end is a nested hash identifying the record, e.g.
#   facility_relationship: { "organization" => { "name" => "…" },
#     "facility" => { "name" => "…", "nrc_docket" => "05000424" }, "relationship_type" => "operates" }
# See app/data_quality/README.md.
class DataQuality::Stages::Match < DataQuality::Stage
  # Facilities before organizations: company names are checked against the
  # plant names they may end in ("NextEra Energy Seabrook"), so plants proposed
  # in the same run must already be known. Records before links.
  ORDER = %w[facility organization organization_role organization_technology relationship facility_relationship
    organization_alias].freeze

  # Payload keys that name another record, and what kind of record each is.
  LINK_ENDS = {
    "organization_role" => { "organization" => :organization },
    "organization_technology" => { "organization" => :organization },
    "relationship" => { "from_organization" => :organization, "to_organization" => :organization },
    "facility_relationship" => { "organization" => :organization, "facility" => :facility }
  }.freeze
  LINK_KEYS = {
    "organization_role" => %w[role],
    "organization_technology" => %w[technology],
    "relationship" => %w[relationship_type],
    "facility_relationship" => %w[relationship_type]
  }.freeze

  Found = Data.define(:record, :by)
  Review = Data.define(:reason)
  # A new unit that belongs under an existing site record.
  Under = Data.define(:site)

  private
    def perform(run)
      @run = run
      @stats = { "candidates" => 0, "matched" => 0, "proposed" => 0, "needs_review" => 0, "waiting" => 0, "write_errors" => 0 }

      one_run_at_a_time do
        # Every company name in this run counts as an owner for the brand
        # rule from the start, so matching doesn't depend on candidate order.
        directory.owner_hints = candidates.status_new.where(kind: "organization").filter_map { |c| c.payload["name"] }
        ORDER.each do |kind|
          candidates.status_new.where(kind: kind).find_each { |candidate| match(candidate) }
        end
      end

      @stats
    end

    # Match runs can race when inserting similar records even across source
    # kinds, so only one runs at a time. A Postgres advisory lock, released
    # when the run ends.
    def one_run_at_a_time
      connection = Candidate.connection
      key = Zlib.crc32("data_quality:match")
      locked = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      raise "Another match run is already in progress" unless locked

      yield
    ensure
      connection.select_value("SELECT pg_advisory_unlock(#{key})") if locked
    end

    def match(candidate)
      @stats["candidates"] += 1
      payload = candidate.payload.to_h

      case candidate.kind
      when "facility" then payload.key?("identify") ? match_enrichment(candidate, payload["identify"]) : match_record(candidate, payload)
      when "organization" then match_record(candidate, payload)
      when *LINK_ENDS.keys then match_link(candidate, payload)
      else review(candidate, "#{candidate.kind} candidates aren't matched automatically yet")
      end
    end

    def match_record(candidate, payload)
      case (found = resolve(candidate.kind.to_sym, payload))
      when Review then review(candidate, found.reason)
      when Found
        # Attach only: nothing is written to an existing record until a human approves it.
        attach(candidate, found.record, "Matched existing #{found.record.name} (by #{found.by})")
      when Under
        write(candidate, payload.symbolize_keys.merge(parent_id: found.site.id), existing: false,
          note: "New pending unit under the existing site #{found.site.name}")
      else
        # FactWriter may still find a record by a key match didn't use; trust its answer.
        write(candidate, proposal(candidate, payload))
      end
    end

    # One company per brand: a new company from a per-plant or regional legal
    # entity ("NextEra Energy Seabrook, LLC") is named after its brand
    # ("NextEra Energy"), with the legal name kept as an alias.
    def proposal(candidate, payload)
      attributes = payload.symbolize_keys
      brand = directory.brand_name(attributes[:name]) if candidate.kind_organization? && attributes[:name].present?
      return attributes unless brand

      attributes.merge(name: brand, aliases: [ *attributes[:aliases], attributes[:name] ])
    end

    # Only the fields that identify a link (LINK_KEYS and the resolved ends)
    # are written at match; its description, dates and ownership are applied
    # when it's published, so an existing link never takes on unverified
    # values. (A new link is pending, so nothing public is missing meanwhile;
    # like any proposal, it gets the quote as evidence.)
    def match_link(candidate, payload)
      attributes = payload.slice(*LINK_KEYS.fetch(candidate.kind)).symbolize_keys

      LINK_ENDS.fetch(candidate.kind).each do |key, type|
        unless payload.key?(key)
          return review(candidate, "payload has no #{key}")
        end
        unless payload[key].is_a?(Hash)
          return review(candidate, "payload #{key} must be an object")
        end

        case (found = resolve(type, payload[key]))
        when Review then return review(candidate, "#{key}: #{found.reason}")
        when Found then attributes[:"#{key}_id"] = found.record.id
        else return review(candidate, "#{key} #{label(payload[key]).inspect} isn't in the directory yet")
        end
      end

      write(candidate, attributes, evidence: false)
    end

    # Found, Review or nil (nothing like it exists). A closed record, one that
    # was rejected (a retired proposal, or one a human turned down) or that a
    # human unpublished, is never attached to: the candidate goes to review.
    def resolve(type, payload)
      found = type == :organization ? resolve_organization(payload) : resolve_facility(payload)
      if found.is_a?(Found) && found.record.closed?
        return Review.new("matches #{found.record.name} (by #{found.by}), which was #{found.record.decision}. " \
          "The same thing again, or a new record?")
      end
      if found.is_a?(Under) && found.site.closed?
        return Review.new("looks like a unit of #{found.site.name}, which was #{found.site.decision}. " \
          "Under it anyway, or its own record?")
      end

      found
    end

    def resolve_organization(payload)
      name = payload["name"].presence
      # FactWriter derives a domain from the website unless domain was supplied.
      domain = payload.key?("domain") ? payload["domain"].presence : payload["website"].presence
      by_name = directory.organization(name:) if name
      by_domain = directory.organization(domain:) if domain

      if by_name && by_domain && by_name.id != by_domain.id
        return Review.new("name matches #{by_name.name} but domain matches #{by_domain.name}")
      end
      return Found.new(by_name, "name") if by_name

      # One company per brand: a legal-entity variant of exactly one existing
      # company is that company. Two candidates for the brand is ambiguous. A
      # brand counts as a name match, so it must agree with the domain too, and
      # a shared brand goes to review even when the domain picks one of them.
      brand = name ? directory.same_brand_organizations(name) : []
      if brand.many?
        domain_note = " (its domain matches #{by_domain.name})" if by_domain
        return Review.new("#{name.inspect} could be the same brand as #{brand.map(&:name).join(' or ')}#{domain_note}. Which one?")
      end
      if by_domain && brand.one? && brand.first.id != by_domain.id
        return Review.new("name is the brand of #{brand.first.name} but domain matches #{by_domain.name}")
      end
      # A per-plant name whose brand has no company yet ("NextEra Energy
      # Seabrook, LLC") must still agree with a company found by domain.
      if by_domain && brand.empty? && (inferred = directory.brand_name(name.to_s)) &&
          directory.brand_key(inferred) != directory.brand_key(by_domain.name)
        return Review.new("name is a #{inferred} company but domain matches #{by_domain.name}")
      end
      return Found.new(by_domain, "domain") if by_domain
      return Found.new(brand.first, "brand, a legal-entity variant of its name") if brand.one?

      similar(directory.similar_organizations(name.to_s), name)
    end

    def resolve_facility(payload)
      name, docket = payload.values_at("name", "nrc_docket").map(&:presence)
      by_docket = directory.facility(nrc_docket: docket) if docket
      by_name = directory.facility(name:) if name
      # A candidate's other names find its plant here, so it's attached
      # without writing; its aliases are added only when it's approved.
      by_name ||= Array(payload["aliases"]).compact_blank.lazy.filter_map { |other| directory.facility(name: other) }.first

      if by_docket && by_name && by_docket.id != by_name.id
        return Review.new("docket matches #{by_docket.name} but name matches #{by_name.name}")
      end
      return Found.new(by_docket, "NRC docket") if by_docket
      if by_name && docket && by_name.nrc_docket.present?
        return Review.new("name matches #{by_name.name}, which has a different docket (#{by_name.nrc_docket})")
      end
      return Found.new(by_name, "name") if by_name

      # Units with different dockets are different units, not duplicates.
      others = directory.similar_facilities(name.to_s).reject do |facility|
        docket && facility.nrc_docket.present? && facility.nrc_docket != docket
      end
      site_for_unit(others, name, docket) || similar(others, name)
    end

    # An NRC unit ("Vogtle 3", with a docket) under a site-level record
    # ("Plant Vogtle Units 3 & 4", no docket): Under the site when that is the
    # only similar record, it is top-level, and its name covers this unit.
    # Names that list no units cover them all. Anything less clear is nil, so
    # the caller sends it to review.
    def site_for_unit(others, name, docket)
      return unless docket && others.one?

      site = others.first
      return unless site.nrc_docket.blank? && site.parent_id.nil?

      covered = site_unit_numbers(site.name)
      return Under.new(site) if covered.empty? || covered.include?(unit_number(name))

      Review.new("#{name.inspect} looks like a unit of #{site.name}, but that record only covers " \
        "unit #{covered.join(' & ')}. Add it under the site, or as its own record?")
    end

    # An enrichment source (e.g. EIA) adds values to an NRC unit that already
    # exists and never creates one. identify: { "name", "state", "unit" }.
    # The unit is the NRC unit whose name best fits (most shared distinctive
    # words, state as a tie-break; see Lookup.facility_units) and has the same
    # unit number; a plant with a single, unnumbered NRC unit takes that unit.
    # If no unit fits yet (NRC data not loaded, or the unit's own NRC record is
    # still in review), the candidate stays new and is retried on the next run.
    # More than one fit goes to review.
    def match_enrichment(candidate, identify)
      name, state, unit = identify.to_h.values_at("name", "state", "unit")
      number = unit.to_s[/\d+/]&.to_i
      units, same_number = enrichment_fits(name, state, number)
      chosen = same_number.first if same_number.one?
      chosen ||= units.first if same_number.empty? && units.one? && unit_number(units.first.name).nil?
      label = "#{name} unit #{unit} (#{state})"

      if chosen&.rejected?
        review(candidate, "#{label} would be NRC unit #{chosen.name}, which was rejected")
      elsif chosen
        # Attach only: the values (and their evidence) are written when verify publishes.
        attach(candidate, chosen, "#{label} is NRC unit #{chosen.name}")
      elsif same_number.many? || (units.many? && units.none? { |record| unit_number(record.name) })
        review(candidate, "#{label} could be #{(same_number.presence || units).map(&:name).join(' or ')}")
      else
        # Includes a plant whose other units exist but not this one (Vogtle 1
        # while only Vogtle 3 and 4 are in the directory).
        @stats["waiting"] += 1
        candidate.update!(notes: "No NRC unit for #{label} yet; retried on the next match run")
      end
    end

    # [units that fit the name, those of them with this unit number]
    def enrichment_fits(name, state, number)
      units = directory.facility_units(name: name.to_s, state: state.presence)
      [ units, units.select { |record| unit_number(record.name) == number } ]
    end

    # "Vogtle 3" => 3. A name without a trailing number ("Palisades") is nil.
    def unit_number(name) = name.to_s[/\s(\d+)\s*\z/, 1]&.to_i

    # "Plant Vogtle Units 3 & 4" => [3, 4]; "Susquehanna Steam Electric Station" => [].
    def site_unit_numbers(name)
      name.to_s.scan(/\bunits?\s+((?:\d+(?:\s*(?:,|&|and)\s*)?)+)/i).flatten.flat_map { |list| list.scan(/\d+/) }.map(&:to_i)
    end

    def similar(records, name)
      return if records.empty?

      Review.new("no exact match for #{name.inspect}, but similar: #{records.map(&:name).join('; ')}. " \
        "Same record, or a new one?")
    end

    # existing: whether the candidate describes a record that already exists.
    # Links don't know until FactWriter finds (or doesn't find) the link.
    def attach(candidate, record, note)
      @stats["matched"] += 1
      candidate.update!(status: "matched", subject_type: record.type, subject_id: record.id, notes: note,
        proposed_subject: false)
    end

    # evidence: false for links, which may already exist; their quote is added when a human approves.
    # The write, a new link's quote and the candidate's update happen in one
    # transaction, so a stop part-way leaves nothing half-done for a rerun to
    # mistake for an existing record.
    def write(candidate, attributes, existing: nil, note: nil, evidence: true)
      result = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        result = directory.write_pending(candidate.kind, attributes, candidate:, crawl_run: @run, evidence:)
        # A link written without evidence (so an existing one isn't changed) that
        # turned out to be new is a proposal, and a proposal carries its quote.
        if result.success? && result.created && !evidence
          with_quote = directory.write_pending(candidate.kind, { id: result.ref.id }, candidate:, crawl_run: @run)
          unless with_quote.success?
            result = with_quote
            raise ActiveRecord::Rollback
          end
        end
        next unless result.success?

        existing = !result.created if existing.nil?
        note ||= existing ? "Matched an existing record" : "No existing record; proposed a new pending one"
        # Remembered so a rejection can retire what match created, and only that.
        candidate.update!(status: "matched", subject_type: result.ref.type, subject_id: result.ref.id, notes: note,
          proposed_subject: result.created)
      end

      if result.success?
        @stats[existing ? "matched" : "proposed"] += 1
      else
        review(candidate, "Directory rejected the write: #{result.errors.join('; ')}", write_error: true)
      end
    end

    def review(candidate, reason, write_error: false)
      @stats["write_errors"] += 1 if write_error
      @stats["needs_review"] += 1
      candidate.update!(status: "needs_review", notes: reason)
    end

    def label(payload) = payload["name"] || payload["nrc_docket"] || payload.to_s
end
