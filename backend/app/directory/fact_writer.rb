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
    Result = Data.define(:kind, :id, :created, :errors) do
      def ok? = errors.empty?
    end

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
          city state country_code latitude longitude]
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

    # kind: a key of KINDS. attributes may include :id to update a known row.
    # verification: { status: "pending" | "verified" | "rejected", by: "human:tosin" }
    # fill_blank: true sets only attributes that are blank on an existing row,
    # so new data can complete a record without overwriting anything.
    # protect_human_verified: true treats a row a human has verified (or
    # rejected) as curated: only its blank attributes are filled and its
    # verification is left alone (evidence is still added). Automated writers
    # pass this, so a human's decision is never overwritten.
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
        curated = protect_human_verified && !created && record.human_reviewed?
        changes = model_attributes(kind, attributes)
        changes = changes.select { |name, _| record.public_send(name).blank? } if (fill_blank || curated) && !created
        record.assign_attributes(changes)
        record.save!

        write_aliases(record, [ record.name, *attributes[:aliases] ]) if kind == :organization
        Array(evidence).each { |item| write_evidence(record, item) }
        apply_verification(record, verification) if verification && !curated
        record.recompute_confidence!
      end

      Result.new(kind:, id: record.id, created:, errors: [])
    rescue Invalid, ArgumentError => e
      failure(kind, e.message)
    rescue ActiveRecord::RecordInvalid => e
      failure(kind, e.record.errors.full_messages.map { |m| "#{e.record.model_name.human}: #{m}" })
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::CheckViolation,
      ActiveRecord::NotNullViolation => e
      failure(kind, e.message.lines.first.strip)
    end

    private
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
          ref ||= Lookup.facility(name: attrs[:name]) if attrs[:name].present?
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
