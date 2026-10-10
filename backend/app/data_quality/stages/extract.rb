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
      stats = { "sources" => 0, "candidates" => 0, "unchanged" => 0, "empty" => 0 }

      sources.crawl_ok.find_each do |source|
        # Nothing stored, nothing to extract (not the same as a page whose
        # layout changed, which the plug-in reports).
        if source.content_text.blank?
          stats["empty"] += 1
          next
        end

        if source.content_sha256.present? && source.content_sha256 == source.extracted_sha256
          stats["unchanged"] += 1
          next
        end

        # The plug-in may take minutes (model calls with retries), so it runs
        # before the transaction: no locks held meanwhile, and if it fails
        # the source's existing candidates are untouched.
        snapshot = source.content_sha256
        extracted = plugin.extract(source, run).map do |attrs|
          attrs = attrs.slice(:kind, :payload, :quote, :status, :notes)
          attrs[:review_origin] = "extract" if attrs[:status].to_s == "needs_review"
          attrs.merge(crawl_run: run)
        end

        # Results belong to the snapshot they were read from, from a source
        # that's still usable. If a crawl stored new content or flagged the
        # source (blocked, needs_human) meanwhile, or another run already
        # extracted this snapshot, they're discarded rather than written.
        written = Candidate.transaction do
          source.lock!
          next false unless source.crawl_ok?
          next false if source.content_sha256 != snapshot || source.extracted_sha256 == snapshot

          stale(source).delete_all
          extracted.each { |attrs| source.candidates.create!(attrs) }
          source.update!(extracted_sha256: snapshot)
          true
        end

        unless written
          stats["superseded"] = stats.fetch("superseded", 0) + 1
          next
        end
        stats["candidates"] += extracted.size
        stats["sources"] += 1
      end

      stats
    end

    def stale(source)
      source.candidates.status_new.or(source.candidates.status_needs_review.where(review_origin: "extract"))
    end
end
