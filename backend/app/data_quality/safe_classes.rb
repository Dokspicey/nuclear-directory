# Safe classes (#306, option A): verifier recommendations that "Accept
# recommendations" takes without Data Quality's list, because Data
# Quality's rule says they can't change anything a person decided. The
# classes and their limits are in config/safe_verifier_classes.yml, which
# Data Quality owns; each is off until turned on there.
#
# A claim is safe only if every gate holds:
# - G1 the verifier recommends it now, confident enough
# - G2 it updates an existing published record, never creates one
# - G3 every field it changes is one the class allows, last written by the
#   pipeline from the same kind of source (Differences.pipeline_written?)
# - G4 nothing else is open on its record: no claim waiting for review, no
#   unresolved correction report
# - G5 it isn't from its source's first batch, the source's last fetch
#   returned 200, and the last match run checked for dropped facts
# - G6 its run doesn't propose too many safe changes (the cap)
# and the class's own: S1 is an update to a DOE "funds" link a person
# verified, whose award total doesn't drop by more than 20%.
#
#   DataQuality::SafeClasses.items(exclude: ids)  # => [Item, …]
#   DataQuality::SafeClasses.accept(items, by: "human:tosin") # => [Review::Result, …]
module DataQuality::SafeClasses
  CONFIG = YAML.safe_load_file(Rails.root.join("config/safe_verifier_classes.yml")).freeze
  # One claim a class covers. changes: { field => [old, new] }. why: why it
  # isn't safe, or nil. enabled: whether its class is on (off, the preview
  # shows what it would take). snapshot: the claim as the preview showed it.
  Item = Data.define(:candidate_id, :klass, :label, :enabled, :snapshot, :claim, :changes, :subject_type, :subject_id, :why) do
    def safe? = why.nil?
    def taken? = safe? && enabled
  end
  # "$2.62 billion", "$921.7 million", "$750,000" in an award summary.
  TOTAL = /totaling \$([\d,]+(?:\.\d+)?)(?: (million|billion))?/
  SCALE = { nil => 1, "million" => 1_000_000, "billion" => 1_000_000_000 }.freeze

  class << self
    # Every claim a class covers that the verifier recommends, safe or not,
    # oldest first. exclude: claims Data Quality has its own call on.
    def items(exclude: [], directory: DataQuality::DirectoryClient.new)
      firsts = DataQuality::Review.first_batches
      CONFIG.fetch("classes").flat_map do |klass, config|
        claims = covered(klass).where.not(id: exclude).includes(:source).order(:id).to_a
        items = claims.map do |candidate|
          why = why_not(candidate, klass, firsts:, directory:)
          record = directory.attached_record(candidate) if candidate.subject_id
          changes = (DataQuality::Differences.changes(candidate, record, directory:) if record) || {}
          Item.new(candidate_id: candidate.id, klass:, label: config.fetch("label"), enabled: config["enabled"] == true,
            snapshot: snapshot(candidate), claim: DataQuality::Claim.describe(candidate), changes:,
            subject_type: candidate.subject_type, subject_id: candidate.subject_id, why:)
        end
        capped(items, config, claims, directory:)
      end
    end

    # The decision's reason in the record's history.
    def reason(item) = "Accepted the verifier's recommendation (safe class #{item.klass}: #{item.label})"

    def fingerprint_parts(items) = items.map { |item| [ item.candidate_id, item.klass, item.snapshot ] }

    # Approves these items (a plan's safe ones) as `by`'s decision, each
    # under its source's and its record's locks, with every gate but the cap
    # asked again there (the cap was the page's, which the click matched).
    def accept(items, by:, directory: DataQuality::DirectoryClient.new)
      DataQuality::Review.human!(by)
      firsts = DataQuality::Review.first_batches
      items.sort_by(&:candidate_id).map do |item|
        result = nil
        Candidate.transaction do
          source_id = Candidate.where(id: item.candidate_id).pick(:source_id)
          result = skipped(item, "this claim no longer exists") and next unless source_id

          ::Source.lock.find(source_id)
          candidate = Candidate.lock.find_by(id: item.candidate_id)
          result = skipped(item, "this claim no longer exists") and next unless candidate
          result = skipped(item, "it changed after the page loaded") and next unless snapshot(candidate) == item.snapshot

          check = ->(locked) { why_not(locked, item.klass, firsts:, directory:) }
          result = DataQuality::Review.approve([ candidate.id ], by:, reason: reason(item), only_recommended: true, safe_check: check,
            directory:).first
          raise ActiveRecord::Rollback unless result.ok?
        end
        result
      rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
        skipped(item, "someone was deciding on it just then; try again")
      end
    end

    # Why a claim isn't safe in its class, or nil. Every gate but the cap.
    def why_not(candidate, klass, firsts:, directory:)
      config = CONFIG.fetch("classes").fetch(klass)
      # G1
      return "the verifier doesn't recommend it now" unless covered(klass).exists?(candidate.id)
      return "the verifier's confidence is below #{config.fetch('min_confidence')}" if candidate.ai_confidence.to_f < config.fetch("min_confidence")

      # G2, with S1's own: a published DOE funds link, both ends published, a person verified it.
      return "it isn't attached to a link yet" unless candidate.subject_type == "Relationship" && candidate.subject_id

      type, id = candidate.subject_type, candidate.subject_id
      record = directory.fact(type:, id:)
      return "its link isn't verified and public" unless record&.verification_status == "verified" && directory.published?(type:, id:)

      values = record.values
      unless values["relationship_type"] == config.fetch("relationship_type") && values["from_organization_name"] == config.fetch("funder")
        return "it isn't a #{config.fetch('funder')} #{config.fetch('relationship_type')} link"
      end
      unless [ values["from_organization_id"], values["to_organization_id"] ].all? { |end_id| directory.published?(type: "Organization", id: end_id) }
        return "a company on its link isn't public"
      end
      unless directory.verification_history(type:, id:).any? { |event| event.to_status == "verified" && event.by.to_s.start_with?("human:") }
        return "no person has verified its link"
      end

      # G3
      changes = DataQuality::Differences.changes(candidate, record, directory:) or return "it changes a field that can't be compared"
      return "it changes nothing" if changes.empty?

      others = changes.keys - config.fetch("fields")
      if others.any?
        allowed = config.fetch("fields").map { |name| label(name) }.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
        return "it changes #{others.map { |name| label(name) }.to_sentence}, not only #{allowed}"
      end
      return "it changes a value a person wrote" unless DataQuality::Differences.pipeline_written?(candidate, record, directory:)

      # G4
      waiting = Candidate.where(subject_type: type, subject_id: id).where.not(id: candidate.id)
      return "another claim on its link waits for review" if waiting.where(status: "needs_review").exists?
      return "a correction report on its page isn't resolved" if directory.open_corrections?(type:, id:)

      # G5
      return DataQuality::Review::FIRST_BATCH if candidate.crawl_run_id && firsts[candidate.source.source_kind] == candidate.crawl_run_id
      return "its source's last fetch didn't return 200" unless candidate.source.http_status == 200

      match = CrawlRun.where(stage: "match", source_kind: candidate.source.source_kind, status: "succeeded").order(started_at: :desc, id: :desc).first
      return "the last match run didn't check for dropped facts" if match.nil? || match.stats["dropped_check_skipped"].to_i.positive?

      # S1: the award total doesn't drop too far.
      if changes.key?("description")
        before, after = changes.fetch("description").map { |text| total(text) }
        return "its award total can't be read" unless before && after
        return "its award total drops by more than #{(config.fetch('max_total_drop') * 100).round}%" if after < before * (1 - config.fetch("max_total_drop"))
      end

      nil
    end

    private
      # The recommended claims a class covers: its source and kind, with no
      # call from Data Quality (its list decides those).
      def covered(klass)
        config = CONFIG.fetch("classes").fetch(klass)
        Candidate.recommended.where(kind: config.fetch("kind"), dq_recommendation: nil)
          .where(sources: { source_kind: config.fetch("source_kind") })
      end

      # G6: a run that proposes more safe changes than the cap, or more than
      # its share of the source's published facts, gets none of them taken.
      def capped(items, config, claims, directory:)
        cap = CONFIG.fetch("cap")
        runs = claims.to_h { |candidate| [ candidate.id, candidate.crawl_run_id ] }
        facts = directory.published_count_backed_by(source_ids: ::Source.where(source_kind: config.fetch("source_kind")).ids)
        limit = [ cap.fetch("max_items"), (facts * cap.fetch("max_share")).floor ].min
        over = items.select(&:safe?).group_by { |item| runs[item.candidate_id] }.select { |_run, group| group.size > limit }
        items.map do |item|
          group = over[runs[item.candidate_id]]
          next item unless group && item.safe?

          item.with(why: "its run proposes #{group.size} safe changes, over the limit of #{limit} " \
            "(#{cap.fetch('max_items')}, or #{(cap.fetch('max_share') * 100).round}% of the source's #{facts} public facts)")
        end
      end

      def label(name) = DataQuality::Claim::LABELS.fetch(name) { name.humanize(capitalize: false) }

      # In dollars, or nil.
      def total(text)
        match = TOTAL.match(text.to_s) or return
        BigDecimal(match[1].delete(",")) * SCALE.fetch(match[2])
      end

      # The claim as the preview showed it, and as the verifier judged it.
      def snapshot(candidate)
        Digest::SHA256.hexdigest([ candidate.payload, candidate.quote, candidate.subject_type, candidate.subject_id, candidate.reopenings,
          candidate.ai_source_sha256, candidate.ai_confidence&.to_s, candidate.verify_run_id ].to_json)
      end

      def skipped(item, why) = DataQuality::Review::Result.new(candidate_id: item.candidate_id, ref: nil, errors: [ why ])
  end
end
