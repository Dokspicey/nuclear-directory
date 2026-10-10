# Turns each crawled source into candidate facts via the plug-in.
# A source whose content hasn't changed since its last extraction is
# skipped. A plug-in may send a candidate straight to review by returning
# status: "needs_review" and the reason in notes; it's marked
# review_origin: "extract".
#
# Re-extracting a changed source replaces what came from its old
# snapshot and wasn't acted on yet: candidates still new, and ones extract
# itself sent to review. Candidates that moved on (matched, merged,
# rejected, or sent to review by a later stage) are left alone.
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
          stale(source).delete_all
          plugin.extract(source, run).each do |attrs|
            attrs = attrs.slice(:kind, :payload, :quote, :status, :notes)
            attrs[:review_origin] = "extract" if attrs[:status].to_s == "needs_review"
            source.candidates.create!(attrs.merge(crawl_run: run))
            stats["candidates"] += 1
          end
          source.update!(extracted_sha256: source.content_sha256)
        end
        stats["sources"] += 1
      end

      stats
    end

    def stale(source)
      source.candidates.status_new.or(source.candidates.status_needs_review.where(review_origin: "extract"))
    end
end
