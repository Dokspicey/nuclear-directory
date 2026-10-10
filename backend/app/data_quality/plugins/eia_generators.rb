# EIA's monthly generator inventory (Form EIA-860M, #61): capacity and
# coordinates for nuclear units. An enrichment source: it never creates or
# renames facilities (NRC is the source of truth for which units exist, their
# names, dockets and operators). It only adds capacity_mw, state, latitude
# and longitude to NRC units that already exist.
#
# Crawl reads EIA's 860M page to find the newest monthly file, fetches it,
# and stores just its nuclear rows as CSV (one source per monthly file, so
# evidence points at the exact file). Extract turns each row into a facility
# candidate whose payload carries "identify" (how to find the unit) and the
# values to set. The match stage finds the unit by state, name and unit
# number; see app/data_quality/README.md.
class DataQuality::Plugins::EiaGenerators < DataQuality::Plugin
  INDEX_URL = "https://www.eia.gov/electricity/data/eia860m/"
  # The 860M page is snapshotted as its own source (never extracted), so it
  # follows the once-a-day fetch rule like any other source.
  INDEX_SOURCE_KIND = "eia_860m_index"
  FILE_LINK = %r{(?:\A|/)xls/([a-z]+)_generator(\d{4})\.xlsx\z}i

  def initialize(fetcher: DataQuality::Fetcher.new)
    @fetcher = fetcher
  end

  def crawl(_run)
    index = Source.find_or_create_by!(url: INDEX_URL) do |new_source|
      new_source.source_kind = INDEX_SOURCE_KIND
      new_source.title = "EIA-860M monthly generator inventory page"
    end
    DataQuality::Snapshot.take(index, fetcher: @fetcher, same_origin: true)
    unless index.crawl_ok? && index.content_text.present?
      raise "EIA 860M page: #{index.status_reason || index.crawl_status}"
    end

    url = latest_file_url(index.content_text) or raise "EIA 860M page: no monthly generator file link found; the page may have changed"
    source = Source.find_or_create_by!(url: url) do |new_source|
      new_source.source_kind = source_kind
      new_source.title = "EIA-860M generator inventory, #{url[FILE_LINK, 1].capitalize} #{url[FILE_LINK, 2]}"
    end

    result = DataQuality::Snapshot.take(source, fetcher: @fetcher, binary: true, same_origin: true) do |bytes|
      Workbook.to_csv(Workbook.nuclear_generators(bytes))
    end
    { "file" => url, "snapshot" => result.to_s, "generators" => [ CSV.parse(source.reload.content_text.to_s).size - 1, 0 ].max,
      "superseded" => (supersede_older_files(source) if source.crawl_ok?) }.compact
  rescue Workbook::Unreadable => error
    source.update!(crawl_status: "needs_human", status_reason: "Couldn't read the EIA workbook: #{error.message}")
    { "file" => url, "snapshot" => "needs_human" }
  end

  def extract(source, _run)
    CSV.parse(source.content_text.to_s, headers: true).filter_map do |row|
      next if row["state"].blank? || row["plant_name"].blank?

      {
        kind: "facility",
        payload: {
          "identify" => row.to_h.slice("plant_name", "state", "generator_id", "eia_plant_id")
            .transform_keys("plant_name" => "name", "generator_id" => "unit"),
          "capacity_mw" => number(row["net_summer_capacity_mw"], 1),
          # EIA's plant state is the unit's state (Tosin, 2026-10-10): NRC's list
          # only names a nearby city, which is in another state for border plants.
          "state" => row["state"],
          "latitude" => number(row["latitude"], 6),
          "longitude" => number(row["longitude"], 6)
        }.compact,
        quote: row.to_csv.chomp
      }
    end
  end

  private
    # Once a newer monthly file is read, candidates from older files that
    # haven't been published yet are withdrawn: an older month approved after
    # a newer one would overwrite current capacity and coordinates.
    def supersede_older_files(source)
      older = Source.where(source_kind:).where.not(id: source.id).select(:id)
      Candidate.where(source_id: older, status: %w[new matched needs_review])
        .update_all(status: "rejected", notes: "Superseded by the newer #{source.title}", updated_at: Time.current)
    end

    # The newest "<month>_generator<year>.xlsx" linked from the page, as an
    # https URL on EIA's own site under the 860M pages. A link anywhere else
    # is ignored, so the page can never point the crawler at another host.
    def latest_file_url(html)
      links = Nokogiri::HTML(html).css("a[href]").filter_map { |a| eia_file_url(a["href"].strip) }
      newest = links.max_by do |url|
        month, year = url.path.match(FILE_LINK).captures
        [ year.to_i, Date::MONTHNAMES.index(month.capitalize).to_i ]
      end
      newest&.to_s
    end

    def eia_file_url(href)
      url = URI.join(INDEX_URL, href)
      index = URI.parse(INDEX_URL)
      url if url.scheme == "https" && url.host == index.host && url.port == index.port &&
        url.path.start_with?(index.path) && url.path.match?(FILE_LINK)
    rescue URI::Error
      nil
    end

    # Strict: the workbook reader already refused anything that isn't a number.
    def number(value, digits) = value.present? ? BigDecimal(value).round(digits).to_s : nil
end
