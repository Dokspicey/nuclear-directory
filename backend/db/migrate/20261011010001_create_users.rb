# Admin accounts (#86). handle names the person in the audit trail
# ("human:tosin"), so decisions don't carry an email address.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :handle, null: false

      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_index :users, :handle, unique: true
    add_check_constraint :users, "handle ~ '^[a-z][a-z0-9_-]*$'", name: "users_handle_format"
  end
end
