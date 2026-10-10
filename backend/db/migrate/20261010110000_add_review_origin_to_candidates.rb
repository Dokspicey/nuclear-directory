# Which stage sent a candidate to review. Extract-time flags ("extract")
# belong to one snapshot of a source and are replaced when it's extracted
# again; flags raised later (match, verify) or awaiting a person are kept.
class AddReviewOriginToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :review_origin, :string
  end
end
