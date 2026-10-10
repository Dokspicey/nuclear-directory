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

  test "brand keys drop trailing legal-entity and operating-arm words" do
    assert_equal "constellation", Directory::Lookup.brand_key("Constellation Energy Generation, LLC")
    assert_equal "southern nuclear", Directory::Lookup.brand_key("Southern Nuclear Operating Co., Inc."), "its own brand"
    assert_equal "pseg", Directory::Lookup.brand_key("PSEG Nuclear, LLC"), "other nuclear arms are their brand"
    assert_equal "ge vernova hitachi", Directory::Lookup.brand_key("GE Vernova Hitachi Nuclear Energy")
    assert_equal "energy northwest", Directory::Lookup.brand_key("Energy Northwest"), "leading words stay"
    assert_nil Directory::Lookup.brand_key("X-Energy, Inc."), "too short to trust"
  end

  test "no brand name from a key too short to trust, and rejected plants don't count" do
    Facility.create!(name: "Seabrook 1", nrc_docket: "05000443")
    assert_nil Directory::Lookup.brand_name("X-Energy Seabrook, LLC"), "reduces to 'x'"

    Facility.create!(name: "Imaginary Point 1", nrc_docket: "05000998").reject!(by: "agent:verifier/x")
    assert_equal "nextera energy imaginary point", Directory::Lookup.brand_key("NextEra Energy Imaginary Point, LLC")
    assert_nil Directory::Lookup.brand_name("NextEra Energy Imaginary Point, LLC")
  end

  test "a name made only of legal or operating words has no brand" do
    assert_nil Directory::Lookup.brand_key("Nuclear Energy LLC")
    assert_nil Directory::Lookup.brand_key("Nuclear Power, Inc.")
    assert_equal "southern nuclear", Directory::Lookup.brand_key("Southern Nuclear Operating Company"), "own brands unaffected"
  end

  test "a place word that starts a plant's name isn't a plant on its own" do
    Facility.create!(name: "North Anna Power Station")
    Facility.create!(name: "Palisades Pioneer Units 1 & 2")

    assert_equal "acme north", Directory::Lookup.brand_key("Acme North, LLC"), "North alone isn't a plant"
    assert_equal "dominion", Directory::Lookup.brand_key("Dominion Energy North Anna, LLC"), "North Anna is"
    assert_equal "holtec", Directory::Lookup.brand_key("Holtec Palisades, LLC"), "a plant's own first word still counts"
  end

  test "a trailing known plant or region is dropped from the brand" do
    Facility.create!(name: "Seabrook 1", nrc_docket: "05000443")

    assert_equal "nextera", Directory::Lookup.brand_key("NextEra Energy Seabrook, LLC")
    assert_equal "NextEra Energy", Directory::Lookup.brand_name("NextEra Energy Seabrook, LLC")
    assert_equal "duke", Directory::Lookup.brand_key("Duke Energy Carolinas, LLC")
    assert_equal "Duke Energy", Directory::Lookup.brand_name("Duke Energy Carolinas, LLC")
    assert_equal "duke", Directory::Lookup.brand_key("Duke Energy Progress, LLC"), "Progress is a legacy brand of Duke"
    assert_nil Directory::Lookup.brand_name("Constellation Energy Generation, LLC"), "no place in it: keep the full name"
    assert_equal "seabrook", Directory::Lookup.brand_key("Seabrook Holdings"), "a name that is only a place stays"
  end

  test "finds organizations of the same brand" do
    assert_equal [ organizations(:westinghouse).id ],
      Directory::Lookup.same_brand_organizations("Westinghouse Electric Company Holdings").map(&:id)
    assert_empty Directory::Lookup.same_brand_organizations("Westinghouse Government Services Division")
  end

  test "needs exactly one way to look up" do
    assert_raises(ArgumentError) { Directory::Lookup.organization }
    assert_raises(ArgumentError) { Directory::Lookup.organization(name: "TerraPower", domain: "terrapower.com") }
  end
end
