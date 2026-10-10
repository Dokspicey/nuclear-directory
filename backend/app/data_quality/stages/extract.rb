# Turns each crawled source into candidate facts via the plug-in.
# Rerunning replaces a source's unprocessed (new) candidates; candidates
# that already moved on are left alone.
class DataQuality::Stages::Extract < DataQuality::Stage
  private
    def perform(run)
      stats = { "sources" => 0, "candidates" => 0 }

      sources.crawl_ok.find_each do |source|
        Candidate.transaction do
          source.candidates.status_new.delete_all
          plugin.extract(source, run).each do |attrs|
            source.candidates.create!(attrs.slice(:kind, :payload, :quote).merge(crawl_run: run))
            stats["candidates"] += 1
          end
        end
        stats["sources"] += 1
      end

      stats
    end
end
