require "yaml"

module Seed
  # Loads the hand-checked organization files in db/seeds/organizations/
  # (researched in #8, #30, #60 and #63, approved by Tosin) and the plant
  # details in db/seeds/facilities.yml through Directory::FactWriter.
  #
  # Every fact is marked verified by human:tosin and gets one evidence row
  # (found_by: human) pointing at the source page and quote from the file.
  # Safe to re-run: FactWriter updates existing facts, never duplicates them.
  # All or nothing: if any fact fails, nothing is written and Error lists why.
  #
  # Not loaded: each file's `notes` (research notes, kept in the YAML), and
  # facilities.yml's other_names (for facility aliases, #65).
  class OrganizationLoader
    class Error < StandardError; end

    VERIFICATION = { status: "verified", by: "human:tosin" }.freeze

    attr_reader :results

    FACILITY_FIELDS = %w[facility_type status city state].freeze

    # facilities: the plant-details file; defaults to facilities.yml next to dir.
    def initialize(dir, facilities: File.join(File.dirname(dir), "facilities.yml"))
      @files = Dir[File.join(dir, "*.yml")].sort
      @facilities_file = facilities
      @results = Hash.new { |h, kind| h[kind] = { created: 0, updated: 0 } }
      @errors = []
    end

    def load!
      docs = @files.to_h { |path| [ File.basename(path, ".yml"), read(path) ] }
      facilities = File.exist?(@facilities_file.to_s) ? Array(read(@facilities_file)["facilities"]) : []

      ActiveRecord::Base.transaction do
        sources = write_sources(docs.values.flat_map { |doc| evidence_items(doc) } +
          facilities.flat_map { |facility| facility.values_at(*FACILITY_FIELDS).select { |f| f.is_a?(Hash) } })
        # Facts can't cite a source that wasn't saved, so stop here.
        raise Error, "Seed failed, nothing was written:\n  #{@errors.join("\n  ")}" if @errors.any?
        shared = shared_domains(docs)

        # Organizations first, so relationships can find the other side.
        docs.each { |slug, doc| write_organization(slug, doc, sources, shared) }
        docs.each { |slug, doc| write_facts(slug, doc, sources) }
        facilities.each { |facility| write_facility_details(facility, sources) }

        raise Error, "Seed failed, nothing was written:\n  #{@errors.join("\n  ")}" if @errors.any?
      end
      self
    end

    private
      # One sources row per URL. Sources belong to the data quality module,
      # so they're created through its entry point, not FactWriter.
      def write_sources(items)
        items.select { |item| item["source_url"] }.group_by { |item| item["source_url"] }.to_h do |url, group|
          published_on = group.filter_map { |item| item["published"] }.min
          result = DataQuality::Sources.find_or_create(url: url, published_on: published_on)
          @errors << "source #{url.inspect}: #{result.errors.join('; ')}" unless result.ok?
          [ url, result.ref&.id ]
        end
      end

      def evidence_items(doc)
        [ *hq_entries(doc), *description_items(doc), *doc["roles"], *doc["technologies"], *doc["relationships"],
          *doc["facilities"] ].compact.select { |item| item["source_url"] }
      end

      # The description's quote, plus any "also" quotes that support the rest
      # of its text (from the same page unless they name their own source_url).
      def description_items(doc)
        description = doc["description"] or return []
        [ description, *Array(description["also"]).map { |extra| { "source_url" => description["source_url"] }.merge(extra) } ]
      end

      def read(path) = YAML.safe_load_file(path, permitted_classes: [ Date ])

      # hq is one entry, or a list when research added to what the seed had
      # (later entries fill in what earlier ones left blank).
      def hq_entries(doc) = Array.wrap(doc["hq"]).compact

      # Websites shared by several organizations (a parent and its
      # subsidiaries, often) can't identify any one of them, so those
      # organizations keep the website but get no matching domain.
      def shared_domains(docs)
        docs.values.map { |doc| Organization.domain_from(doc["website"]) }.compact.tally.select { |_, n| n > 1 }.keys
      end

      def write_organization(slug, doc, sources, shared)
        hq = hq_entries(doc)
        description = doc["description"] || {}
        attributes = {
          name: doc["name"], slug: slug, legal_name: doc["legal_name"], website: doc["website"], aliases: doc["aliases"],
          country_code: doc["country_code"], status: doc["status"], description: description["text"],
          hq_city: hq.filter_map { |entry| entry["city"].presence }.last, hq_state: hq.filter_map { |entry| entry["state"].presence }.last
        }
        attributes[:domain] = nil if shared.include?(Organization.domain_from(doc["website"]))

        write(slug, :organization, attributes, [ *hq, *description_items(doc) ].filter_map { |item| evidence(item, sources) })
      end

      def write_facts(slug, doc, sources)
        organization = Directory::Lookup.organization(slug:) or return

        Array(doc["roles"]).each do |item|
          [ item["key"], item["subtype"] ].compact.each do |role|
            write(slug, :organization_role, { organization_id: organization.id, role: role }, evidence(item, sources))
          end
        end

        Array(doc["technologies"]).each do |item|
          write(slug, :organization_technology, { organization_id: organization.id, technology: item["key"] },
            evidence(item, sources))
        end

        Array(doc["relationships"]).each do |item|
          other = Directory::Lookup.organization(name: item["to"])
          unless other
            @errors << "#{slug}: relationship to unknown organization #{item["to"].inspect}"
            next
          end

          write(slug, :relationship, { from_organization_id: organization.id, to_organization_id: other.id,
            relationship_type: item["type"], description: item["description"] }, evidence(item, sources))
        end

        Array(doc["facilities"]).each do |item|
          facility = write(slug, :facility, facility_attributes(item), evidence(item, sources))
          next unless facility&.ok?

          write(slug, :facility_relationship, { organization_id: organization.id, facility_id: facility.id,
            relationship_type: item["type"], description: item["note"], ownership_pct: item["ownership_pct"] },
            evidence(item, sources))
        end
      end

      # Plant details from facilities.yml: each field has its own source, so
      # each is written with its own evidence. The plant must already be in an
      # organization file. A field with no value (e.g. no city, with a quote
      # naming the nearest town) is kept in the YAML but not written.
      def write_facility_details(entry, sources)
        name = entry["name"]
        facility = Directory::Lookup.facility(name:)
        return @errors << "facilities.yml: #{name.inspect} isn't in any organization file" unless facility

        FACILITY_FIELDS.each do |field|
          detail = entry[field]
          next unless detail.is_a?(Hash) && detail["value"].present?

          write("facilities.yml", :facility, { id: facility.id, field.to_sym => detail["value"] }, evidence(detail, sources))
        end
      end

      # A facility can be mentioned in several entries, each stating only some
      # of its details, so blank details never overwrite ones already set.
      # county isn't loaded (no column); it stays in the YAML.
      def facility_attributes(item)
        item.slice("name", "facility_type", "status", "city", "state")
          .transform_values { |value| value.is_a?(String) ? value.strip : value }
          .compact_blank.symbolize_keys
      end

      # nil when the file gives no source (e.g. an HQ city stated without one).
      def evidence(item, sources)
        return unless item["source_url"]

        { source_id: sources.fetch(item["source_url"]), quote: item["quote"], found_by: "human",
          confidence: item["confidence"] }
      end

      def write(slug, kind, attributes, evidence)
        result = Directory::FactWriter.write(kind, attributes, evidence: Array.wrap(evidence), verification: VERIFICATION)
        if result.ok?
          @results[kind][result.created ? :created : :updated] += 1
        else
          @errors << "#{slug}: #{kind} #{attributes[:name] || attributes[:role] || attributes[:relationship_type]}: " \
            "#{result.errors.join("; ")}"
        end
        result
      end
  end
end
