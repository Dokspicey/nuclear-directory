# A site or a unit at a site. Reactor units point at their site via parent.
# facility_type and status stay blank until a source states them.
class Facility < ApplicationRecord
  include Verifiable
  include Sluggable
  include Hierarchical

  enum :facility_type, %w[power_reactor research_reactor fuel_facility enrichment fusion_facility uranium_mine mill other]
    .index_by(&:itself),
    validate: { allow_nil: true }
  enum :status, %w[operating under_construction planned shut_down decommissioning].index_by(&:itself),
    validate: { allow_nil: true }

  belongs_to :technology, optional: true
  has_many :facility_relationships, dependent: :destroy
  has_many :organizations, -> { distinct }, through: :facility_relationships

  normalizes :nrc_docket, with: ->(docket) { docket.strip.presence }
  normalizes :country_code, with: ->(code) { code.strip.upcase }

  validates :name, presence: true
  validates :nrc_docket, uniqueness: true, allow_nil: true
  validates :country_code, length: { is: 2 }
  validates :capacity_mw, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
end
