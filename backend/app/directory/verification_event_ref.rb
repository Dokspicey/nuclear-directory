# What Directory::Lookup.verification_history returns for one change of a
# fact's verification: plain values, not a model.
# changed_values: attributes the same write changed, { "state" => [before, after] }.
Directory::VerificationEventRef = Data.define(:from_status, :to_status, :by, :reason, :context, :changed_values, :at) do
  def self.from(event)
    new(from_status: event.from_status, to_status: event.to_status, by: event.by, reason: event.reason,
      context: event.context, changed_values: event.changed_values, at: event.created_at)
  end
end
