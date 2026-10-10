# Who decided on a candidate in the admin, and when (#85). The fact's own
# history is in verification_events; this records the decision on the claim.
class AddReviewDecisionToCandidates < ActiveRecord::Migration[8.1]
  def change
    change_table :candidates, bulk: true do |t|
      t.string :reviewed_by
      t.datetime :reviewed_at
    end
  end
end
