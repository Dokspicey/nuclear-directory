# What Directory::Lookup.verification_history returns for one change of a
# fact's verification: plain values, not a model.
Directory::VerificationEventRef = Data.define(:from_status, :to_status, :by, :reason, :context, :at) do
  def self.from(event)
    new(from_status: event.from_status, to_status: event.to_status, by: event.by, reason: event.reason,
      context: event.context, at: event.created_at)
  end
end
