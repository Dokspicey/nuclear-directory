# Checks each candidate and then publishes it through the directory's
# FactWriter, sends it to human review, or rejects it. Shared by all plug-ins.
#
# 1. Code first: the cited quote must really appear in the source's stored
#    content (plug-in's quote_in_source?). A made-up quote goes to review
#    without asking any model.
# 2. Then the verifier decides. The default is the verifier agent, a second
#    model that re-reads the source (Verifiers::Agent). A verifier either
#    answers in batches (#verdicts) or one candidate at a time (#call).
# Publishing never overwrites a fact a human verified or rejected
# (DirectoryClient#write_fact, FactWriter protect_human_verified).
class DataQuality::Stages::Verify < DataQuality::Stage
  def initialize(verifier: DataQuality::Verifiers::Agent.new, **)
    super(**)
    @verifier = verifier
  end

  private
    def perform(run)
      stats = { "candidates" => 0, "quote_missing" => 0, "published" => 0, "needs_review" => 0, "rejected" => 0,
        "write_errors" => 0 }
      pending = candidates.where(status: %w[new matched]).includes(:source).order(:id).to_a
      stats["candidates"] = pending.size

      checkable, made_up = pending.partition { |candidate| quote_found?(candidate) }

      # Every model call happens here, before anything is written, so a
      # failed call leaves every candidate as it was.
      verdicts = verdicts_for(checkable, run)

      made_up.each do |candidate|
        stats["quote_missing"] += 1
        send_to_review(candidate, "The cited quote isn't in the source as stored, so it can't be checked: " \
          "#{candidate.quote.to_s.truncate(120).inspect}", stats)
      end
      checkable.each do |candidate|
        verdict = verdicts.fetch(candidate.id)

        case verdict.outcome
        when :publish then publish(candidate, verdict, run, stats)
        when :review then send_to_review(candidate, verdict.reason, stats)
        when :reject
          candidate.update!(status: "rejected", notes: verdict.reason)
          stats["rejected"] += 1
          retire_proposal(candidate, run)
        end
      end

      stats
    end

    def verdicts_for(candidates, run)
      return {} if candidates.empty?
      return @verifier.verdicts(candidates, run:, plugin:) if @verifier.respond_to?(:verdicts)

      candidates.to_h { |candidate| [ candidate.id, @verifier.call(candidate) ] }
    end

    # With no stored content there's nothing to check the quote against
    # (e.g. hand-made candidates); the verifier still decides.
    def quote_found?(candidate)
      candidate.source.content_text.blank? || plugin.quote_in_source?(candidate.source, candidate.quote)
    end

    def publish(candidate, verdict, run, stats)
      result = directory.write_fact(candidate, confidence: verdict.confidence, crawl_run: run)

      if result.success?
        candidate.update!(status: "merged", subject_type: result.ref.type, subject_id: result.ref.id, notes: verdict.reason)
        stats["published"] += 1
        # A verified unit completes its site's missing details (see DirectoryClient).
        directory.fill_site_from_unit(result.ref.id, candidate, crawl_run: run) if candidate.kind_facility?
      else
        stats["write_errors"] += 1
        send_to_review(candidate, "Directory rejected the write: #{result.errors.join('; ')}", stats)
      end
    end

    # A rejected candidate whose record match created (a proposal) takes that
    # record with it, unless another live candidate is attached to it too. A
    # rejected candidate attached to an existing record leaves it alone.
    def retire_proposal(candidate, run)
      return unless candidate.proposed_subject? && candidate.subject_id

      others = Candidate.where(subject_type: candidate.subject_type, subject_id: candidate.subject_id)
        .where.not(id: candidate.id).where(status: %w[new matched merged needs_review])
      directory.retire(candidate, crawl_run: run) unless others.exists?
    end

    def send_to_review(candidate, reason, stats)
      candidate.update!(status: "needs_review", notes: reason)
      stats["needs_review"] += 1
    end
end
