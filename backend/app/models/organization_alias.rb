# Another name an organization goes by ("Westinghouse Electric Company LLC",
# "Westinghouse"). normalized_alias is what the matcher compares, so two
# spellings of the same name can't point at different organizations.
class OrganizationAlias < ApplicationRecord
  # Company-type suffixes dropped from the end of a name before comparing.
  SUFFIXES = %w[inc incorporated llc l l c co company corp corporation ltd limited plc lp llp].freeze

  belongs_to :organization

  before_validation { self.normalized_alias = self.class.normalize(self.alias) }

  validates :alias, presence: true
  validates :normalized_alias, presence: true, uniqueness: true

  def self.normalize(name)
    words = name.to_s.downcase.gsub("&", " and ").gsub(/[^a-z0-9\s]/, " ").split
    words.pop while words.size > 1 && SUFFIXES.include?(words.last)
    words.join(" ")
  end
end
