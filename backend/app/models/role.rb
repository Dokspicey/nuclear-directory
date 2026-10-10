# What an organization does in the supply chain, e.g. reactor_vendor.
# Sub-roles (coolant → molten_salt) point at their parent.
class Role < ApplicationRecord
  include Lookup

  has_many :organization_roles, dependent: :restrict_with_error
  has_many :organizations, through: :organization_roles
end
