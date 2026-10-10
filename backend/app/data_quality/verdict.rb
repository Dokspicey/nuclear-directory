# A verifier's decision about one candidate.
#   outcome    - :publish, :review or :reject
#   confidence - 0..1, stored on the evidence when published
#   reason     - shown to the maintainer in the review queue
#   by_code    - true when a code check decided and no model was asked
class DataQuality::Verdict < Data.define(:outcome, :confidence, :reason, :by_code)
  OUTCOMES = %i[publish review reject].freeze

  def initialize(outcome:, confidence: nil, reason: nil, by_code: false)
    raise ArgumentError, "unknown outcome #{outcome.inspect}" unless OUTCOMES.include?(outcome)

    super
  end
end
