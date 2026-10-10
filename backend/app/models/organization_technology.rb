class OrganizationTechnology < ApplicationRecord
  include Verifiable

  belongs_to :organization
  belongs_to :technology

  validates :technology_id, uniqueness: { scope: :organization_id }

  # Hidden when its company isn't published.
  def self.published = verified.where(organization_id: Organization.published.select(:id))
end
