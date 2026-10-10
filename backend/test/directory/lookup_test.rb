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

  test "a plant named after its owner doesn't make the owner's name a plant name" do
    Directory::FactWriter.write(:organization, { name: "Urenco" })
    Facility.create!(name: "Urenco USA enrichment facility")

    assert_equal "acme urenco", Directory::Lookup.brand_key("Acme Urenco, LLC")
  end

  test "a plant name of four or more words is recognized at the end of a company name" do
    Facility.create!(name: "Crane Clean Energy Center (Three Mile Island Unit 1)")

    assert_equal "constellation", Directory::Lookup.brand_key("Constellation Crane Three Mile Island, LLC")
  end

  test "dotted legal suffixes are dropped like plain ones" do
    assert_equal "acme", Directory::Lookup.brand_key("Acme Holdings, L.P.")
    assert_equal "acme", Directory::Lookup.brand_key("Acme Holdings, LP")
    assert_equal "acme", Directory::Lookup.brand_key("Acme P.L.C.")
  end

  test "a leading 'the' doesn't get past the own-brand rule" do
    assert_equal "southern nuclear", Directory::Lookup.brand_key("The Southern Nuclear Operating Co.")
    assert_equal "southern", Directory::Lookup.brand_key("The Southern Company")
  end

  test "a leading 'the' is ignored everywhere the brand is worked out" do
    Directory::FactWriter.write(:organization, { name: "The Acme Company" })
    Facility.create!(name: "Acme enrichment facility")
    Facility.create!(name: "Seabrook Station")

    assert_equal [ "The Acme Company" ], Directory::Lookup.same_brand_organizations("Acme Operations LLC").map(&:name)
    assert_equal "other acme", Directory::Lookup.brand_key("Other Acme LLC"), "Acme is the owner, not a plant"
    assert_equal "NextEra Energy", Directory::Lookup.brand_name("The NextEra Energy Seabrook, LLC")
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
    assert_equal "holtec palisades", Directory::Lookup.brand_key("Holtec Palisades, LLC"),
      "one word of a longer plant name doesn't count"
    Facility.create!(name: "Palisades", nrc_docket: "05000255")
    assert_equal "holtec", Directory::Lookup.brand_key("Holtec Palisades, LLC"), "a plant named Palisades does"
  end

  test "a single ordinary word that starts a plant name isn't a plant" do
    Facility.create!(name: "Advanced Test Reactor")
    Facility.create!(name: "White Mesa Mill")

    assert_equal "acme advanced", Directory::Lookup.brand_key("Acme Advanced, LLC")
    assert_equal "acme white", Directory::Lookup.brand_key("Acme White LLC")
  end

  test "a new company is named for its brand, without the operating arm" do
    Facility.create!(name: "Seabrook Station")
    Facility.create!(name: "Point Beach")

    assert_equal "NextEra Energy", Directory::Lookup.brand_name("NextEra Energy Nuclear Seabrook, LLC")
    assert_equal "NextEra Energy", Directory::Lookup.brand_name("NextEra Energy Point Beach, LLC")
    assert_equal "Acme", Directory::Lookup.brand_name("Acme Operations Seabrook, LLC")
  end

  test "a brand the directory has takes that company's name" do
    Facility.create!(name: "Seabrook Station")
    Organization.create!(name: "NextEra Energy, Inc.").aliases.create!(alias: "NextEra Energy, Inc.")

    assert_equal "NextEra Energy, Inc.", Directory::Lookup.brand_name("NextEra Energy Nuclear Seabrook, LLC")
  end

  test "dotted initials in a brand are kept as written" do
    Facility.create!(name: "Seabrook Station")
    assert_equal "L.L. Bean", Directory::Lookup.brand_name("L.L. Bean Seabrook, LLC")
  end

  test "a trailing known plant or region is dropped from the brand" do
    Facility.create!(name: "Seabrook 1", nrc_docket: "05000443")

    assert_equal "nextera", Directory::Lookup.brand_key("NextEra Energy Seabrook, LLC")
    assert_equal "NextEra Energy", Directory::Lookup.brand_name("NextEra Energy Seabrook, LLC")
    assert_equal "Sargent & Lundy", Directory::Lookup.brand_name("Sargent & Lundy Seabrook, LLC"), "keeps its own spelling"
    assert_equal "Babcock-Wilcox", Directory::Lookup.brand_name("Babcock-Wilcox Seabrook LLC")
    assert_equal "NextEra Energy", Directory::Lookup.brand_name("NextEra Energy Seabrook, L.L.C."), "dotted LLC"
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
    fuel = OrganizationRole.create!(organization: org, role: Role.create!(key: "fuel", name: "Fuel"))
    assert_equal "the fact “TerraPower is a fuel supplier”", Directory::Lookup.fact_state(type: "OrganizationRole", id: fuel.id).name
    other = OrganizationRole.create!(organization: org, role: Role.create!(key: "isotopes", name: "Isotopes"))
    assert_equal "the fact “TerraPower has the role Isotopes”", Directory::Lookup.fact_state(type: "OrganizationRole", id: other.id).name
    assert_equal "the fact “TerraPower works on SMR”", Directory::Lookup.fact_state(type: "OrganizationTechnology", id: smr.id).name
  end

  test "needs exactly one way to look up" do
    assert_raises(ArgumentError) { Directory::Lookup.organization }
    assert_raises(ArgumentError) { Directory::Lookup.organization(name: "TerraPower", domain: "terrapower.com") }
  end
end
