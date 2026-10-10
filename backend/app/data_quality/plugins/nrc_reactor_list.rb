# NRC's list of operating power reactor units: the first source.
# Crawl is #12; extract (#13) is described at #extract.
#
# Crawl fetches the HTML list page, then the 365-day power status file, and
# checks that both name the same units. Rules (agreed on #12):
# - at most one fetch a day per URL, with ETag / If-Modified-Since
# - an honest user agent, robots.txt respected, no retries
# - on a block (403), record it with the CDN reference and stop the run
# - if the page's table is missing, or the two files disagree on which
#   units exist, mark the list needs_human so nothing is extracted from it
class DataQuality::Plugins::NrcReactorList < DataQuality::Plugin
  LIST_URL = "https://www.nrc.gov/facilities-safety/operating-reactors/list-power-reactor-units"
  STATUS_URL = "https://www.nrc.gov/documents-reports/document-collections/events-reports-associated-with/" \
    "power-reactor-status-reports/PowerReactorStatusForLast365Days.txt"
  # The status file only cross-checks the list; it has its own kind so the
  # extract stage never reads it.
  STATUS_SOURCE_KIND = "nrc_power_status"
  # Units the status file names differently from the list page, beyond
  # spacing and punctuation (which the comparison ignores, so "LaSalle 1"
  # already matches "La Salle 1"). When a cross-check flags a pair that is
  # really the same unit, add it here.
  STATUS_FILE_NAMES = {
    "Harris 1" => "Shearon Harris 1",
    "River Bend Station 1" => "River Bend 1"
  }.freeze

  def initialize(fetcher: DataQuality::Fetcher.new, extractor: Extractor.new)
    @fetcher = fetcher
    @extractor = extractor
  end

  def crawl(_run)
    list = source(LIST_URL, source_kind, title: "NRC list of power reactor units")
    status = source(STATUS_URL, STATUS_SOURCE_KIND, title: "NRC power reactor status, last 365 days")

    stats = { "list" => DataQuality::Snapshot.take(list, fetcher: @fetcher).to_s }
    return stats.merge("stopped" => "list page blocked") if stats["list"] == "blocked"

    stats["status_file"] = DataQuality::Snapshot.take(status, fetcher: @fetcher).to_s
    stats.merge(check(list, status))
  end

  # Extract (#13): the extractor model reads the table and every answer is
  # checked against the exact parse, matched by NRC docket. The candidates
  # always carry the table's values; the model's job here is to prove
  # itself on a source we can check, before it's trusted on messier ones.
  # - agrees: candidates go on as new
  # - disagrees, or its quote isn't the row as written: candidates go to
  #   review, with both values in the notes
  # - skips a unit: that unit's candidates go to review
  # - invents a unit: dropped and counted
  # - an operator goes to review unless the model agreed on one of its rows
  # The tally is saved on the run as stats["ai_check"].
  # Per unit: the unit (facility), its operator (organization, one per
  # name) and the "operates" link, in the shape match expects (README).
  def extract(source, run)
    table = Page.units(source.content_text).index_by(&:nrc_docket)
    text = Page.lines(source.content_text)
    lines = text.index_by { |line| line[/(?:\A| \| )(\d{8})(?: \| |\z)/, 1] }
    answers = @extractor.call(text, run: run)

    tally = { "table_units" => table.size, "ai_units" => answers.size,
      "agreed" => 0, "disagreed" => 0, "missed" => 0, "made_up" => 0 }
    seen = {}
    units = answers.filter_map do |answer|
      unit = table[answer["nrc_docket"]]
      if unit.nil? || seen[unit.nrc_docket]
        tally["made_up"] += 1
        next
      end

      seen[unit.nrc_docket] = true
      problems = disagreements(answer, unit, lines[unit.nrc_docket])
      tally[problems.empty? ? "agreed" : "disagreed"] += 1
      [ unit, problems.presence && "The extractor model disagreed with the table: #{problems.join('; ')}" ]
    end
    (table.keys - seen.keys).each do |docket|
      tally["missed"] += 1
      units << [ table[docket], "The extractor model skipped this unit; values are from the table" ]
    end

    run.update!(stats: run.stats.merge("ai_check" => tally))
    operator_candidates(units, lines) + units.flat_map { |unit, review| unit_candidates(unit, lines[unit.nrc_docket], review) }
  end

  private
    def source(url, kind, title:)
      Source.find_or_create_by!(url: url) do |source|
        source.source_kind = kind
        source.title = title
      end
    end

    # Sanity-checks the list snapshot; runs every crawl, so a fixed page
    # clears an earlier needs_human.
    def check(list, status)
      return {} unless list.crawl_ok? && list.content_text.present?

      units = Page.units(list.content_text)
      if units.empty?
        needs_human(list, "Couldn't find the reactor table; the page layout may have changed")
        return { "units" => 0 }
      end

      stats = { "units" => units.size }
      if (unusable = status_file_problem(status))
        return stats.merge("cross_check" => "skipped: status file is #{unusable}")
      end

      reported = StatusFile.latest_units(status.content_text)
      return stats.merge("cross_check" => "skipped: no units in status file") if reported.empty?

      missing, extra = differences(units.map(&:name), reported)
      if missing.any? || extra.any?
        needs_human(list, "List page and status file disagree on units. " \
          "Only on the page: #{sample(missing)}. Only in the status file: #{sample(extra)}")
        return stats.merge("cross_check" => "mismatch", "only_on_page" => missing.size, "only_in_status_file" => extra.size)
      end

      stats.merge("cross_check" => "ok")
    end

    # What the model got wrong about one unit, in words; [] when it agrees.
    # The model is told to copy values exactly, so it's checked exactly:
    # "DC Cook 1" for "D.C. Cook 1" is a disagreement, not a match.
    def disagreements(answer, unit, line)
      {
        "name" => [ answer["name"], unit.name ],
        "reactor type" => [ answer["reactor_type"], unit.reactor_type ],
        "state" => [ answer["state"], unit.state ],
        "operator" => [ answer["operator"], unit.owner_operator ]
      }.filter_map { |field, (said, table)| differs(field, said, table) unless said == table }
        .tap { |problems| problems << differs("quote", answer["quote"], line) unless answer["quote"] == line }
    end

    def differs(field, said, table) = "#{field}: model said #{said.inspect}, table says #{table.inspect}"

    # One per operator name. An operator is only as confirmed as its units:
    # it goes on as new if the model agreed on at least one of its rows
    # (operator included), else to review. The quote is an agreed row when
    # there is one.
    def operator_candidates(units, lines)
      units.group_by { |unit, _review| unit.owner_operator }.map do |operator, rows|
        agreed = rows.find { |_unit, review| review.nil? }
        quote_unit = (agreed || rows.first).first
        candidate = { kind: "organization", payload: { "name" => operator }, quote: lines[quote_unit.nrc_docket] }
        next candidate if agreed

        candidate.merge(status: "needs_review",
          notes: "The extractor model didn't confirm any row for this operator: #{rows.map { |_unit, review| review }.uniq.join(' / ')}")
      end
    end

    def unit_candidates(unit, line, review)
      facility = { "name" => unit.name, "nrc_docket" => unit.nrc_docket }
      flags = review ? { status: "needs_review", notes: review } : {}

      # "state" is NRC's, which is the state of the city Location measures
      # from; near a border that's not the plant's (Salem NJ shows as DE).
      # It's evidence; EIA's plant state is to win for that field (planned in
      # the EIA plug-in, #72).
      [
        { kind: "facility", quote: line, payload: facility.merge(
          "facility_type" => "power_reactor", "status" => "operating", "reactor_type" => unit.reactor_type,
          "state" => unit.state, "country_code" => "US") },
        { kind: "facility_relationship", quote: line, payload: {
          "organization" => { "name" => unit.owner_operator }, "facility" => facility, "relationship_type" => "operates" } }
      ].map { |candidate| candidate.merge(flags) }
    end

    # Why the status file can't be used for the cross-check, or nil if it can.
    # A blocked or never-fetched file reports its crawl_status. A file that
    # fetched fine before but failed today (server error, timeout) keeps
    # crawl_status ok with a status_reason; its content is stale, so don't
    # compare against it.
    def status_file_problem(status)
      return status.crawl_status unless status.crawl_ok?
      return "unavailable (#{status.status_reason})" if status.status_reason.present?
      "empty" if status.content_text.blank?
    end

    def differences(page_names, status_names)
      page = page_names.index_by { |name| normalize(name) }
      status = status_names.index_by { |name| normalize(STATUS_FILE_NAMES.fetch(name, name)) }
      [ page.except(*status.keys).values, status.except(*page.keys).values ]
    end

    # "D.C. Cook 1" => "dccook1", "La Salle 1" => "lasalle1"
    def normalize(name) = name.downcase.gsub(/[^a-z0-9]/, "")

    def sample(names) = names.empty? ? "none" : names.first(5).join(", ") + (names.size > 5 ? " and #{names.size - 5} more" : "")

    def needs_human(source, reason)
      source.update!(crawl_status: "needs_human", status_reason: reason)
    end
end
