# fission, fusion, and sub-types such as smr (under fission).
class Technology < ApplicationRecord
  include Lookup

  has_many :organization_technologies, dependent: :restrict_with_error
  has_many :organizations, through: :organization_technologies
  has_many :facilities, dependent: :restrict_with_error
end
