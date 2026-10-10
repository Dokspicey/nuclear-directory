# Default verifier until the verifier agent exists (#15): nothing is
# published automatically, every candidate goes to the review queue.
class DataQuality::Verifiers::ReviewEverything
  def call(_candidate)
    DataQuality::Verdict.new(outcome: :review, reason: "No automatic verifier configured yet")
  end
end
