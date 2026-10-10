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

      OrganizationAlias.where("organization_aliases.normalized_alias LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(key)}%")
        .includes(:organization).select { |a| brand_key(a.alias, plants:) == key }
        .map(&:organization).uniq.first(10).map { |org| OrganizationRef.from(org) }
    end

    # "Constellation Energy Generation, LLC" => "constellation";
    # "NextEra Energy Seabrook, LLC" => "nextera" (Seabrook is a known plant);
    # "Duke Energy Carolinas, LLC" => "duke". nil when too short to trust.
    def brand_key(name, plants: plant_names)
      words = brand_words(name, plants)
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

      # "L.L.C." is one word ("LLC"), as the alias normalizer reads it.
      tokens = name.to_s.gsub("&", " and ").gsub(/\b(?:[[:alpha:]]\.){2,}/) { |initials| initials.delete(".") }
        .scan(/[[:alnum:]]+/)
      base = strip_entities(tokens.map(&:downcase))
      place = place_words_at_end(base, plants) or return

      tokens.first(base.size - place).join(" ")
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
      Facility.where.not(verification_status: "rejected").pluck(:name).flat_map do |name|
        words = distinctive_words(name).reject { |word| word.length < 3 }
        first = words.first.to_s
        [ words.join(" "), words.first(2).join(" "), (first if first.length >= 5 && !PLACE_PREFIXES.include?(first)) ]
      end.compact_blank.to_set
    end

    def distinctive_words(name)
      OrganizationAlias.normalize(name).split.reject { |word| GENERIC_WORDS.include?(word) || word.match?(/\A\d+\z/) }
    end

    private
      # Normalized words of the brand: legal and operating words dropped from
      # the end, then a trailing known plant or region name, then legal words
      # again. Stops at an OWN_BRANDS name.
      def brand_words(name, plants)
        words = strip_entities(OrganizationAlias.normalize(name).split)
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

        3.downto(1).find do |size|
          next if words.size <= size

          tail = words.last(size).join(" ")
          REGION_WORDS.include?(tail) || plants.include?(tail)
        end
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
