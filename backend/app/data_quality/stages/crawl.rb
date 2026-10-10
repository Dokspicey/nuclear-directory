# Fetches the plug-in's sources and stores a snapshot of each (sources
# table). Fetching rules (robots.txt, rate limits) live in the plug-in.
class DataQuality::Stages::Crawl < DataQuality::Stage
  private
    def perform(run)
      plugin.crawl(run)
    end
end
