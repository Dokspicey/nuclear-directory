require "test_helper"

# What public pages read: verified facts whose companies and plants are
# published too, so unpublishing a company or plant hides its facts.
class Directory::PublishedTest < ActiveSupport::TestCase
  setup do
    @company = organizations(:terrapower).tap { |o| o.verify!(by: "human:tosin") }
    @partner = organizations(:westinghouse).tap { |o| o.verify!(by: "human:tosin") }
    @site = facilities(:vogtle).tap { |f| f.verify!(by: "human:tosin") }
    @unit = Facility.create!(name: "Vogtle 3", parent: @site).tap { |f| f.verify!(by: "human:tosin") }
    @role = OrganizationRole.create!(organization: @company, role: Role.create!(key: "reactor_vendor", name: "Reactor vendor"))
    @role.verify!(by: "human:tosin")
    @tech = OrganizationTechnology.create!(organization: @company, technology: Technology.create!(key: "smr", name: "SMR"))
    @tech.verify!(by: "human:tosin")
    @link = Relationship.create!(from_organization: @partner, to_organization: @company, relationship_type: "supplies")
    @link.verify!(by: "human:tosin")
    @owns = FacilityRelationship.create!(organization: @company, facility: @unit, relationship_type: "owns")
    @owns.verify!(by: "human:tosin")
  end

  test "everything verified is published" do
    assert_includes OrganizationRole.published, @role
    assert_includes OrganizationTechnology.published, @tech
    assert_includes Relationship.published, @link
    assert_includes FacilityRelationship.published, @owns
    assert_includes Facility.published, @unit
  end

  test "unpublishing a company hides its roles, relationships and plant links, but deletes nothing" do
    @company.unpublish!(by: "human:tosin", reason: "under review")

    assert_not_includes Organization.published, @company
    assert_not_includes OrganizationRole.published, @role
    assert_not_includes OrganizationTechnology.published, @tech
    assert_not_includes Relationship.published, @link
    assert_not_includes FacilityRelationship.published, @owns
    assert @role.reload.verified?, "the facts themselves keep their own decision"
    assert [ @role, @link, @owns ].all? { |fact| fact.class.exists?(fact.id) }, "nothing is deleted"
  end

  test "unpublishing a plant's site hides its units and their links" do
    @site.unpublish!(by: "human:tosin")

    assert_not_includes Facility.published, @unit
    assert_not_includes FacilityRelationship.published, @owns
  end

  test "republishing brings them back" do
    @company.unpublish!(by: "human:tosin")
    @company.verify!(by: "human:tosin")

    assert_includes OrganizationRole.published, @role
    assert_includes OrganizationTechnology.published, @tech
  end
end
