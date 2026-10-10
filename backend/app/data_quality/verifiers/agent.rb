# The verifier agent (#15): a second model, different from the extractor
# (OPENROUTER_VERIFY_MODEL), re-reads the source and says whether it
# supports each claim. It works in batches, one source at a time.
#
# - supported, and at least PUBLISH_AT sure: publish, with that confidence
# - supported but less sure, disputed, or not enough in the source: review,
#   with the model's reason
# The agent never rejects on its own; v1 leaves rejections to a person.
class DataQuality::Verifiers::Agent
  PROMPT_VERSION = "verify-v1"
  BATCH_SIZE = 15
  PUBLISH_AT = 0.8
  NOTHING_STORED = DataQuality::Verdict.new(outcome: :review,
    reason: "The source has no stored content, so the claim can't be checked against it")

  SCHEMA = {
    "type" => "object",
    "properties" => {
      "results" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "string" },
            "verdict" => { "type" => "string", "enum" => %w[supported contradicted not_enough_info] },
            # No minimum/maximum: not every provider's structured output accepts
            # them. verdict_for sends an out-of-range value to review.
            "confidence" => { "type" => "number", "description" => "0 to 1" },
            "reason" => { "type" => "string", "description" => "One short sentence, citing the excerpt" }
          },
          "required" => %w[id verdict confidence reason],
          "additionalProperties" => false
        }
      }
    },
    "required" => [ "results" ],
    "additionalProperties" => false
  }.freeze

  INSTRUCTIONS = <<~TEXT.freeze
    You are an independent fact checker for a directory of the US nuclear industry.
    Each claim comes with an excerpt from its source. Using ONLY the source and the
    excerpt, decide whether the claim is true:
    - supported: the excerpt states every detail of the claim, or the source plainly implies it
    - contradicted: the excerpt says something different
    - not_enough_info: the excerpt doesn't say enough to tell
    Don't use outside knowledge, even if you know the answer. Give your confidence from
    0 to 1 and one short reason that points to the excerpt. Answer every claim, by its id.
  TEXT

  def initialize(llm: nil)
    @llm = llm
  end

  # Returns { candidate_id => DataQuality::Verdict } for every candidate.
  def verdicts(candidates, run:, plugin:)
    run.update!(prompt_version: PROMPT_VERSION)

    candidates.group_by(&:source).flat_map do |source, from_source|
      # With nothing stored there's nothing to read, so no model is asked.
      next from_source.map { |candidate| [ candidate.id, NOTHING_STORED ] } if source.content_text.blank?

      from_source.each_slice(BATCH_SIZE).flat_map { |batch| ask(source, batch, run, plugin) }
    end.to_h
  end

  private
    def ask(source, batch, run, plugin)
      claims = batch.map do |candidate|
        { "id" => candidate.id.to_s, "claim" => DataQuality::Claim.describe(candidate),
          "quote" => candidate.quote, "excerpt" => plugin.verification_context(source, candidate.quote) }
      end

      response = llm.structured(
        role: :verify,
        schema: SCHEMA,
        schema_name: "claim_verdicts",
        crawl_run: run,
        reasoning_effort: "low",
        messages: [
          { role: "system", content: INSTRUCTIONS },
          { role: "user", content: "Source: #{source.title.presence || source.domain} (#{source.url})\n\n" \
            "Claims:\n#{JSON.pretty_generate(claims)}" }
        ]
      )
      answers = response.data.fetch("results").index_by { |answer| answer["id"] }

      batch.map { |candidate| [ candidate.id, verdict_for(answers[candidate.id.to_s]) ] }
    end

    def verdict_for(answer)
      return DataQuality::Verdict.new(outcome: :review, reason: "The verifier gave no answer for this claim") unless answer

      reason = answer["reason"].to_s.squish
      raw = answer["confidence"]
      # Out of range means the answer is malformed: a person looks, rather
      # than clamping 2 into "100% sure".
      unless raw.is_a?(Numeric) && raw.between?(0, 1)
        return DataQuality::Verdict.new(outcome: :review, reason: "The verifier gave an invalid confidence (#{raw.inspect}): #{reason}")
      end

      # The threshold is checked before rounding, so 0.795 stays below 80%.
      sure_enough = raw >= PUBLISH_AT
      confidence = raw.to_f.round(2)

      case answer["verdict"]
      when "supported"
        if sure_enough
          DataQuality::Verdict.new(outcome: :publish, confidence:, reason:)
        else
          DataQuality::Verdict.new(outcome: :review, confidence:,
            reason: "The verifier thinks the source supports this, but is only #{(raw * 100).floor}% sure: #{reason}")
        end
      when "contradicted"
        DataQuality::Verdict.new(outcome: :review, confidence:, reason: "The verifier says the source contradicts this: #{reason}")
      else
        DataQuality::Verdict.new(outcome: :review, confidence:, reason: "The verifier couldn't confirm this from the source: #{reason}")
      end
    end

    # Built on first use, so nothing needs an OpenRouter key until verify runs.
    def llm = @llm ||= DataQuality::OpenRouter::Client.new
end
