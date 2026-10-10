# A raw claim pulled out of a source by the extract stage, before it becomes
# a fact. Once matched, subject points at the fact it became.
class Candidate < ApplicationRecord
  KINDS = %w[organization organization_alias organization_role organization_technology
    facility relationship facility_relationship].freeze

  enum :kind, KINDS.index_by(&:itself), validate: true, prefix: true
  # Prefixed because "new" would clash with Candidate.new.
  enum :status, %w[new matched merged rejected needs_review].index_by(&:itself), default: "new", validate: true,
    prefix: true

  # The verifier agent's view (#15): it recommends, a human decides.
  AI_RECOMMENDATIONS = %w[recommend_publish needs_review].freeze

  belongs_to :source
  belongs_to :crawl_run, optional: true
  belongs_to :verify_run, class_name: "CrawlRun", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :ai_recommendation, inclusion: { in: AI_RECOMMENDATIONS }, allow_nil: true
  validates :ai_confidence, numericality: { in: 0..1 }, allow_nil: true

  # Waiting for a human to approve: recommended by the agent, not yet decided.
  scope :recommended, -> { where(ai_recommendation: "recommend_publish", status: %w[new matched]) }

  # Checks the columns rather than loading the record, so the data quality
  # module can set the link without touching directory models.
  validates :subject_type, :subject_id, presence: true, if: -> { status_matched? || status_merged? }
end
