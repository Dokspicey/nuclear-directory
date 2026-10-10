# One-off (#64): gives sources without a title one, so pages citing
# several articles from the same site can tell them apart. Each URL is
# fetched once through the Fetcher (honest user agent, robots.txt, a pause
# between requests to one host) and only its title is kept, not the page.
#
# - an HTML page: its <title>
# - fetched but no title (e.g. a PDF): "<site>, <published date>"
# - blocked, disallowed or unreachable: skipped; the title stays empty
#
#   DataQuality::TitleBackfill.run # => { "titled" => 51, "fallback" => 3, "skipped" => 10 }
class DataQuality::TitleBackfill
  # A title sits at the top of a page; there's no need to download more.
  MAX_BYTES = 512.kilobytes

  def self.run(sources: Source.where(title: [ nil, "" ]), fetcher: DataQuality::Fetcher.new, log: ->(_line) { })
    stats = Hash.new(0)

    sources.find_each do |source|
      outcome, detail = title_for(source, fetcher)
      source.update!(title: detail) if %i[titled fallback].include?(outcome)
      stats[outcome.to_s] += 1
      log.call("#{outcome.to_s.ljust(8)} #{source.url}  #{detail}")
    end

    stats
  end

  def self.title_for(source, fetcher)
    return [ :skipped, "not a web URL" ] unless source.url.match?(%r{\Ahttps?://}i)

    response = fetcher.get(source.url, max_bytes: MAX_BYTES)
    return [ :skipped, response.reason ] unless response.kind == :ok

    title = DataQuality::PageTitle.from(response.body, content_type: response.content_type)
    title ? [ :titled, title ] : [ :fallback, fallback(source) ]
  end

  # "energy.gov, March 4, 2024", or just the site when there's no date.
  def self.fallback(source)
    [ source.domain, source.published_on&.strftime("%B %-d, %Y") ].compact.join(", ")
  end
  private_class_method :title_for, :fallback
end
