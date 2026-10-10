# Links each new candidate to the directory record it describes, so the
# directory never gets duplicates. Shared by all plug-ins.
#
# For every new candidate, one of three things happens:
# - Found: an exact match on NRC docket, domain or name/alias. The candidate
#   is attached to that record, its quote is added as evidence, and for an
#   organization its name is added as an alias.
# - Not found: a new pending record is proposed with the quote as evidence.
# - Ambiguous: identifiers point at different records, or a similar record
#   exists ("Vogtle 3" vs "Plant Vogtle Units 3 & 4"). The candidate goes to
#   needs_review with the reason. Never merged automatically.
#
# Either way a matched candidate ends up with a subject, and verify decides
# whether that fact is published. Records go first, so links (who operates
# what) can find records proposed earlier in the same run.
#
# Payload for links: each end is a nested hash identifying the record, e.g.
#   facility_relationship: { "organization" => { "name" => "…" },
#     "facility" => { "name" => "…", "nrc_docket" => "05000424" }, "relationship_type" => "operates" }
# See app/data_quality/README.md.
class DataQuality::Stages::Match < DataQuality::Stage
  ORDER = %w[organization facility organization_role organization_technology relationship facility_relationship
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
      @stats = { "candidates" => 0, "matched" => 0, "proposed" => 0, "needs_review" => 0, "write_errors" => 0 }

      one_run_at_a_time do
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
      when "organization", "facility" then match_record(candidate, payload)
      when *LINK_ENDS.keys then match_link(candidate, payload)
      else review(candidate, "#{candidate.kind} candidates aren't matched automatically yet")
      end
    end

    def match_record(candidate, payload)
      case (found = resolve(candidate.kind.to_sym, payload))
      when Review then review(candidate, found.reason)
      when Found
        # Attach only; the name it was found under becomes an alias if and when it's published.
        write(candidate, { id: found.record.id }, existing: true, note: "Matched existing #{found.record.name} (by #{found.by})")
      when Under
        write(candidate, payload.symbolize_keys.merge(parent_id: found.site.id), existing: false,
          note: "New pending unit under the existing site #{found.site.name}")
      else
        # FactWriter may still find a record by a key match didn't use; trust its answer.
        write(candidate, payload.symbolize_keys)
      end
    end

    # Only the fields that identify a link (LINK_KEYS and the resolved ends)
    # are written at match; its description, dates and ownership are applied
    # when it's published, so an existing link never takes on unverified
    # values. (A new link is pending, so nothing public is missing meanwhile.)
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

      write(candidate, attributes)
    end

    # Found, Review or nil (nothing like it exists). A record that was rejected
    # (a retired proposal, or one a human turned down) is never attached to:
    # the candidate goes to review instead.
    def resolve(type, payload)
      found = type == :organization ? resolve_organization(payload) : resolve_facility(payload)
      if found.is_a?(Found) && found.record.rejected?
        return Review.new("matches #{found.record.name} (by #{found.by}), which was rejected. The same thing again, or a new record?")
      end
      if found.is_a?(Under) && found.site.rejected?
        return Review.new("looks like a unit of #{found.site.name}, which was rejected. Under it anyway, or its own record?")
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
      return Found.new(by_domain, "domain") if by_domain

      similar(directory.similar_organizations(name.to_s), name)
    end

    def resolve_facility(payload)
      name, docket = payload.values_at("name", "nrc_docket").map(&:presence)
      by_docket = directory.facility(nrc_docket: docket) if docket
      by_name = directory.facility(name:) if name

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
    def write(candidate, attributes, existing: nil, note: nil)
      result = directory.write_pending(candidate.kind, attributes, candidate:, crawl_run: @run)
      unless result.success?
        return review(candidate, "Directory rejected the write: #{result.errors.join('; ')}", write_error: true)
      end

      existing = !result.created if existing.nil?
      @stats[existing ? "matched" : "proposed"] += 1
      note ||= existing ? "Matched an existing record" : "No existing record; proposed a new pending one"
      # Remembered so a rejection can retire what match created, and only that.
      candidate.update!(status: "matched", subject_type: result.ref.type, subject_id: result.ref.id, notes: note,
        proposed_subject: result.created)
    end

    def review(candidate, reason, write_error: false)
      @stats["write_errors"] += 1 if write_error
      @stats["needs_review"] += 1
      candidate.update!(status: "needs_review", notes: reason)
    end

    def label(payload) = payload["name"] || payload["nrc_docket"] || payload.to_s
end
