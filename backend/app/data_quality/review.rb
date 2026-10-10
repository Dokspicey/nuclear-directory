# How a human decides on what the pipeline found (#85). The verifier only
# recommends; nothing is published except from here, by a person, from the
# admin (#86). The admin calls only this module: it never touches candidates,
# FactWriter or directory models itself.
#
# Candidates (claims the pipeline extracted from a source):
#   Review.candidates(queue: :recommended, run_id:, reason:)  # what to decide on
#   Review.approve(ids, by: "human:tosin")                     # publish, bulk
#   Review.edit_and_approve(id, attributes: { "state" => "NJ" }, by:)
#   Review.reject(ids, by:, reason:)
# Directory facts (published, or waiting without a candidate, e.g. seed facts
# loaded as pending):
#   Review.pending_facts(kind:)
#   Review.approve_fact(type:, id:, by:, attributes: {})       # also republish
#   Review.reject_fact(type:, id:, by:, reason:)
#   Review.unpublish(type:, id:, by:, reason:)
#   Review.history(type:, id:)
#
# Every action is a human's (by: "human:…") and returns Results; a refused
# write (e.g. an edit that duplicates another fact) comes back as errors,
# never raises.
module DataQuality::Review
  Result = Data.define(:candidate_id, :ref, :errors) do
    def ok? = errors.empty?
  end

  # A candidate as the admin shows it. differences: { "state" => ["NJ", "DE"] }
  # ([human-verified, this source]) when it disagrees with a human-verified
  # record; approving would apply the source's value.
  Item = Data.define(:candidate_id, :kind, :status, :claim, :payload, :quote, :source, :notes,
    :ai_recommendation, :ai_reason, :ai_confidence, :ai_model, :ai_checked_at, :verify_run_id,
    :subject_type, :subject_id, :differences)
  Source = Data.define(:id, :url, :title)
  EvidenceItem = Data.define(:source, :quote, :found_by, :confidence)
  PendingFact = Data.define(:type, :id, :kind, :attributes, :evidence, :created_at, :last_event)

  QUEUES = {
    recommended: -> { Candidate.recommended },
    needs_review: -> { Candidate.status_needs_review }
  }.freeze
  # Link ends were resolved by match; editing them means matching again.
  NOT_EDITABLE = %w[organization facility from_organization to_organization slug].freeze

  class << self
    # Candidates waiting for a decision, oldest first. queue: :recommended
    # (the agent recommends publishing) or :needs_review. Narrow by the
    # verify run, and by reason (the start of the note, e.g. "human-verified").
    def candidates(queue: :recommended, run_id: nil, reason: nil, after_id: nil, limit: 50,
      directory: DataQuality::DirectoryClient.new)
      scope = QUEUES.fetch(queue.to_sym).call.includes(:source).order(:id).limit(limit)
      scope = scope.where(verify_run_id: run_id) if run_id
      scope = scope.where("candidates.notes ILIKE ?", "#{Candidate.sanitize_sql_like(reason)}%") if reason.present?
      scope = scope.where("candidates.id > ?", after_id) if after_id
      scope.map { |candidate| item(candidate, directory) }
    end

    # Kinds of question in a queue, most common first, quoted names blanked
    # ('no exact match for "…"'), for the admin's reason filter.
    def reasons(queue: :needs_review, run_id: nil)
      scope = QUEUES.fetch(queue.to_sym).call
      scope = scope.where(verify_run_id: run_id) if run_id
      scope.pluck(:notes).map { |notes| notes.to_s.split(":").first.to_s.gsub(/"[^"]*"/, '"…"').squish.presence || "no reason" }
        .tally.sort_by { |reason, n| [ -n, reason ] }
    end

    # Publishes each candidate as a fact verified by `by`, with its quote as
    # evidence (the verifier's confidence, the verify run) and the candidate
    # and run in the audit trail. A human's write isn't protected, so a
    # candidate that disagrees with a human-verified value applies the new
    # value; the admin shows `differences` first. An approved unit fills its
    # site's blank fields. Already-decided candidates are refused.
    def approve(candidate_ids, by:, reason: nil, directory: DataQuality::DirectoryClient.new)
      human!(by)
      Candidate.where(id: candidate_ids).includes(:crawl_run, :verify_run).order(:id).map do |candidate|
        approve_one(candidate, by:, reason:, directory:)
      end
    end

    # Changes some of a candidate's values, then approves it. Link ends and
    # slug can't be edited here.
    def edit_and_approve(candidate_id, attributes:, by:, reason: nil, directory: DataQuality::DirectoryClient.new)
      human!(by)
      candidate = Candidate.find(candidate_id)
      attributes = attributes.to_h.stringify_keys
      if (locked = attributes.keys & NOT_EDITABLE).any?
        return Result.new(candidate_id:, ref: nil, errors: [ "can't edit #{locked.to_sentence} here" ])
      end

      result = nil
      Candidate.transaction do
        candidate.update!(payload: candidate.payload.merge(attributes))
        result = approve_one(candidate, by:, reason:, directory:)
        raise ActiveRecord::Rollback unless result.ok? # keep the original values if publishing failed
      end
      result
    end

    # Rejects candidates. A record match created only for one of them (a
    # proposal) is rejected too, unless another live candidate is attached.
    def reject(candidate_ids, by:, reason: nil, directory: DataQuality::DirectoryClient.new)
      human!(by)
      Candidate.where(id: candidate_ids).order(:id).map do |candidate|
        next Result.new(candidate_id: candidate.id, ref: nil, errors: [ already(candidate) ]) unless open?(candidate)

        candidate.update!(status: "rejected", notes: reason.presence || candidate.notes, reviewed_by: by, reviewed_at: Time.current)
        errors = retire_proposal(candidate, by:, reason:, directory:)
        Result.new(candidate_id: candidate.id, ref: nil, errors:)
      end
    end

    # Directory facts of one kind waiting for a human with no open candidate
    # (those show in the candidate queues), e.g. seed facts loaded as pending.
    def pending_facts(kind:, after_id: nil, limit: 50, directory: DataQuality::DirectoryClient.new)
      facts = directory.pending_facts(kind:, after_id:, limit:)
      open = Candidate.where(status: %w[new matched needs_review], subject_type: facts.map(&:type).uniq,
        subject_id: facts.map(&:id)).pluck(:subject_type, :subject_id).to_set
      sources = sources_by_id(facts.flat_map { |fact| fact.evidence.map(&:source_id) })

      facts.reject { |fact| open.include?([ fact.type, fact.id ]) }.map do |fact|
        PendingFact.new(type: fact.type, id: fact.id, kind: fact.kind, attributes: fact.attributes, created_at: fact.created_at,
          last_event: fact.last_event, evidence: fact.evidence.map { |e| EvidenceItem.new(source: sources[e.source_id], quote: e.quote,
            found_by: e.found_by, confidence: e.confidence) })
      end
    end

    # Approves (or republishes) a directory fact, optionally with edited
    # values; the edit is recorded in its history.
    def approve_fact(type:, id:, by:, reason: nil, attributes: {}, directory: DataQuality::DirectoryClient.new)
      decide_fact(type, id, "verified", by:, reason:, attributes:, directory:)
    end

    def reject_fact(type:, id:, by:, reason: nil, directory: DataQuality::DirectoryClient.new)
      decide_fact(type, id, "rejected", by:, reason:, directory:)
    end

    # Takes a published fact down: hidden from the public site, recorded as
    # unpublished by `by`, protected from the pipeline. Republish = approve_fact.
    def unpublish(type:, id:, by:, reason: nil, directory: DataQuality::DirectoryClient.new)
      decide_fact(type, id, "unpublished", by:, reason:, directory:)
    end

    def history(type:, id:, directory: DataQuality::DirectoryClient.new) = directory.verification_history(type:, id:)

    private
      # Evidence confidence means "how sure the source supports this". The
      # verifier's confidence only says that when it recommended publishing;
      # for a review verdict (disputed, unsure) it's confidence in that
      # verdict, so the evidence gets none.
      def supporting_confidence(candidate)
        candidate.ai_confidence if candidate.ai_recommendation == "recommend_publish"
      end

      def human!(by)
        raise ArgumentError, "only a human decides (by: \"human:…\")" unless by.to_s.start_with?("human:")
      end

      def open?(candidate) = candidate.status_new? || candidate.status_matched? || candidate.status_needs_review?
      def already(candidate) = "it's already #{candidate.status.humanize(capitalize: false)}"

      def approve_one(candidate, by:, reason:, directory:)
        return Result.new(candidate_id: candidate.id, ref: nil, errors: [ already(candidate) ]) unless open?(candidate)

        # The evidence belongs to the run that judged it (verify), else the one that found it.
        run = candidate.verify_run || candidate.crawl_run
        result = directory.write_fact(candidate, confidence: supporting_confidence(candidate), crawl_run: run, by:, reason:)
        return Result.new(candidate_id: candidate.id, ref: nil, errors: result.errors) unless result.success?

        candidate.update!(status: "merged", subject_type: result.ref.type, subject_id: result.ref.id,
          reviewed_by: by, reviewed_at: Time.current)
        fill_site(candidate, result.ref.id, run, directory) if candidate.kind_facility?
        Result.new(candidate_id: candidate.id, ref: result.ref, errors: [])
      end

      # A published unit completes its site's missing details (see
      # DirectoryClient#fill_site_from_unit). The unit stays published if the
      # site refuses (a human rejected it); the candidate notes why.
      def fill_site(candidate, unit_id, run, directory)
        filled = directory.fill_site_from_unit(unit_id, candidate, crawl_run: run)
        return if filled.nil? || filled.success?

        # A conflict (e.g. NRC's state is a nearby city's) is shown, not applied.
        why = filled.conflict? ? "Its site disagrees, so it wasn't filled" : "Site not filled"
        candidate.update!(notes: [ candidate.notes, "#{why}: #{filled.errors.join('; ')}" ].compact_blank.join(". "))
      end

      # Returns errors from rejecting the proposal, or [].
      def retire_proposal(candidate, by:, reason:, directory:)
        return [] unless candidate.subject_id

        attached = Candidate.where(subject_type: candidate.subject_type, subject_id: candidate.subject_id)
        return [] unless attached.where(proposed_subject: true).exists?
        return [] if attached.where.not(id: candidate.id).where(status: %w[new matched merged needs_review]).exists?

        directory.decide_fact(candidate.subject_type.underscore, id: candidate.subject_id, status: "rejected", by:, reason:,
          context: { "candidate_id" => candidate.id }).errors
      end

      def decide_fact(type, id, status, by:, reason:, attributes: {}, directory:)
        human!(by)
        if (locked = attributes.to_h.stringify_keys.keys & %w[slug]).any?
          return Result.new(candidate_id: nil, ref: nil, errors: [ "can't edit #{locked.to_sentence} here" ])
        end

        result = directory.decide_fact(type.to_s.underscore, id:, status:, by:, reason:, attributes:)
        Result.new(candidate_id: nil, ref: result.ref, errors: result.errors)
      end

      def item(candidate, directory)
        differences = DataQuality::Differences.with_human_verified(candidate, directory.attached_record(candidate))
        Item.new(candidate_id: candidate.id, kind: candidate.kind, status: candidate.status, claim: DataQuality::Claim.describe(candidate),
          payload: candidate.payload, quote: candidate.quote, notes: candidate.notes,
          source: Source.new(id: candidate.source.id, url: candidate.source.url, title: candidate.source.title),
          ai_recommendation: candidate.ai_recommendation, ai_reason: candidate.ai_reason, ai_confidence: candidate.ai_confidence,
          ai_model: candidate.ai_model, ai_checked_at: candidate.ai_checked_at, verify_run_id: candidate.verify_run_id,
          subject_type: candidate.subject_type, subject_id: candidate.subject_id, differences:)
      end

      def sources_by_id(ids)
        ::Source.where(id: ids.uniq).to_h { |source| [ source.id, Source.new(id: source.id, url: source.url, title: source.title) ] }
      end
  end
end
