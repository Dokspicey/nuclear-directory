class OrganizationTechnology < ApplicationRecord
  include Verifiable

  belongs_to :organization
  belongs_to :technology

  validates :technology_id, uniqueness: { scope: :organization_id }
end
