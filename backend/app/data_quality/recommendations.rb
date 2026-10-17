# Data Quality's recommendations (#306): its call on each claim it
# reviewed, approve or reject with a reason, and one button that accepts
# them all as a person's decision.
#
# Data Quality sends the list in a message; Tosin pastes it into Checks:
#
#   # DOE awards, 18 Oct
#   1234 approve: the award page names General Atomics as the recipient
#   1235 reject: a subcontract, not an award to this company
#
# Blank lines and lines starting with # are skipped; any other line that
# isn't "<claim id> approve|reject: <reason>" is an error, never guessed at.
# A JSON array of { "id", "recommendation", "reason" } works too. Recording
# a list decides nothing: Accept does, and only for claims that are still
# as Data Quality saw them and pass the same checks as Approve all, except
# the first-batch hold, which is what Data Quality's review is for.
#
#   DataQuality::Recommendations.record(text, by: "human:tosin")  # => Recorded
#   DataQuality::Recommendations.plan                             # => Plan (accept: […], left: […])
#   DataQuality::Recommendations.accept(ids, by: "human:tosin")    # => [Review::Result, …]
module DataQuality::Recommendations
  CALLS = %w[approve reject].freeze
  REASON_LIMIT = 500
  # What every accepted decision's history says, before Data Quality's reason.
  ACCEPTED = "Accepted Data Quality's recommendation".freeze
  OPEN = %w[new matched needs_review].freeze
  LINE = /\A\s*#?(\d+)\s+(approve|reject)\s*:\s*(.+?)\s*\z/i

  Recorded = Data.define(:recorded, :errors)
  # One recommendation as the preview shows it. why: why it's left for a
  # person (nil when it will be accepted).
  Item = Data.define(:candidate_id, :call, :reason, :claim, :subject_type, :subject_id, :why)
  Plan = Data.define(:accept, :left) do
    # The exact list Accept will act on, compared on the click (as Approve all's).
    def fingerprint = DataQuality::Recommendations.fingerprint(accept)
  end

  class << self
    # Parses the pasted list and records each call on its claim. Returns
    # Recorded(recorded: count, errors: ["line 3: …"]).
    def record(text, by:)
      DataQuality::Review.human!(by)
      calls, errors = parse(text.to_s)
      recorded = 0
      calls.each do |line, id, call, reason|
        candidate = Candidate.find_by(id:)
        next errors << "line #{line}: there's no claim #{id}" unless candidate
        next errors << "line #{line}: claim #{id} is already #{candidate.status}" unless OPEN.include?(candidate.status)

        candidate.update!(dq_recommendation: call, dq_reason: reason, dq_by: by, dq_at: Time.current, dq_payload_sha256: digest(candidate))
        recorded += 1
      end
      Recorded.new(recorded:, errors:)
    end

    # Every open claim with a recommendation: those Accept will act on, and
    # those left for a person, each with why.
    def plan(directory: DataQuality::DirectoryClient.new)
      firsts = DataQuality::Review.first_batches
      items = Candidate.where(status: OPEN).where.not(dq_recommendation: nil).includes(:source).order(:id).map do |candidate|
        Item.new(candidate_id: candidate.id, call: candidate.dq_recommendation, reason: candidate.dq_reason,
          claim: DataQuality::Claim.describe(candidate), subject_type: candidate.subject_type, subject_id: candidate.subject_id,
          why: why_left(candidate, directory:, firsts:))
      end
      accept, left = items.partition { |item| item.why.nil? }
      Plan.new(accept:, left:)
    end

    def fingerprint(items) = Digest::SHA256.hexdigest(items.map { |item| [ item.candidate_id, item.call, item.reason ] }.to_json)

    # Accepts the recommendations on these claims as `by`'s decision, each
    # checked again as it's decided; one that no longer qualifies is skipped
    # with why. Returns a Review::Result per claim.
    def accept(candidate_ids, by:, directory: DataQuality::DirectoryClient.new)
      DataQuality::Review.human!(by)
      firsts = DataQuality::Review.first_batches
      Candidate.where(id: candidate_ids).includes(:source).order(:id).map do |candidate|
        if (why = why_left(candidate, directory:, firsts:))
          next DataQuality::Review::Result.new(candidate_id: candidate.id, ref: nil, errors: [ why ])
        end

        reason = "#{ACCEPTED}: #{candidate.dq_reason}"
        if candidate.dq_recommendation == "approve"
          DataQuality::Review.approve([ candidate.id ], by:, reason:, only_recommended: true, data_quality_reviewed: true, directory:).first
        else
          DataQuality::Review.reject([ candidate.id ], by:, reason:, directory:).first
        end
      end
    end

    private
      # [[line number, id, call, reason], …] and ["line n: …"] errors.
      def parse(text)
        return parse_json(text) if text.lstrip.start_with?("[")

        calls, errors = [], []
        text.each_line.with_index(1) do |raw, line|
          stripped = raw.strip
          next if stripped.empty? || (stripped.start_with?("#") && !stripped.match?(/\A#\d/))

          match = LINE.match(stripped)
          next errors << "line #{line}: “#{stripped.truncate(80)}” isn't “<claim id> approve: <reason>” or “… reject: …”" unless match

          calls << [ line, match[1].to_i, match[2].downcase, match[3].truncate(REASON_LIMIT) ]
        end
        [ calls, errors ]
      end

      def parse_json(text)
        rows = JSON.parse(text)
        raise JSON::ParserError, "not a list" unless rows.is_a?(Array)

        calls, errors = [], []
        rows.each.with_index(1) do |row, line|
          id, call, reason = row.is_a?(Hash) ? row.values_at("id", "recommendation", "reason") : []
          unless id.to_s.match?(/\A\d+\z/) && CALLS.include?(call.to_s.downcase) && reason.present?
            next errors << "item #{line}: needs an id, a recommendation (approve or reject) and a reason"
          end

          calls << [ line, id.to_i, call.to_s.downcase, reason.to_s.strip.truncate(REASON_LIMIT) ]
        end
        [ calls, errors ]
      rescue JSON::ParserError => error
        [ [], [ "the list isn't valid JSON: #{error.message.truncate(80)}" ] ]
      end

      # nil when Accept may act on it; otherwise why a person decides it.
      def why_left(candidate, directory:, firsts:)
        return "it's already #{candidate.status}" unless OPEN.include?(candidate.status)
        return "it changed after Data Quality looked at it" unless candidate.dq_payload_sha256 == digest(candidate)
        return if candidate.dq_recommendation == "reject"

        return "the verifier didn't recommend it" unless candidate.ai_recommendation == "recommend_publish"
        return "it's waiting for a person's review" if candidate.status_needs_review?
        return "its source changed after the verifier checked it" unless Candidate.recommended.exists?(candidate.id)
        return "its company or plant isn't settled yet" unless candidate.subject_id

        held = DataQuality::Review.held_reason(candidate, directory:, firsts:)
        held unless held == DataQuality::Review::FIRST_BATCH
      end

      # The claim as Data Quality saw it: what it says and what it's attached to.
      def digest(candidate) = Digest::SHA256.hexdigest([ candidate.payload, candidate.quote, candidate.subject_type, candidate.subject_id ].to_json)
  end
end
