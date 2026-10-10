require "test_helper"

class FacilityTest < ActiveSupport::TestCase
  setup { @site = facilities(:vogtle) }

  test "a unit belongs to its site" do
    unit = Facility.create!(name: "Vogtle Unit 3", parent: @site, facility_type: "power_reactor", status: "operating")
    assert_equal "vogtle-unit-3", unit.slug
    assert_includes @site.children, unit
  end

  test "nrc docket is unique when present" do
    Facility.create!(name: "Unit A", facility_type: "power_reactor", status: "operating", nrc_docket: "05000424")
    dup = Facility.new(name: "Unit B", facility_type: "power_reactor", status: "operating", nrc_docket: "05000424")
    assert_not dup.valid?

    Facility.create!(name: "No docket 1", facility_type: "other", status: "planned", nrc_docket: " ")
    assert Facility.create!(name: "No docket 2", facility_type: "other", status: "planned").persisted?
  end

  test "type and status must be known values" do
    assert_not Facility.new(name: "X", facility_type: "spaceship", status: "operating").valid?
    assert_not Facility.new(name: "X", facility_type: "other", status: "vibing").valid?
  end

  test "an organization can own a share of a facility" do
    org = organizations(:westinghouse)
    link = FacilityRelationship.create!(organization: org, facility: @site, relationship_type: "owns", ownership_pct: 45.7)
    assert_includes org.facilities, @site
    assert_not FacilityRelationship.new(organization: org, facility: @site, relationship_type: "owns").valid?
    assert link.pending?
  end

  test "ownership_pct only applies to owns" do
    link = FacilityRelationship.new(organization: organizations(:westinghouse), facility: @site,
      relationship_type: "operates", ownership_pct: 10)
    assert_not link.valid?
  end
end
