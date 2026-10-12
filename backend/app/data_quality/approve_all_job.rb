# "Approve all recommended" in the review queue (#188): the claims a person
# chose with one click, approved in the background so a few hundred don't
# hold up a web request. The decision is theirs (by: "human:<handle>"), and
# each claim is re-checked as it's approved, exactly as "Approve selected"
# does: one that's no longer recommended (its source changed, a person
# decided it meanwhile) is skipped and stays in the queue.
class DataQuality::ApproveAllJob < ApplicationJob
  BATCH = 50

  queue_as :data_quality

  def perform(candidate_ids, by:)
    approved = skipped = 0
    candidate_ids.each_slice(BATCH) do |batch|
      results = DataQuality::Review.approve(batch, by:, only_recommended: true)
      approved += results.count(&:ok?)
      skipped += results.count { |result| !result.ok? }
    end
    Rails.logger.info("[review] #{by} approved #{approved} recommended claims; #{skipped} skipped and left in the queue")
  end
end
