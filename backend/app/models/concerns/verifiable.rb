# Shared by every fact table (organizations, facilities, their join tables
# and both relationship tables). A fact starts as pending and only verified
# facts are shown publicly.
module Verifiable
  extend ActiveSupport::Concern

  VERIFICATION_STATUSES = %w[pending verified rejected].freeze

  included do
    enum :verification_status, VERIFICATION_STATUSES.index_by(&:itself), default: "pending", validate: true

    has_many :evidence, as: :subject, dependent: :destroy

    validates :confidence, numericality: { in: 0..1 }, allow_nil: true
  end

  # by: who made the call, e.g. "human:tosin" or "agent:verifier/<model>"
  def verify!(by:)
    update!(verification_status: "verified", verified_at: Time.current, verified_by: by)
    recompute_confidence!
  end

  def human_verified?
    verified? && verified_by.to_s.start_with?("human:")
  end

  # Called whenever this fact's evidence changes. The rule itself lives in
  # Evidence.combined_confidence.
  def recompute_confidence!
    update_column(:confidence, Evidence.combined_confidence(evidence.includes(:source), human_verified: human_verified?))
  end

  def reject!(by:)
    update!(verification_status: "rejected", verified_at: Time.current, verified_by: by)
    recompute_confidence!
  end
end
