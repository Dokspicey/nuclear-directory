require "test_helper"

class Directory::LookupTest < ActiveSupport::TestCase
  test "finds an organization by name, ignoring punctuation and company suffixes" do
    ref = Directory::Lookup.organization(name: "TerraPower, LLC")
    assert_equal organizations(:terrapower).id, ref.id
    assert_equal "terrapower", ref.slug
  end

  test "finds an organization by alias" do
    organizations(:terrapower).aliases.create!(alias: "US SFR Owner")
    assert_equal organizations(:terrapower).id, Directory::Lookup.organization(name: "US SFR Owner LLC").id
  end

  test "finds an organization by domain or URL" do
    assert_equal organizations(:terrapower).id, Directory::Lookup.organization(domain: "terrapower.com").id
    assert_equal organizations(:terrapower).id, Directory::Lookup.organization(domain: "https://www.TerraPower.com/news").id
  end

  test "finds an organization by id and slug" do
    org = organizations(:westinghouse)
    assert_equal org.id, Directory::Lookup.organization(id: org.id).id
    assert_equal org.id, Directory::Lookup.organization(slug: "westinghouse").id
  end

  test "returns nil when nothing matches" do
    assert_nil Directory::Lookup.organization(name: "Nobody Nuclear")
    assert_nil Directory::Lookup.facility(nrc_docket: "99999999")
  end

  test "returns plain values, not models" do
    ref = Directory::Lookup.organization(slug: "terrapower")
    assert_kind_of Directory::OrganizationRef, ref
    assert_not_kind_of ActiveRecord::Base, ref
    assert_equal "pending", ref.verification_status
    assert ref.frozen?
  end

  test "finds a facility by name, case-insensitively, and by docket" do
    site = facilities(:vogtle)
    assert_equal site.id, Directory::Lookup.facility(name: " vogtle electric generating plant ").id

    site.update!(nrc_docket: "05000424")
    ref = Directory::Lookup.facility(nrc_docket: "05000424")
    assert_kind_of Directory::FacilityRef, ref
    assert_equal site.id, ref.id
  end

  test "finds similar facilities, ignoring unit numbers and generic words" do
    lasalle = Facility.create!(name: "La Salle County Station")
    Facility.create!(name: "La Crosse Boiling Water Reactor")

    assert_equal [ facilities(:vogtle).id ], Directory::Lookup.similar_facilities("Vogtle 3").map(&:id)
    assert_equal [ lasalle.id ], Directory::Lookup.similar_facilities("LaSalle 1").map(&:id)
    assert_empty Directory::Lookup.similar_facilities("Nuclear Generating Station 2"), "only generic words"
    assert_empty Directory::Lookup.similar_facilities("Clinch River")
  end

  test "only the leading distinctive word counts, since later words are often places" do
    Facility.create!(name: "Lost Creek ISR uranium facility")
    Facility.create!(name: "Crane Clean Energy Center (Three Mile Island Unit 1)")

    assert_empty Directory::Lookup.similar_facilities("Hope Creek 1")
    assert_empty Directory::Lookup.similar_facilities("Nine Mile Point 1")
  end

  test "finds similar organizations through any alias" do
    organizations(:westinghouse).aliases.create!(alias: "Westinghouse")

    similar = Directory::Lookup.similar_organizations("Westinghouse Government Services LLC")
    assert_equal [ organizations(:westinghouse).id ], similar.map(&:id)
    assert_kind_of Directory::OrganizationRef, similar.first
    assert_empty Directory::Lookup.similar_organizations("Entergy Nuclear Operations, Inc.")
  end

  test "a malformed or blank key matches nothing, not every record missing that field" do
    Organization.create!(name: "No Domain Co")
    assert_nil Directory::Lookup.organization(domain: "https://[")
    assert_nil Directory::Lookup.organization(domain: "   ")
    assert_nil Directory::Lookup.organization(name: "Inc.")

    assert_nil Directory::Lookup.facility(nrc_docket: " "), "the Vogtle fixture has no docket"
  end

  test "a link's decision reads as a plain fact, in the words visitors use" do
    org = organizations(:terrapower)
    role = OrganizationRole.create!(organization: org, role: Role.create!(key: "reactor_vendor", name: "Reactor vendor"))
    deal = Relationship.create!(from_organization: organizations(:westinghouse), to_organization: org, relationship_type: "invests_in")

    assert_equal "the fact “TerraPower is a reactor developer”", Directory::Lookup.fact_state(type: "OrganizationRole", id: role.id).name
    assert_equal "the fact “#{organizations(:westinghouse).name} invests in TerraPower”",
      Directory::Lookup.fact_state(type: "Relationship", id: deal.id).name
    assert_equal "TerraPower", Directory::Lookup.fact_state(type: "Organization", id: org.id).name

    operator = OrganizationRole.create!(organization: org, role: Role.create!(key: "operator", name: "Operator"))
    smr = OrganizationTechnology.create!(organization: org, technology: Technology.create!(key: "smr", name: "SMR"))
    assert_equal "the fact “TerraPower is an operator”", Directory::Lookup.fact_state(type: "OrganizationRole", id: operator.id).name
    assert_equal "the fact “TerraPower works on SMR”", Directory::Lookup.fact_state(type: "OrganizationTechnology", id: smr.id).name
  end

  test "needs exactly one way to look up" do
    assert_raises(ArgumentError) { Directory::Lookup.organization }
    assert_raises(ArgumentError) { Directory::Lookup.organization(name: "TerraPower", domain: "terrapower.com") }
  end
end
