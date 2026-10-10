# Read side of the directory boundary. Finds organizations and facilities
# and returns plain value objects (OrganizationRef, FacilityRef), so code
# outside the directory never holds an ActiveRecord model. Facts of every
# verification status are returned; check verification_status if it matters.
#
#   Directory::Lookup.organization(name: "TerraPower, Inc.")  # => OrganizationRef or nil
#   Directory::Lookup.facility(nrc_docket: "05000424")        # => FacilityRef or nil
module Directory
  module Lookup
    extend self

    # Pass exactly one of id, slug, name or domain.
    # name matches the organization's name or any alias, compared after
    # OrganizationAlias.normalize, so "TerraPower, LLC" finds "TerraPower".
    # domain accepts a bare domain or a URL.
    def organization(id: nil, slug: nil, name: nil, domain: nil)
      scope =
        case one_of!(id:, slug:, name:, domain:)
        in [ :id, value ] then Organization.where(id: value)
        in [ :slug, value ] then Organization.where(slug: value)
        in [ :name, value ]
          normalized = OrganizationAlias.normalize(value).presence or return
          Organization.joins(:aliases).where(organization_aliases: { normalized_alias: normalized })
        in [ :domain, value ]
          # A malformed URL has no domain; it must match nothing, not every record without one.
          domain = Organization.domain_from(value) or return
          Organization.where(domain: domain)
        end

      record = scope.first
      OrganizationRef.from(record) if record
    end

    # Every change of a fact's verification, newest first, as plain values:
    # who, when, from -> to, why. type is the fact's class name ("Organization").
    def verification_history(type:, id:)
      raise ArgumentError, "not a fact type: #{type.inspect}" unless FACT_TYPES.include?(type.to_s)

      VerificationEvent.where(subject_type: type.to_s, subject_id: id).order(created_at: :desc, id: :desc)
        .map { |event| VerificationEventRef.from(event) }
    end

    FACT_TYPES = %w[Organization OrganizationRole OrganizationTechnology Facility Relationship FacilityRelationship].freeze
    # FactWriter kinds, one per fact type.
    FACT_KINDS = FACT_TYPES.map(&:underscore).freeze

    # Facts of one kind waiting for a human's decision (verification_status
    # pending; never rejected or unpublished), oldest first, as
    # Directory::PendingFactRefs. Page with after_id: the last id seen.
    #
    #   Directory::Lookup.pending_facts(kind: "facility_relationship", limit: 50)
    def pending_facts(kind:, after_id: nil, limit: 50)
      kind = kind.to_s
      raise ArgumentError, "not a fact kind: #{kind.inspect}" unless FACT_KINDS.include?(kind)

      model = kind.camelize.constantize
      scope = model.pending.order(:id).limit(limit).includes(*PENDING_INCLUDES.fetch(kind), :evidence)
      scope = scope.where("#{model.table_name}.id > ?", after_id) if after_id
      latest = latest_events(model.name, scope.map(&:id))

      scope.map do |record|
        PendingFactRef.new(type: model.name, id: record.id, kind:, attributes: pending_attributes(kind, record),
          evidence: record.evidence.sort_by(&:id).map { |item| EvidenceRef.from(item) },
          created_at: record.created_at, last_event: latest[record.id])
      end
    end

    PENDING_INCLUDES = {
      "organization" => [ :aliases ], "facility" => [ :parent, :technology ], "organization_role" => [ :organization, :role ],
      "organization_technology" => [ :organization, :technology ],
      "relationship" => [ :from_organization, :to_organization ], "facility_relationship" => [ :organization, :facility ]
    }.freeze
    private_constant :PENDING_INCLUDES

    # Whether a fact is public now, by its model's .published scope (a unit
    # under a closed site isn't, #104), so callers don't re-derive the rule.
    def published?(type:, id:)
      raise ArgumentError, "not a fact type: #{type.inspect}" unless FACT_TYPES.include?(type.to_s)

      type.to_s.constantize.published.exists?(id:)
    end

    # Whether a fact has any evidence (a source).
    def sourced?(type:, id:)
      raise ArgumentError, "not a fact type: #{type.inspect}" unless FACT_TYPES.include?(type.to_s)

      Evidence.exists?(subject_type: type.to_s, subject_id: id)
    end

    # Any fact's stored values, as FactWriter names them (string keys; link
    # ends as ids, plus the linked records' names), or nil. Lets a caller
    # compare a link's values, which fact_state doesn't carry.
    #
    #   Directory::Lookup.fact_attributes(type: "FacilityRelationship", id: 7)
    #   # => { "ownership_pct" => 45.7, "description" => "...", ... }
    def fact_attributes(type:, id:)
      raise ArgumentError, "not a fact type: #{type.inspect}" unless FACT_TYPES.include?(type.to_s)

      record = type.to_s.constantize.find_by(id:) or return
      pending_attributes(type.to_s.underscore, record).stringify_keys
    end

    # How a link reads to a person (VOICE.md's fixed verbs and words).
    LINK_VERBS = {
      "supplies" => "supplies", "invests_in" => "invests in", "funds" => "funds",
      "offtake_with" => "has an offtake agreement with", "subsidiary_of" => "is a subsidiary of",
      "owns" => "owns", "operates" => "operates", "vendor_for" => "is a vendor for", "offtakes_from" => "offtakes from"
    }.freeze
    # What a company with each role is, in a sentence ("TerraPower is a reactor
    # developer"), in visitors' words. A role not listed reads "has the role …".
    ROLE_WORDS = {
      "fuel" => "a fuel supplier", "mining" => "a uranium miner", "conversion" => "a uranium converter",
      "enrichment" => "a uranium enricher", "fabrication" => "a fuel fabricator",
      "reactor_vendor" => "a reactor developer", "reactor_services" => "a repair and services company",
      "utility" => "a utility", "operator" => "an operator", "data_center_offtaker" => "a power buyer",
      "coolant" => "a coolant supplier", "molten_salt" => "a molten salt coolant supplier",
      "water" => "a light water coolant supplier", "helium" => "a helium coolant supplier",
      "sodium" => "a sodium coolant supplier", "lead" => "a lead coolant supplier",
      "heavy_water" => "a heavy water supplier", "regulatory_consultant" => "a regulatory consultant",
      "venture_capital" => "a venture capital investor", "government_agency" => "a government agency",
      "national_lab" => "a national lab"
    }.freeze
    private_constant :LINK_VERBS, :ROLE_WORDS

    # Any fact's current decision (Directory::FactStateRef), or nil.
    def fact_state(type:, id:)
      raise ArgumentError, "not a fact type: #{type.inspect}" unless FACT_TYPES.include?(type.to_s)

      record = type.to_s.constantize.find_by(id:) or return
      FactStateRef.new(type: type.to_s, id: record.id, name: fact_label(record),
        verification_status: record.verification_status, verified_by: record.verified_by, verified_at: record.verified_at)
    end

    # Pass exactly one of id, slug, name or nrc_docket.
    # name is matched case-insensitively; names aren't unique, so the oldest
    # match wins.
    def facility(id: nil, slug: nil, name: nil, nrc_docket: nil)
      scope =
        case one_of!(id:, slug:, name:, nrc_docket:)
        in [ :id, value ] then Facility.where(id: value)
        in [ :slug, value ] then Facility.where(slug: value)
        in [ :name, value ] then Facility.where("lower(name) = ?", value.to_s.strip.downcase)
        in [ :nrc_docket, value ]
          # A blank docket must match nothing, not every facility without one.
          docket = value.to_s.strip.presence or return
          Facility.where(nrc_docket: docket)
        end

      record = scope.order(:id).first
      FacilityRef.from(record) if record
    end

    # Words too common in this industry to tell two names apart.
    GENERIC_WORDS = %w[
      the of and a an
      nuclear energy power electric electricity generating generation generator station plant plants
      unit units site center centre facility facilities reactor reactors clean
      company co corp corporation inc incorporated llc lp llp ltd limited plc group holdings
      services service operating operations operator operators
      u s us united states american national
    ].to_set.freeze

    # Records whose names share a distinctive word with name, for spotting
    # likely duplicates that an exact lookup misses ("Vogtle 3" vs
    # "Plant Vogtle Units 3 & 4", "LaSalle 1" vs "La Salle"). Unit numbers and
    # generic words like "nuclear" or "station" don't count. Returns up to 10
    # refs; empty when name has no distinctive words.
    def similar_organizations(name)
      words = distinctive_words(name)
      return [] if words.empty?

      aliases = OrganizationAlias.where(similar_text_sql("organization_aliases.normalized_alias", words.size),
        *like_patterns(words)).includes(:organization)
      aliases.select { |a| similar_words?(words, distinctive_words(a.alias)) }
        .map(&:organization).uniq.first(10).map { |org| OrganizationRef.from(org) }
    end

    def similar_facilities(name)
      words = distinctive_words(name)
      return [] if words.empty?

      Facility.where(similar_text_sql("lower(facilities.name)", words.size), *like_patterns(words)).order(:id)
        .select { |facility| similar_words?(words, distinctive_words(facility.name)) }
        .first(10).map { |facility| FacilityRef.from(facility) }
    end

    # Words that name a legal entity or operating arm of a brand rather than
    # the brand itself, when they end a name: "Constellation Energy
    # Generation, LLC" and "Constellation Energy Corporation" are one brand.
    # Decision (Tosin, 2026-10-10): one company per brand.
    ENTITY_WORDS = %w[
      generation operating operations operator nuclear energy power usa us america americas
      holdings holding group international global services company co corp corporation inc incorporated
      llc lp llp ltd limited plc
    ].to_set.freeze
    # Shorter brand keys ("x" from "X-energy") match too much to trust.
    MIN_BRAND_KEY_LENGTH = 4
    # Brands that are their own company even though they look like an arm of
    # another (Tosin, 2026-10-10: Southern Nuclear stays separate from Southern
    # Company). Reducing a name stops here.
    OWN_BRANDS = [ "southern nuclear" ].to_set.freeze
    # Regions a utility brand names its operating companies after
    # ("Duke Energy Carolinas, LLC" is Duke Energy), plus legacy brands that
    # live on as an operating company's name: "progress" (Progress Energy,
    # now "Duke Energy Progress, LLC", is Duke Energy; Tosin, 2026-10-10).
    REGION_WORDS = %w[carolinas carolina florida midwest indiana ohio kentucky texas virginia progress].to_set.freeze

    # Organizations whose name or an alias is the same brand as name: equal
    # once trailing entity words, and a trailing plant or region name, are
    # dropped. More than one result means the brand is ambiguous (e.g. "Urenco"
    # and "Urenco USA" are both records).
    def same_brand_organizations(name, plants: plant_names)
      key = brand_key(name, plants:) or return []

      # A leading "the" isn't part of a brand, so "The Acme Company" is found too.
      prefix = ActiveRecord::Base.sanitize_sql_like(key)
      OrganizationAlias.where("organization_aliases.normalized_alias LIKE ? OR organization_aliases.normalized_alias LIKE ?",
        "#{prefix}%", "the #{prefix}%")
        .includes(:organization).select { |a| brand_key(a.alias, plants:) == key }
        .map(&:organization).uniq.first(10).map { |org| OrganizationRef.from(org) }
    end

    # "Constellation Energy Generation, LLC" => "constellation";
    # "NextEra Energy Seabrook, LLC" => "nextera" (Seabrook is a known plant);
    # "Duke Energy Carolinas, LLC" => "duke". nil when too short to trust.
    def brand_key(name, plants: plant_names)
      words = brand_words(name, plants)
      # Nothing but legal or operating words ("Nuclear Energy LLC") is no brand.
      return if words.all? { |word| ENTITY_WORDS.include?(word) }

      key = words.join(" ")
      key if key.delete(" ").length >= MIN_BRAND_KEY_LENGTH
    end

    # The brand part of a name as written, for naming a new company after its
    # brand: "NextEra Energy Point Beach, LLC" => "NextEra Energy". nil when
    # only legal or operating words were dropped, since the full name is
    # then the company's own.
    def brand_name(name, plants: plant_names)
      # Only for a brand key we'd trust ("X-Energy Seabrook" reduces to "x": no).
      return unless brand_key(name, plants:)

      # Words are found in the name as written, so the brand keeps its own
      # spelling ("Sargent & Lundy", "Babcock-Wilcox"); "&" counts as "and"
      # only for finding the plant or region at the end.
      text = join_initials(name).sub(/\A\s*the\s+(?=\S+\s)/i, "")
      words = text.to_enum(:scan, /[[:alnum:]]+|&/).map { [ Regexp.last_match[0], Regexp.last_match.end(0) ] }
      base = strip_entities(words.map { |word, _| word == "&" ? "and" : word.downcase })
      place = place_words_at_end(base, plants) or return

      text[0, words[base.size - place - 1].last].strip
    end

    # Words that start many place names ("North Anna", "Point Beach"); on its
    # own, one of these isn't a plant's name, so "Acme North" keeps "North".
    PLACE_PREFIXES = %w[north south east west new upper lower lake river point fort mount port saint grand great
      little big old].to_set.freeze

    # Distinctive names of known plants ("seabrook", "point beach",
    # "palisades"), from the facility records, leaving out rejected ones: the
    # full distinctive name, its first two words, and its first word alone
    # when that is a name in itself (five letters or more, not a place word).
    # One query; read it once and pass it as plants: when checking many names.
    def plant_names
      # Plants are often named after their owner ("Urenco USA enrichment
      # facility", "Kairos Power Salt Production Facility"), so a short form
      # that starts a company's name isn't a plant name on its own.
      owners = OrganizationAlias.pluck(:normalized_alias).flat_map do |name|
        words = without_article(name.split)
        [ words.first, words.first(2).join(" ") ]
      end.to_set
      Facility.where.not(verification_status: "rejected").pluck(:name).flat_map do |name|
        words = distinctive_words(name).reject { |word| word.length < 3 }
        first = words.first.to_s
        short = [ words.first(2).join(" "), (first if first.length >= 5 && !PLACE_PREFIXES.include?(first)) ]
        [ words.join(" "), *short.compact.reject { |form| owners.include?(form) } ]
      end.compact_blank.to_set
    end

    # NRC units (facilities with a docket) whose names best fit name, for
    # sources that name plants their own way ("Joseph M Farley" for NRC's
    # "Farley 1", "PSEG Hope Creek Generating Station" for "Hope Creek 1").
    # The units sharing the most distinctive words win, so "Wolf Creek" picks
    # Wolf Creek 1 over Hope Creek 1. Words under three letters don't count,
    # but two words run together do ("la salle" / "lasalle"). state breaks a
    # tie: among equally good fits, units in that state (or with no state
    # yet) are preferred, since NRC units no longer carry a state (EIA's is
    # used; Tosin, 2026-10-10).
    def facility_units(name:, state: nil)
      words = comparable_words(distinctive_words(name))
      return [] if words.empty?

      scored = Facility.where.not(nrc_docket: nil).order(:name).filter_map do |unit|
        shared = (comparable_words(distinctive_words(unit.name)) & words).size
        [ unit, shared ] if shared.positive?
      end
      best = scored.map(&:last).max or return []
      units = scored.select { |_, shared| shared == best }.map(&:first)
      if state.present?
        in_state = units.select { |unit| unit.state.blank? || unit.state.casecmp?(state) }
        units = in_state if in_state.any?
      end
      units.first(20).map { |unit| FacilityRef.from(unit) }
    end

    def distinctive_words(name)
      OrganizationAlias.normalize(name).split.reject { |word| GENERIC_WORDS.include?(word) || word.match?(/\A\d+\z/) }
    end

    private
      # The fact's FactWriter attributes as stored (role and technology as
      # their keys), plus the names of the records it links.
      def pending_attributes(kind, record)
        names = FactWriter::KINDS.fetch(kind.to_sym)[:attributes] - %i[aliases role technology]
        values = names.to_h { |name| [ name, record.public_send(name) ] }
        values[:role] = record.role.key if kind == "organization_role"
        values[:aliases] = record.aliases.map(&:alias).sort if kind == "organization"
        values[:technology] = record.technology&.key if record.respond_to?(:technology)
        values[:organization_name] = record.organization.name if record.respond_to?(:organization)
        values[:facility_name] = record.facility.name if kind == "facility_relationship"
        if kind == "relationship"
          values[:from_organization_name] = record.from_organization.name
          values[:to_organization_name] = record.to_organization.name
        end
        values[:parent_name] = record.parent&.name if kind == "facility"
        values
      end

      def latest_events(type, ids)
        VerificationEvent.where(subject_type: type, subject_id: ids).order(:created_at, :id)
          .index_by(&:subject_id).transform_values { |event| VerificationEventRef.from(event) }
      end

      # Dotted initials as one word ("L.L.C." => "LLC", "L.P." => "LP"), so legal
      # suffixes are recognized however they're punctuated.
      def without_article(words) = words.first == "the" && words.size > 1 ? words.drop(1) : words

      def join_initials(name) = name.to_s.gsub(/\b(?:[[:alpha:]]\.){2,}/) { |initials| initials.delete(".") }

      # Normalized words of the brand: legal and operating words dropped from
      # the end, then a trailing known plant or region name, then legal words
      # again. Stops at an OWN_BRANDS name.
      def brand_words(name, plants)
        # A leading "the" isn't part of a brand ("The Southern Company" is Southern).
        words = without_article(OrganizationAlias.normalize(join_initials(name)).split)
        words = strip_entities(words)
        place = place_words_at_end(words, plants)
        words = strip_entities(words.first(words.size - place)) if place
        words
      end

      def strip_entities(words)
        words = words.dup
        words.pop while words.size > 1 && !OWN_BRANDS.include?(words.join(" ")) && ENTITY_WORDS.include?(words.last)
        words
      end

      # How many words at the end name a known plant or a region, leaving at
      # least one brand word; nil when none do.
      def place_words_at_end(words, plants)
        return if OWN_BRANDS.include?(words.join(" "))

        # Longest first, and always leaving at least one word of the brand.
        (words.size - 1).downto(1).find do |size|
          tail = words.last(size).join(" ")
          REGION_WORDS.include?(tail) || plants.include?(tail)
        end
      end

      # A record's name; a link is "the fact “TerraPower owns Plant Vogtle”",
      # in the words visitors use (VOICE.md), so it reads as a review note.
      def fact_label(record)
        statement =
          case record
          when Organization, Facility then return record.name
          when OrganizationRole
            phrase = ROLE_WORDS[record.role.key]
            phrase ? "#{record.organization.name} is #{phrase}" : "#{record.organization.name} has the role #{record.role.name}"
          when OrganizationTechnology then "#{record.organization.name} works on #{in_sentence(record.technology.name)}"
          when Relationship then "#{record.from_organization.name} #{LINK_VERBS.fetch(record.relationship_type)} #{record.to_organization.name}"
          when FacilityRelationship then "#{record.organization.name} #{LINK_VERBS.fetch(record.relationship_type)} #{record.facility.name}"
          end
        "the fact “#{statement}”"
      end

      # A display name inside a sentence: lowercased, except acronyms ("SMR",
      # "HALEU") and words with capitals inside ("TRISO-X").
      def in_sentence(name)
        name.split.map { |word| word.match?(/\A[[:upper:]][[:lower:]]+\z/) ? word.downcase : word }.join(" ")
      end

      # The same leading distinctive word, which is usually the plant's or
      # company's own name ("Vogtle", "Susquehanna", "Southern"). Later words
      # tend to be places ("Hope Creek" vs "Lost Creek") and don't count. The
      # first two words run together count too ("la salle" and "lasalle").
      # Words under three letters only count as part of that pair, so
      # "La Crosse" isn't like "La Salle".
      def similar_words?(words, other)
        (leading(words) & leading(other)).any?
      end

      def comparable_words(words)
        (words.select { |word| word.length >= 3 } + words.each_cons(2).map(&:join)).uniq
      end

      def leading(words)
        [ (words.first if words.first.to_s.length >= 3), words.first(2).join ].compact.uniq
      end

      # Narrows the search in SQL; similar_words? makes the final call.
      def similar_text_sql(column, word_count)
        squashed = "regexp_replace(#{column}, '[^a-z0-9]', '', 'g')"
        ([ "#{column} LIKE ?" ] * word_count + [ "#{squashed} LIKE ?" ]).join(" OR ")
      end

      def like_patterns(words)
        [ *words, words.join ].map { |word| "%#{ActiveRecord::Base.sanitize_sql_like(word)}%" }
      end

      def one_of!(**options)
        given = options.compact
        raise ArgumentError, "pass exactly one of #{options.keys.join(", ")}" unless given.size == 1

        given.first
      end
  end
end
