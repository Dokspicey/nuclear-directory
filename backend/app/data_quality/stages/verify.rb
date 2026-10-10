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
        # A human may have rejected or unpublished the record since match
        # attached this candidate to it; that decision goes to review, named.
        if (subject = directory.attached_record(candidate))&.closed?
          send_to_review(candidate, "#{subject.name.upcase_first} was #{subject.decision} after this was matched to it. " \
            "The same thing again, or a new record?", stats)
          next
        end

        verdict = @verifier.call(candidate)

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

    def publish(candidate, verdict, run, stats)
      result = directory.write_fact(candidate, confidence: verdict.confidence, crawl_run: run)

      if result.success?
        candidate.update!(status: "merged", subject_type: result.ref.type, subject_id: result.ref.id)
        stats["published"] += 1
        fill_site(candidate, result.ref.id, run, stats) if candidate.kind_facility?
      else
        stats["write_errors"] += 1
        send_to_review(candidate, "Directory rejected the write: #{result.errors.join('; ')}", stats)
      end
    end

    # A verified unit completes its site's missing details (see DirectoryClient).
    # The unit itself is already published, so a site that refuses (a human
    # rejected it) is noted on the candidate rather than undoing the unit.
    def fill_site(candidate, unit_id, run, stats)
      result = directory.fill_site_from_unit(unit_id, candidate, crawl_run: run)
      return if result.nil? || result.success?
      # The unit disagrees with what a human recorded for its site: published,
      # but a human should look (e.g. NRC's state is a nearby city's).
      if result.conflict?
        return send_to_review(candidate, "Published, but its site disagrees: #{result.errors.join('; ')}", stats)
      end

      stats["site_not_filled"] = stats.fetch("site_not_filled", 0) + 1
      candidate.update!(notes: [ candidate.notes, "Site not filled: #{result.errors.join('; ')}" ].compact_blank.join(". "))
    end

    # When the last live candidate attached to a record match created (a
    # proposal) is rejected, the proposal is retired. Which candidate created
    # it doesn't matter. A record that existed before match is left alone.
    def retire_proposal(candidate, run)
      return unless candidate.subject_id

      attached = Candidate.where(subject_type: candidate.subject_type, subject_id: candidate.subject_id)
      return unless attached.where(proposed_subject: true).exists?
      return if attached.where.not(id: candidate.id).where(status: %w[new matched merged needs_review]).exists?

      directory.retire(candidate, crawl_run: run)
    end

    def send_to_review(candidate, reason, stats)
      candidate.update!(status: "needs_review", notes: reason)
      stats["needs_review"] += 1
    end
end
