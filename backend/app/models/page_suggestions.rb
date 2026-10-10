# "Did you mean…" for a page that wasn't found (#110). Most 404s here are a
# mistyped or renamed company or plant address, so the words in the path
# ("/companies/kairos-powr") are matched against published company and plant
# names: each word, or its first four letters when it's long enough for a
# typo near the end. Names matching more words come first, then the kind
# the address was for (/companies/ or /plants/), then the shortest name.
class PageSuggestions
  LIMIT = 3
  # Path words that never name anything.
  NOISE = %w[companies company plants plant sites site www html php index page].freeze

  attr_reader :words

  def initialize(path)
    @kind = { "companies" => :company, "plants" => :plant }[path.to_s.split("/")[1]]
    @words = path.to_s.split("?").first.to_s.downcase.scan(/[a-z0-9]+/)
      .reject { |word| word.length < 3 || NOISE.include?(word) || word.match?(/\A\d+\z/) }.uniq.first(6)
  end

  # What to prefill the search with.
  def query = words.join(" ").presence

  # Up to LIMIT [kind, record] pairs, kind :company or :plant.
  def matches
    return [] if words.empty?

    @matches ||= begin
      # Ranked and capped in SQL, so a broad word never loads whole tables.
      companies = best(Organization.published, "organizations.name").map { |o| [ :company, o ] }
      plants = best(Facility.published.where(parent_id: nil), "facilities.name").map { |f| [ :plant, f ] }
      (companies + plants).sort_by { |kind, record| [ -score(record.name), kind == @kind ? 0 : 1, record.name.length, record.name ] }.first(LIMIT)
    end
  end

  private
    def patterns = words.map { |word| word.length >= 5 ? word.first(4) : word }

    def name_matches(column)
      clause = patterns.map { "#{column} ILIKE ?" }.join(" OR ")
      ActiveRecord::Base.sanitize_sql_array([ clause, *likes ])
    end

    # The LIMIT best matches of one kind: most words matched, then shortest name.
    def best(scope, column)
      score_sql = patterns.map { "(CASE WHEN #{column} ILIKE ? THEN 1 ELSE 0 END)" }.join(" + ")
      order = ActiveRecord::Base.sanitize_sql_array([ "#{score_sql} DESC, LENGTH(#{column}), #{column}", *likes ])
      scope.where(name_matches(column)).order(Arel.sql(order)).limit(LIMIT).to_a
    end

    def likes = patterns.map { |p| "%#{ActiveRecord::Base.sanitize_sql_like(p)}%" }

    def score(name) = patterns.count { |pattern| name.downcase.include?(pattern) }
end
