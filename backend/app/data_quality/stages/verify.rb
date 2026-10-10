# Asks the verifier about each candidate, then publishes it through the
# directory's FactWriter, sends it to human review, or rejects it.
# Shared by all plug-ins.
class DataQuality::Stages::Verify < DataQuality::Stage
  def initialize(verifier: DataQuality::Verifiers::ReviewEverything.new, **)
    super(**)
    @verifier = verifier
  end

  private
    def perform(run)
      stats = { "candidates" => 0, "published" => 0, "needs_review" => 0, "rejected" => 0, "write_errors" => 0 }

      candidates.where(status: %w[new matched]).find_each do |candidate|
        stats["candidates"] += 1
        verdict = @verifier.call(candidate)

        case verdict.outcome
        when :publish then publish(candidate, verdict, run, stats)
        when :review then send_to_review(candidate, verdict.reason, stats)
        when :reject
          candidate.update!(status: "rejected", notes: verdict.reason)
          stats["rejected"] += 1
        end
      end

      stats
    end

    def publish(candidate, verdict, run, stats)
      result = directory.write_fact(candidate, confidence: verdict.confidence, crawl_run: run)

      if result.success?
        candidate.update!(status: "merged", subject_type: result.ref.type, subject_id: result.ref.id)
        stats["published"] += 1
      else
        stats["write_errors"] += 1
        send_to_review(candidate, "Directory rejected the write: #{result.errors.join('; ')}", stats)
      end
    end

    def send_to_review(candidate, reason, stats)
      candidate.update!(status: "needs_review", notes: reason)
      stats["needs_review"] += 1
    end
end
