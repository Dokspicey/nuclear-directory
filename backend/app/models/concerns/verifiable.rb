# Shared by every fact table (organizations, facilities, their join tables
# and both relationship tables). A fact starts as pending and only verified
# facts are shown publicly.
module Verifiable
  extend ActiveSupport::Concern

  VERIFICATION_STATUSES = %w[pending verified rejected].freeze

  included do
    enum :verification_status, VERIFICATION_STATUSES.index_by(&:itself), default: "pending", validate: true

    validates :confidence, numericality: { in: 0..1 }, allow_nil: true
  end

  # by: who made the call, e.g. "human:tosin" or "agent:verifier/<model>"
  def verify!(by:)
    update!(verification_status: "verified", verified_at: Time.current, verified_by: by)
  end

  def reject!(by:)
    update!(verification_status: "rejected", verified_at: Time.current, verified_by: by)
  end
end
