# Old URL slugs of renamed or merged records (#143), so an old address
# redirects to the record's current page.
class CreateFormerSlugs < ActiveRecord::Migration[8.1]
  def change
    create_table :former_slugs do |t|
      t.references :sluggable, polymorphic: true, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :former_slugs, %i[sluggable_type slug], unique: true
  end
end
