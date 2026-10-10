# Other names a plant goes by ("Three Mile Island Unit 1" for Crane Clean
# Energy Center), so Directory::Lookup finds it under them, and search can
# match them once it exists (#65). Like
# organization_aliases: one normalized spelling belongs to one facility.
class CreateFacilityAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :facility_aliases do |t|
      t.references :facility, null: false, foreign_key: true
      t.string :alias, null: false
      t.string :normalized_alias, null: false
      t.timestamps

      t.index :normalized_alias, unique: true
    end
  end
end
