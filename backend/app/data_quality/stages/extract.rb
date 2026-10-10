# Turns each crawled source into candidate facts via the plug-in.
# A source whose content hasn't changed since its last extraction is
# skipped. Re-extracting replaces a source's unprocessed (new) candidates;
# candidates that already moved on are left alone. A plug-in may send a
# candidate straight to review by returning status: "needs_review" and the
# reason in notes.
class DataQuality::Stages::Extract < DataQuality::Stage
  private
    def perform(run)
      stats = { "sources" => 0, "candidates" => 0, "unchanged" => 0 }

      sources.crawl_ok.find_each do |source|
        if source.content_sha256.present? && source.content_sha256 == source.extracted_sha256
          stats["unchanged"] += 1
          next
        end

        Candidate.transaction do
          source.candidates.status_new.delete_all
          plugin.extract(source, run).each do |attrs|
            source.candidates.create!(attrs.slice(:kind, :payload, :quote, :status, :notes).merge(crawl_run: run))
            stats["candidates"] += 1
          end
          source.update!(extracted_sha256: source.content_sha256)
        end
        stats["sources"] += 1
      end

      stats
    end
end
