# EIA's plant ID on a site (#121), so the EIA plug-in finds the plant it
# proposed before, or one a human linked, and never creates it twice. One
# site per EIA plant; units don't carry it.
class AddEiaPlantIdToFacilities < ActiveRecord::Migration[8.1]
  def change
    add_column :facilities, :eia_plant_id, :string
    add_index :facilities, :eia_plant_id, unique: true, where: "parent_id IS NULL AND eia_plant_id IS NOT NULL",
      name: "index_facilities_on_eia_plant_id_for_sites"
  end
end
