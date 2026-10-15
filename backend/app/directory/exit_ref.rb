# What Directory::Lookup.exits returns for one fact taken out of the
# directory (#166): rejected or unpublished, by whom, when and why. Plain
# values, not a model. merged_into: { "type", "id" } when a merge took it
# out (the record it went into), else nil.
Directory::ExitRef = Data.define(:type, :id, :name, :to_status, :by, :reason, :merged_into, :at)
