# Checks each candidate and RECOMMENDS: it never publishes. A human approves
# in the admin (DataQuality::Review.approve). Shared by all plug-ins.
#
# For each new or matched candidate, in order:
# 1. Its record was rejected or unpublished by a human after match attached
#    it: review, naming that decision.
# 2. It disagrees with a value a human verified on its record: review,
#    showing both values ("human-verified state is NJ; this source says DE").
# 3. Its quote isn't in the source's stored content (plug-in's
#    quote_in_source?): review, without asking any model.
# 4. The verifier decides. The default is the verifier agent, a second model
#    that re-reads the source (Verifiers::Agent). A verifier answers in batches
#    (#verdicts) or one candidate at a time (#call).
#    - publish → ai_recommendation "recommend_publish"; the candidate stays
#      new/matched and nothing is written to the directory
#    - review → needs_review, with the reason
#    - reject → rejected (only test verifiers reject; the agent never does)
# The recommendation (ai_*, verify_run) is stored on the candidate, so the
# admin can list it by run and by reason. A candidate already recommended
# isn't sent to the model again; later runs only repeat the code checks
# (1-3), in case a human decided on its record meanwhile.
class DataQuality::Stages::Verify < DataQuality::Stage
  def initialize(verifier: DataQuality::Verifiers::Agent.new, **)
    super(**)
    @verifier = verifier
  end

  private
    def perform(run)
      stats = { "candidates" => 0, "recommended" => 0, "needs_review" => 0, "rejected" => 0,
        "quote_missing" => 0, "human_decision" => 0, "conflicts" => 0, "already_recommended" => 0, "decided_meanwhile" => 0 }
      pending = candidates.where(status: %w[new matched]).includes(:source).order(:id).to_a
      stats["candidates"] = pending.size

      # Code checks first; only what passes goes to the model.
      held = pending.to_h { |candidate| [ candidate.id, hold_reason(candidate) ] }.compact
      checkable = pending.reject { |candidate| held.key?(candidate.id) || recommended?(candidate) }

      # Every model call happens here, before anything is written, so a
      # failed call leaves every candidate as it was.
      verdicts = verdicts_for(checkable, run)

      pending.each do |candidate|
        # A human may approve or reject in the admin while the model is
        # asked; lock and re-check so their decision is never overwritten.
        candidate.with_lock do
          next stats["decided_meanwhile"] += 1 unless candidate.status_new? || candidate.status_matched?

          apply(candidate, held[candidate.id], verdicts[candidate.id], run, stats)
        end
      end

      stats
    end

    def apply(candidate, hold, verdict, run, stats)
      if hold
        stat, reason = hold
        stats[stat] += 1
        return send_to_review(candidate, reason, run, stats, model: nil)
      end
      return stats["already_recommended"] += 1 if recommended?(candidate)

      # A verdict a code check produced (e.g. nothing stored) names no model.
      model = verdict.by_code ? nil : run.model
      case verdict.outcome
      when :publish then recommend(candidate, verdict, run, stats, model:)
      when :review then send_to_review(candidate, verdict.reason, run, stats, confidence: verdict.confidence, model:)
      when :reject
        candidate.update!(status: "rejected", notes: verdict.reason)
        stats["rejected"] += 1
        retire_proposal(candidate, run)
      end
    end

    # [stats key, reason] when a candidate must go to review before any model
    # is asked, or nil.
    def hold_reason(candidate)
      record = directory.attached_record(candidate)
      if record&.closed?
        return [ "human_decision", "#{record.name.upcase_first} was #{record.decision} after this was matched to it. " \
          "The same thing again, or a new record?" ]
      end

      differences = DataQuality::Differences.with_human_verified(candidate, record)
      return [ "conflicts", DataQuality::Differences.describe(differences) ] if differences.any?

      unless quote_found?(candidate)
        return [ "quote_missing", "The cited quote isn't in the source as stored, so it can't be checked: " \
          "#{candidate.quote.to_s.truncate(120).inspect}" ]
      end

      nil
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

    def recommend(candidate, verdict, run, stats, model: run.model)
      candidate.update!(ai_fields("recommend_publish", verdict.reason, verdict.confidence, run, model:))
      stats["recommended"] += 1
    end

    # A rejected candidate whose record match created (a proposal) retires
    # that record, unless another live candidate is attached to it too.
    def retire_proposal(candidate, run)
      return unless candidate.subject_id

      attached = Candidate.where(subject_type: candidate.subject_type, subject_id: candidate.subject_id)
      return unless attached.where(proposed_subject: true).exists?
      return if attached.where.not(id: candidate.id).where(status: %w[new matched merged needs_review]).exists?

      directory.retire(candidate, crawl_run: run)
    end

    def recommended?(candidate) = candidate.ai_recommendation == "recommend_publish"

    # model: nil for a code check, which asked no model.
    def send_to_review(candidate, reason, run, stats, confidence: nil, model: run.model)
      candidate.update!(ai_fields("needs_review", reason, confidence, run, model:).merge(status: "needs_review", notes: reason))
      stats["needs_review"] += 1
    end

    def ai_fields(recommendation, reason, confidence, run, model: run.model)
      { ai_recommendation: recommendation, ai_reason: reason, ai_confidence: confidence,
        ai_model: model, ai_checked_at: Time.current, verify_run: run }
    end
end
