# What Directory::Lookup.pending_facts returns: a fact waiting for a human's
# decision, as plain values for the review queue.
# type:       the record type, as candidates store it in subject_type
# kind:       the FactWriter kind, to approve or edit it with
# attributes: FactWriter attribute names with their current values; links
#             also carry their ends' names (organization_name, facility_name,
#             from_organization_name, to_organization_name, parent_name)
# evidence:   Directory::EvidenceRefs
# last_event: the latest Directory::VerificationEventRef, or nil
Directory::PendingFactRef = Data.define(:type, :id, :kind, :attributes, :evidence, :created_at, :last_event)
