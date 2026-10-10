# A raw claim pulled out of a source by the extract stage, before it becomes
# a fact. Once matched, subject points at the fact it became.
class Candidate < ApplicationRecord
  KINDS = %w[organization organization_alias organization_role organization_technology
    facility relationship facility_relationship].freeze

  enum :kind, KINDS.index_by(&:itself), validate: true, prefix: true
  # Prefixed because "new" would clash with Candidate.new.
  enum :status, %w[new matched merged rejected needs_review].index_by(&:itself), default: "new", validate: true,
    prefix: true

  belongs_to :source
  belongs_to :crawl_run, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :subject, presence: true, if: -> { status_matched? || status_merged? }
end
