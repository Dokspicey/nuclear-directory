# What Directory::Lookup.fact_state returns: any fact's current decision, as
# plain values. name is the record's name, or a short label for a link
# ("TerraPower owns Plant Vogtle").
Directory::FactStateRef = Data.define(:type, :id, :name, :verification_status, :verified_by, :verified_at)
