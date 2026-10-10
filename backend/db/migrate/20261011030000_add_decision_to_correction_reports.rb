# How a correction ended, and who decided (#86's corrections inbox): fixed
# (the record was changed) or dismissed, by "human:<handle>".
class AddDecisionToCorrectionReports < ActiveRecord::Migration[8.1]
  def change
    change_table :correction_reports, bulk: true do |t|
      t.string :resolution
      t.string :decided_by
      t.datetime :decided_at
    end
    add_check_constraint :correction_reports, "resolution IN ('fixed', 'dismissed')", name: "correction_reports_resolution_check"
  end
end
