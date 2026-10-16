# The admin's "exits" list (#166): facts rejected or unpublished, newest first.
class AddExitsIndexToVerificationEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :verification_events, [ :to_status, :created_at ], name: "index_verification_events_on_to_status_and_created_at"
  end
end
