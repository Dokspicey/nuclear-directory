require "test_helper"

# The review queue's view of facts waiting for a human (Backend's review API).
class Directory::PendingFactsTest < ActiveSupport::TestCase
  def pending(kind, **) = Directory::Lookup.pending_facts(kind:, **)

  setup do
    @source = sources(:nrc)
    @org = organizations(:terrapower)
    @plant = facilities(:vogtle)
    @link = Directory::FactWriter.write(:facility_relationship,
      { organization_id: @org.id, facility_id: @plant.id, relationship_type: "owns", ownership_pct: 40 },
      evidence: [ { source_id: @source.id, quote: "TerraPower owns 40%.", found_by: "human", confidence: 0.8 } ])
  end

  test "a pending link comes with its values, its ends' names and its evidence" do
    fact = pending("facility_relationship").sole

    assert_kind_of Directory::PendingFactRef, fact
    assert_equal [ "FacilityRelationship", @link.id, "facility_relationship" ], [ fact.type, fact.id, fact.kind ]
    assert_equal({ organization_id: @org.id, facility_id: @plant.id, relationship_type: "owns",
      organization_name: @org.name, facility_name: @plant.name },
      fact.attributes.slice(:organization_id, :facility_id, :relationship_type, :organization_name, :facility_name))
    assert_equal 40, fact.attributes[:ownership_pct]
    assert_equal [ [ @source.id, "TerraPower owns 40%.", "human", 0.8 ] ],
      fact.evidence.map { |e| [ e.source_id, e.quote, e.found_by, e.confidence ] }
    assert_nil fact.last_event
  end

  test "only pending facts: never verified, rejected or unpublished ones" do
    FacilityRelationship.find(@link.id).reject!(by: "human:tosin")

    assert_empty pending("facility_relationship")
  end

  test "the latest event says why a fact is waiting" do
    record = FacilityRelationship.find(@link.id)
    record.verify!(by: "human:tosin")
    Directory::FactWriter.write(:facility_relationship, { id: record.id },
      verification: { status: "pending", by: "human:tosin", reason: "The quote doesn't state ownership directly" })

    assert_equal [ "verified", "pending", "The quote doesn't state ownership directly" ],
      pending("facility_relationship").sole.last_event.to_h.values_at(:from_status, :to_status, :reason)
  end

  test "pages oldest first by id" do
    other = Facility.create!(name: "Hope Creek")
    second = Directory::FactWriter.write(:facility_relationship,
      { organization_id: @org.id, facility_id: other.id, relationship_type: "operates" })

    assert_equal [ @link.id ], pending("facility_relationship", limit: 1).map(&:id)
    assert_equal [ second.id ], pending("facility_relationship", after_id: @link.id).map(&:id)
  end

  test "roles are their key, and each kind names what it links" do
    Role.create!(key: "reactor_vendor", name: "Reactor vendor")
    Directory::FactWriter.write(:organization_role, { organization_id: @org.id, role: "reactor_vendor" })
    Directory::FactWriter.write(:relationship,
      { from_organization_id: organizations(:westinghouse).id, to_organization_id: @org.id, relationship_type: "supplies" })

    assert_equal [ "reactor_vendor", @org.name ], pending("organization_role").sole.attributes.values_at(:role, :organization_name)
    assert_equal [ organizations(:westinghouse).name, @org.name ],
      pending("relationship").sole.attributes.values_at(:from_organization_name, :to_organization_name)
    assert pending("organization").all? { |fact| fact.attributes.key?(:hq_state) }
  end

  test "only fact kinds" do
    assert_raises(ArgumentError) { pending("candidate") }
  end
end
