# Each time a person reopens a rejected candidate (#228): who, when and why.
# Appended only, so later match notes and review decisions don't erase it.
class AddReopeningsToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :reopenings, :jsonb, default: [], null: false
  end
end
