require "test_helper"

class RelationshipTest < ActiveSupport::TestCase
  setup do
    @from = organizations(:westinghouse)
    @to = organizations(:terrapower)
  end

  test "valid between two organizations" do
    assert Relationship.create!(from_organization: @from, to_organization: @to, relationship_type: "supplies").persisted?
  end

  test "an organization can't have a relationship with itself" do
    rel = Relationship.new(from_organization: @from, to_organization: @from, relationship_type: "supplies")
    assert_not rel.valid?
    assert_includes rel.errors[:to_organization], "can't be the same as the from organization"
  end

  test "database enforces from ≠ to" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Relationship.insert!({ from_organization_id: @from.id, to_organization_id: @from.id, relationship_type: "supplies" })
    end
  end

  test "unique per from, to and type" do
    Relationship.create!(from_organization: @from, to_organization: @to, relationship_type: "supplies")
    assert_not Relationship.new(from_organization: @from, to_organization: @to, relationship_type: "supplies").valid?
    assert Relationship.new(from_organization: @from, to_organization: @to, relationship_type: "invests_in").valid?
    assert Relationship.new(from_organization: @to, to_organization: @from, relationship_type: "supplies").valid?
  end

  test "type must be a known value" do
    rel = Relationship.new(from_organization: @from, to_organization: @to, relationship_type: "likes")
    assert_not rel.valid?
  end

  test "ended_on can't be before started_on" do
    rel = Relationship.new(from_organization: @from, to_organization: @to, relationship_type: "supplies",
      started_on: Date.new(2025, 1, 1), ended_on: Date.new(2024, 1, 1))
    assert_not rel.valid?
  end

  test "organizations see their relationships both ways" do
    rel = Relationship.create!(from_organization: @from, to_organization: @to, relationship_type: "supplies")
    assert_includes @from.outgoing_relationships, rel
    assert_includes @to.incoming_relationships, rel
  end
end
