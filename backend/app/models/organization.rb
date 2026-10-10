class Organization < ApplicationRecord
  include Verifiable
  include Sluggable

  enum :status, %w[active acquired defunct].index_by(&:itself), default: "active", validate: true

  has_many :aliases, class_name: "OrganizationAlias", dependent: :destroy
  has_many :organization_roles, dependent: :destroy
  has_many :roles, through: :organization_roles
  has_many :organization_technologies, dependent: :destroy
  has_many :technologies, through: :organization_technologies
  has_many :outgoing_relationships, class_name: "Relationship", foreign_key: :from_organization_id,
    inverse_of: :from_organization, dependent: :destroy
  has_many :incoming_relationships, class_name: "Relationship", foreign_key: :to_organization_id,
    inverse_of: :to_organization, dependent: :destroy
  has_many :facility_relationships, dependent: :destroy
  has_many :facilities, -> { distinct }, through: :facility_relationships

  normalizes :domain, with: ->(domain) { domain.strip.downcase.delete_prefix("www.").presence }
  normalizes :country_code, with: ->(code) { code.strip.upcase }

  validates :name, presence: true
  validates :domain, uniqueness: true, allow_nil: true
  validates :country_code, length: { is: 2 }
  validates :founded_year, numericality: { only_integer: true, in: 1800..2100 }, allow_nil: true
end
