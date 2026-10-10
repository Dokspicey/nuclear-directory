# Another name a plant goes by ("Three Mile Island Unit 1", "TMI"), for
# lookups and search (#65). normalized_alias is what's compared, so two
# spellings of the same name can't point at different facilities.
class FacilityAlias < ApplicationRecord
  belongs_to :facility

  before_validation { self.normalized_alias = self.class.normalize(self.alias) }

  validates :alias, presence: true
  validates :normalized_alias, presence: true, uniqueness: true

  # Lowercased, "&" as "and", punctuation dropped: "Plant Vogtle Units 3 & 4"
  # => "plant vogtle units 3 and 4". Unlike company names, no words are dropped,
  # since "Unit 1" is what tells one name from another.
  def self.normalize(name)
    name.to_s.downcase.gsub("&", " and ").gsub(/[^a-z0-9\s]/, " ").split.join(" ")
  end
end
