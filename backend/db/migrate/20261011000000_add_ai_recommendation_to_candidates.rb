# The verifier agent's recommendation on a candidate (#15). The agent never
# publishes: it recommends, and a human approves in the admin (#85, #86).
# Indexed so the admin can list recommendations by run and bulk-approve them.
class AddAiRecommendationToCandidates < ActiveRecord::Migration[8.1]
  def change
    change_table :candidates, bulk: true do |t|
      t.string :ai_recommendation # recommend_publish | needs_review
      t.text :ai_reason
      t.decimal :ai_confidence, precision: 3, scale: 2
      t.string :ai_model
      t.datetime :ai_checked_at
      t.references :verify_run, foreign_key: { to_table: :crawl_runs }, index: false
    end
    add_index :candidates, [ :ai_recommendation, :verify_run_id ]
    add_check_constraint :candidates, "ai_recommendation IN ('recommend_publish', 'needs_review')",
      name: "candidates_ai_recommendation_check"
  end
end
