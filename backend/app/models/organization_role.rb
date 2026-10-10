class OrganizationRole < ApplicationRecord
  include Verifiable

  belongs_to :organization
  belongs_to :role

  validates :role_id, uniqueness: { scope: :organization_id }
end
