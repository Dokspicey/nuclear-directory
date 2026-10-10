# A verifier's decision about one candidate.
#   outcome    - :publish, :review or :reject
#   confidence - 0..1, stored on the evidence when published
#   reason     - shown to the maintainer in the review queue
class DataQuality::Verdict < Data.define(:outcome, :confidence, :reason)
  OUTCOMES = %i[publish review reject].freeze

  def initialize(outcome:, confidence: nil, reason: nil)
    raise ArgumentError, "unknown outcome #{outcome.inspect}" unless OUTCOMES.include?(outcome)

    super
  end
end
