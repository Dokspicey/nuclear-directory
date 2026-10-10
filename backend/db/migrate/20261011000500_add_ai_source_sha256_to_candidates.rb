# Which snapshot of the source a recommendation was made against (#15): when
# the source changes, the recommendation no longer stands and verify asks
# again.
class AddAiSourceSha256ToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :ai_source_sha256, :string
  end
end
