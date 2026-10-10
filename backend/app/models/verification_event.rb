# One change of a fact's verification: who changed it from what to what,
# when, and why. Append-only; written by Directory::FactWriter. Read through
# Directory::Lookup.verification_history.
class VerificationEvent < ApplicationRecord
  belongs_to :subject, polymorphic: true

  validates :to_status, inclusion: { in: Verifiable::VERIFICATION_STATUSES }
  validates :from_status, inclusion: { in: Verifiable::VERIFICATION_STATUSES }, allow_nil: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "verification events can't be changed" }
  before_destroy { throw :abort unless destroyed_by_association }
end
