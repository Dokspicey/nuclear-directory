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

  test "needs exactly one way to look up" do
    assert_raises(ArgumentError) { Directory::Lookup.organization }
    assert_raises(ArgumentError) { Directory::Lookup.organization(name: "TerraPower", domain: "terrapower.com") }
  end
end
