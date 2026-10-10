# NRC's list of operating power reactor units (#12): the first source.
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

  def initialize(fetcher: DataQuality::Fetcher.new)
    @fetcher = fetcher
  end

  def crawl(_run)
    list = source(LIST_URL, source_kind, title: "NRC list of power reactor units")
    status = source(STATUS_URL, STATUS_SOURCE_KIND, title: "NRC power reactor status, last 365 days")

    stats = { "list" => DataQuality::Snapshot.take(list, fetcher: @fetcher).to_s }
    return stats.merge("stopped" => "list page blocked") if stats["list"] == "blocked"

    stats["status_file"] = DataQuality::Snapshot.take(status, fetcher: @fetcher).to_s
    stats.merge(check(list, status))
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
