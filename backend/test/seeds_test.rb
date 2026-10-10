require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  COUNTED = %w[Organization OrganizationAlias OrganizationRole OrganizationTechnology Facility Relationship
    FacilityRelationship Source Evidence Role Technology].map { |model| "#{model}.count" }

  def load_seeds
    silence_warnings { load Rails.root.join("db/seeds.rb") }
  end

  test "seeds roles and technologies" do
    load_seeds

    assert Role.find_by!(key: "reactor_vendor").description.present?
    assert_equal Role.find_by!(key: "coolant"), Role.find_by!(key: "molten_salt").parent
    assert_equal Role.find_by!(key: "fuel"), Role.find_by!(key: "enrichment").parent
    assert_equal Technology.find_by!(key: "fission"), Technology.find_by!(key: "smr").parent
    assert_nil Technology.find_by!(key: "fusion").parent
  end

  test "loads the hand-checked organizations as verified facts with evidence" do
    load_seeds

    assert_equal 40, Organization.verified.count
    assert_equal 51, OrganizationRole.verified.count
    assert_equal 27, OrganizationTechnology.verified.count
    assert_equal 45, Relationship.verified.count
    assert_equal 24, Facility.verified.count
    assert_equal 36, FacilityRelationship.verified.count
    assert_equal [ "human:tosin" ], Relationship.distinct.pluck(:verified_by)
    assert_equal [ 1 ], OrganizationRole.distinct.pluck(:confidence)

    georgia_power = Directory::Lookup.organization(name: "Georgia Power Company")
    southern = Directory::Lookup.organization(name: "Southern Company")
    link = Relationship.find_by!(from_organization_id: georgia_power.id, to_organization_id: southern.id)
    assert link.subsidiary_of?
    assert_equal "human", link.evidence.sole.found_by
    assert_match "Georgia Power", link.evidence.sole.quote
  end

  test "is safe to re-run" do
    load_seeds
    Role.find_by!(key: "fuel").update!(name: "Edited")

    assert_no_difference(COUNTED) { load_seeds }
    assert_equal "Fuel", Role.find_by!(key: "fuel").name
  end
end
