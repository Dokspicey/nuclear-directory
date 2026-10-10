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
    # How a link reads to a person (VOICE.md's fixed verbs and words).
    LINK_VERBS = {
      "supplies" => "supplies", "invests_in" => "invests in", "funds" => "funds",
      "offtake_with" => "has an offtake agreement with", "subsidiary_of" => "is a subsidiary of",
      "owns" => "owns", "operates" => "operates", "vendor_for" => "is vendor for", "offtakes_from" => "offtakes from"
    }.freeze
    ROLE_WORDS = { "reactor_vendor" => "reactor developer", "reactor_services" => "repair and services company",
      "data_center_offtaker" => "power buyer" }.freeze
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

    def distinctive_words(name)
      OrganizationAlias.normalize(name).split.reject { |word| GENERIC_WORDS.include?(word) || word.match?(/\A\d+\z/) }
    end

    private
      # A record's name; a link is "the fact “TerraPower owns Plant Vogtle”",
      # in the words visitors use (VOICE.md), so it reads as a review note.
      def fact_label(record)
        statement =
          case record
          when Organization, Facility then return record.name
          when OrganizationRole then "#{record.organization.name} is a #{ROLE_WORDS.fetch(record.role.key, record.role.name.downcase)}"
          when OrganizationTechnology then "#{record.organization.name} works on #{record.technology.name.downcase}"
          when Relationship then "#{record.from_organization.name} #{LINK_VERBS.fetch(record.relationship_type)} #{record.to_organization.name}"
          when FacilityRelationship then "#{record.organization.name} #{LINK_VERBS.fetch(record.relationship_type)} #{record.facility.name}"
          end
        "the fact “#{statement}”"
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
