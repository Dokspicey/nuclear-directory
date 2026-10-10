# Fields the hand-checked seed (#9) needs so nothing in it is lost or guessed:
# - facility type/status and organization country can be unknown until a
#   source states them, rather than defaulted to a value we haven't checked
# - sources keep the page's publish date
# - facility links get a description, like org-to-org relationships have
class AddSeedDataFields < ActiveRecord::Migration[8.1]
  def change
    change_column_null :facilities, :facility_type, true
    change_column_null :facilities, :status, true
    change_column_null :organizations, :country_code, true

    add_column :sources, :published_on, :date
    add_column :facility_relationships, :description, :text
  end
end
