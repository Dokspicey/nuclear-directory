# Corrections visitors send from a company or plant page (#44). Anonymous:
# no IP address or user agent is stored; contact is optional.
class CreateCorrectionReports < ActiveRecord::Migration[8.1]
  def change
    create_table :correction_reports do |t|
      t.string :subject, null: false
      t.string :page_path, null: false
      t.text :message, null: false
      t.string :contact
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :correction_reports, :status
    add_check_constraint :correction_reports, "status IN ('open', 'reviewed', 'closed')", name: "correction_reports_status_check"
  end
end
