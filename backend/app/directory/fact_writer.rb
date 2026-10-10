# Write side of the directory boundary: the one way facts get created or
# updated, by the seed loader and the data quality pipeline alike.
#
# Each call writes one fact together with its evidence and, optionally, a
# verification decision, then recomputes the fact's confidence. Input is
# plain hashes; ids for other records come from Directory::Lookup, and roles
# and technologies are named by key.
#
#   result = Directory::FactWriter.write(:organization_role,
#     { organization_id: ref.id, role: "reactor_vendor" },
#     evidence: [ { source_id: 7, quote: "…", found_by: "crawler", confidence: 0.8 } ],
#     verification: { status: "verified", by: "human:tosin" })
#   result.ok?      # => true
#   result.id       # => id of the organization_role
#   result.created  # => false when it already existed and was updated
#
# Writes are idempotent: an existing fact is found by its natural key (see
# KINDS) and updated, and evidence is matched by source and quote. A failed
# write changes nothing and returns errors instead of raising.
module Directory
  class FactWriter
    # conflicts: { "state" => [stored, incoming] } when a write disagreed with a
    # human-reviewed fact (see protect_human_verified); nothing was written.
    Result = Data.define(:kind, :id, :created, :errors, :conflicts) do
      def initialize(kind:, id:, created:, errors:, conflicts: {}) = super
      def ok? = errors.empty? && conflicts.empty?
      def conflict? = conflicts.any?
    end

    # Raised inside a write to undo it and report the disagreement.
    class Conflict < StandardError
      attr_reader :id, :conflicts

      def initialize(id, conflicts)
        @id = id
        @conflicts = conflicts
        super(conflicts.map { |name, (stored, incoming)| "human-verified #{name} is #{stored}; this source says #{incoming}" }.join("; "))
      end
    end

    # Never compared for conflicts: names vary by legal form and spelling
    # (aliases cover that), and slugs are internal.
    NOT_COMPARED = %i[name slug].freeze

    class Invalid < StandardError; end

    # attributes: what callers may set. Natural keys are how an existing
    # fact is found, so the same input never creates a second row.
    KINDS = {
      organization: {
        model: Organization,
        attributes: %i[name slug legal_name website domain description hq_city hq_state country_code founded_year status aliases]
      },
      organization_role: { model: OrganizationRole, attributes: %i[organization_id role] },
      organization_technology: { model: OrganizationTechnology, attributes: %i[organization_id technology] },
      facility: {
        model: Facility,
        attributes: %i[name slug parent_id facility_type status technology reactor_type capacity_mw nrc_docket
          city state country_code latitude longitude aliases]
      },
      relationship: {
        model: Relationship,
        attributes: %i[from_organization_id to_organization_id relationship_type description started_on ended_on]
      },
      facility_relationship: {
        model: FacilityRelationship,
        attributes: %i[organization_id facility_id relationship_type ownership_pct description started_on ended_on]
      }
    }.freeze

    EVIDENCE_ATTRIBUTES = %i[source_id quote found_by confidence crawl_run_id].freeze

    def self.write(...) = new.write(...)
    def self.fill_site_from_unit(...) = new.fill_site_from_unit(...)

    # Fills a site's blank fields (from fields:) with its unit's stored
    # values, with evidence, in one transaction that locks the unit and then
    # the site. Only a verified unit speaks for its site, and only for fields
    # still blank once both are locked, so a decision or a fill made
    # meanwhile is seen. A protected write: a rejected site isn't changed (an
    # error is returned), and when a human reviewed the site, a unit value
    # that disagrees with one the site has is reported as a conflict and
    # nothing is written. nil when there's nothing to fill.
    def fill_site_from_unit(unit_id, fields:, evidence:)
      ActiveRecord::Base.transaction(requires_new: true) do
        unit = Facility.lock.find_by(id: unit_id)
        next unless unit&.parent_id && unit.verified?

        site = Facility.lock.find(unit.parent_id)
        stated = fields.to_h { |name| [ name.to_sym, unit.public_send(name) ] }.compact_blank
        if site.human_reviewed? && !site.rejected? && (conflicts = conflicts_with(site, stated)).any?
          raise Conflict.new(site.id, conflicts)
        end
        values = stated.select { |name, _| site.public_send(name).blank? }
        next if values.empty?

        write(:facility, values.merge(id: site.id), fill_blank: true, protect_human_verified: true, evidence:)
      end
    rescue Conflict => e
      Result.new(kind: :facility, id: e.id, created: false, errors: [ e.message ], conflicts: e.conflicts)
    end

    # kind: a key of KINDS. attributes may include :id to update a known row.
    # verification: { status: "pending" | "verified" | "rejected", by: "human:tosin" }
    # fill_blank: true sets only attributes that are blank on an existing row,
    # so new data can complete a record without overwriting anything.
    # protect_human_verified: true treats a row a human has verified (or
    # rejected) as curated, so a human's decision is never overwritten:
    # - a rejected row (by anyone) isn't changed at all (an error is returned)
    # - if an incoming value disagrees with a stored one, nothing is written
    #   (no attributes, evidence or confidence change) and the result's
    #   conflicts say what disagreed, for review
    # - otherwise only blank attributes are filled, evidence is added, and the
    #   verification is left alone
    # Automated writers pass this.
    def write(kind, attributes, evidence: [], verification: nil, fill_blank: false, protect_human_verified: false)
      kind = kind.to_sym
      spec = KINDS[kind] or return failure(kind, "unknown kind #{kind.inspect}")
      attributes = attributes.to_h.symbolize_keys
      unknown = attributes.keys - spec[:attributes] - [ :id ]
      return failure(kind, "unknown attributes: #{unknown.join(", ")}") if unknown.any?

      record = nil
      created = false
      ActiveRecord::Base.transaction(requires_new: true) do
        record = find(kind, spec[:model], attributes) || spec[:model].new
        created = record.new_record?
        # Locked, so a human's decision made while this write runs is seen.
        record.lock! if protect_human_verified && !created
        # A rejected fact (by a human, or a retired proposal) only changes by a human's hand.
        if protect_human_verified && !created && record.rejected?
          raise Invalid, "#{record.model_name.human} was rejected by #{record.verified_by || 'review'}; not changed"
        end
        # No automated unit under a rejected site; the site is locked, so a
        # rejection made while this write runs is seen.
        if protect_human_verified && kind == :facility && attributes[:parent_id] &&
            (site = Facility.lock.find_by(id: attributes[:parent_id]))&.rejected?
          raise Invalid, "site #{site.name} was rejected by #{site.verified_by || 'review'}; no units under it"
        end
        curated = protect_human_verified && !created && record.human_reviewed?
        changes = model_attributes(kind, attributes)
        # A plant found by its docket, name or an alias keeps its name: writing
        # "Three Mile Island Unit 1" updates Crane, it doesn't rename it. Only a
        # write by id renames.
        changes.delete(:name) if kind == :facility && !created && !attributes.key?(:id)
        check_facility_name(record, changes[:name]) if kind == :facility && changes[:name]
        if curated && (conflicts = conflicts_with(record, changes)).any?
          raise Conflict.new(record.id, conflicts)
        end
        changes = changes.select { |name, _| record.public_send(name).blank? } if (fill_blank || curated) && !created
        record.assign_attributes(changes)
        record.save!

        write_aliases(record, [ record.name, *attributes[:aliases] ]) if kind == :organization
        if kind == :facility
          # A name that was one of the plant's aliases is now its name.
          record.aliases.where(normalized_alias: FacilityAlias.normalize(record.name)).delete_all
          write_facility_aliases(record, attributes[:aliases])
        end
        Array(evidence).each { |item| write_evidence(record, item) }
        apply_verification(record, verification) if verification && !curated
        record.recompute_confidence!
      end

      Result.new(kind:, id: record.id, created:, errors: [])
    rescue Conflict => e
      Result.new(kind:, id: e.id, created: false, errors: [ e.message ], conflicts: e.conflicts)
    rescue Invalid, ArgumentError => e
      failure(kind, e.message)
    rescue ActiveRecord::RecordInvalid => e
      failure(kind, e.record.errors.full_messages.map { |m| "#{e.record.model_name.human}: #{m}" })
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::CheckViolation,
      ActiveRecord::NotNullViolation => e
      failure(kind, e.message.lines.first.strip)
    end

    private
      # Incoming values that differ from the stored ones, where both are
      # present: { "state" => ["NJ", "DE"] }. Websites compare by domain.
      def conflicts_with(record, changes)
        changes.each_with_object({}) do |(name, incoming), found|
          next if NOT_COMPARED.include?(name.to_sym)

          stored = record.public_send(name)
          next if incoming.blank? || stored.blank?
          next if same_value?(record, name, stored, incoming)

          found[name.to_s] = [ shown(stored), shown(incoming) ]
        end
      end

      def same_value?(record, name, stored, incoming)
        if name.to_sym == :website
          # Same site if the same domain; a URL with no readable domain only equals itself.
          domains = [ stored, incoming ].map { |url| Organization.domain_from(url) }
          return domains.all?(&:present?) ? domains.uniq.one? : stored.strip == incoming.strip
        end
        return stored == incoming if incoming.is_a?(ActiveRecord::Base)

        # Compared as the model would store it ("us" is "US" once normalized).
        incoming = record.class.normalize_value_for(name.to_sym, incoming)
        stored == record.class.type_for_attribute(name.to_s).cast(incoming)
      end

      def shown(value) = value.respond_to?(:key) ? value.key : value.to_s

      def failure(kind, errors)
        Result.new(kind:, id: nil, created: false, errors: Array(errors))
      end

      # Finds the existing row for this fact, or nil.
      def find(kind, model, attrs)
        return model.find_by(id: attrs[:id]) || raise(Invalid, "no #{kind} with id #{attrs[:id]}") if attrs[:id]

        case kind
        when :organization
          ref = [ attrs[:name], *attrs[:aliases] ].compact.lazy.filter_map { |name| Lookup.organization(name:) }.first
          domain = attrs.key?(:domain) ? attrs[:domain] : Organization.domain_from(attrs[:website])
          ref ||= Lookup.organization(domain:) if domain.present?
          Organization.find(ref.id) if ref
        when :facility
          ref = Lookup.facility(nrc_docket: attrs[:nrc_docket]) if attrs[:nrc_docket].present?
          ref ||= [ attrs[:name], *attrs[:aliases] ].compact_blank.lazy.filter_map { |name| Lookup.facility(name:) }.first
          Facility.find(ref.id) if ref
        when :organization_role
          model.find_by(organization_id: attrs[:organization_id], role: lookup_row(Role, attrs[:role]))
        when :organization_technology
          model.find_by(organization_id: attrs[:organization_id], technology: lookup_row(Technology, attrs[:technology]))
        when :relationship
          model.find_by(attrs.slice(:from_organization_id, :to_organization_id, :relationship_type))
        when :facility_relationship
          model.find_by(attrs.slice(:organization_id, :facility_id, :relationship_type))
        end
      end

      # Turns caller input into model attributes: role/technology keys become
      # records, an organization's domain defaults to its website's (pass
      # domain: nil to leave it blank), and :aliases is handled separately.
      def model_attributes(kind, attrs)
        attrs = attrs.except(:id, :aliases)
        attrs[:domain] = Organization.domain_from(attrs[:website]) if kind == :organization && attrs[:website] && !attrs.key?(:domain)
        attrs[:role] = lookup_row(Role, attrs[:role]) if attrs.key?(:role)
        attrs[:technology] = lookup_row(Technology, attrs[:technology]) if attrs.key?(:technology) && attrs[:technology]
        attrs
      end

      def lookup_row(model, key)
        model.find_by(key: key.to_s) || raise(Invalid, "unknown #{model.model_name.singular} #{key.inspect}")
      end

      # The organization's own name is stored as an alias too, so
      # Lookup.organization(name:) only ever has to check aliases.
      def write_aliases(organization, names)
        names.compact_blank.uniq.each do |name|
          normalized = OrganizationAlias.normalize(name)
          existing = OrganizationAlias.find_by(normalized_alias: normalized)
          if existing.nil?
            organization.aliases.create!(alias: name)
          elsif existing.organization_id != organization.id
            raise Invalid, "alias #{name.inspect} already belongs to #{existing.organization.name}"
          end
        end
      end

      # A facility's other names. Its own name isn't stored (facility names
      # aren't unique), so a name that is another facility's is an error, as
      # is an alias another facility already has.
      # A plant can't take a name that's another plant's alias: the alias
      # would still find the other plant under some spellings.
      def check_facility_name(facility, name)
        owner = FacilityAlias.find_by(normalized_alias: FacilityAlias.normalize(name))
        return if owner.nil? || owner.facility_id == facility.id

        raise Invalid, "name #{name.inspect} is an alias of #{owner.facility.name}"
      end

      def write_facility_aliases(facility, names)
        names.to_a.compact_blank.uniq.each do |name|
          normalized = FacilityAlias.normalize(name)
          next if FacilityAlias.normalize(facility.name) == normalized

          existing = FacilityAlias.find_by(normalized_alias: normalized)
          raise Invalid, "alias #{name.inspect} already belongs to #{existing.facility.name}" if existing && existing.facility_id != facility.id
          next if existing

          named = Facility.where.not(id: facility.id).find_by("lower(name) = ?", name.strip.downcase)
          raise Invalid, "alias #{name.inspect} is the name of another facility" if named

          facility.aliases.create!(alias: name)
        end
      end

      def write_evidence(record, item)
        item = item.to_h.symbolize_keys
        unknown = item.keys - EVIDENCE_ATTRIBUTES
        raise Invalid, "unknown evidence attributes: #{unknown.join(", ")}" if unknown.any?

        row = record.evidence.find_or_initialize_by(source_id: item[:source_id], quote: item[:quote])
        row.assign_attributes(item.slice(:found_by, :confidence, :crawl_run_id))
        row.save!
      end

      # Re-applying the same decision leaves verified_at alone, so re-runs
      # don't look like fresh reviews.
      def apply_verification(record, verification)
        status, by = verification.to_h.symbolize_keys.values_at(:status, :by)
        return if record.verification_status == status.to_s && record.verified_by == by

        record.update!(verification_status: status, verified_by: by, verified_at: status.to_s == "pending" ? nil : Time.current)
      end
  end
end
