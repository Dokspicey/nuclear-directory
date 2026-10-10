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
  has_many :aliases, class_name: "FacilityAlias", dependent: :destroy

  normalizes :nrc_docket, with: ->(docket) { docket.strip.presence }
  normalizes :country_code, with: ->(code) { code.strip.upcase }

  validates :name, presence: true
  validates :nrc_docket, uniqueness: true, allow_nil: true
  validates :country_code, length: { is: 2 }
  validates :capacity_mw, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true

  # What the public sees. A unit: verified, under a site that isn't rejected
  # or unpublished. A site: verified, or pending with at least one such unit
  # (#73: a site made from NRC units goes public with its first verified unit).
  def self.published
    closed_sites = where(parent_id: nil, verification_status: Verifiable::CLOSED_STATUSES).select(:id)
    units = verified.where.not(parent_id: nil).where.not(parent_id: closed_sites)
    sites = where(parent_id: nil)
    sites.verified.or(sites.pending.where(id: units.select(:parent_id))).or(units)
  end
end
