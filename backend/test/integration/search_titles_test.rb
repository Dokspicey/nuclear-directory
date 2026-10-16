require "test_helper"
require_relative "../support/directory_builders"

# Titles and descriptions in the words people search with, built only from
# published facts (#290 categories, #291 plants, #292 companies). URLs don't
# change.
class SearchTitlesTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  def description = css_select("meta[name='description']").first["content"]
  def og_description = css_select("meta[property='og:description']").first["content"]

  test "every category has a search title and a counted description that doesn't talk about sourcing" do
    Category.all.each do |category|
      assert category.title.present?, category.key
      assert_operator category.title.length, :<=, 60, category.key
      assert_match(/\A11 /, category.description(11), category.key)
      assert_no_match(/source/i, category.description(11), category.key)
      assert_operator category.description(11).length, :<=, 160, category.key
    end
    assert_equal "Fusion energy companies in the US.", Category.find("fusion").description(1)
  end

  test "a category page uses its search title and its count; the heading stays short" do
    fusion = technology("fusion", "Fusion")
    %w[Helion TAE].each { |name| cite!(company(name, techs: [ fusion ])) }

    get companies_path(category: "fusion")

    assert_select "title", "Fusion energy companies in the US · Nuclear Directory"
    assert_select "h1", /Fusion/
    assert_equal "2 fusion energy companies in the US.", description
    assert_equal description, og_description
  end

  test "a company with no one-line description is described by its plants, never the generic line (#247)" do
    utility = cite!(company("Alabama Power", city: "Birmingham", state: "AL", roles: [ role("utility") ]))
    %w[Farley Hatch Vogtle].each { |name| cite!(link(utility, "owns", cite!(plant(name)))) }
    cite!(link(utility, "operates", Facility.find_by!(name: "Farley")))

    get company_path(slug: utility.slug)

    assert_select "title", "Alabama Power: utility, plants · Nuclear Directory"
    assert_equal "Alabama Power: Utility in Birmingham, AL. Owns Farley and 2 other plants. Operates Farley.", description
    assert_equal description, og_description
    assert_no_match(/Plants, sites and deals/, description)
  end

  test "a long description is cut at a word under 160 characters, and the legal name is added when it fits" do
    long = cite!(company("Holtec", description: "Designs and builds spent fuel storage casks and the SMR-300 small modular reactor, " \
      "and decommissions shut-down plants across the United States and abroad.", legal_name: "Holtec International"))
    short = cite!(company("GNF-A", description: "Makes nuclear fuel.", legal_name: "Global Nuclear Fuel-Americas, LLC"))

    get company_path(slug: long.slug)
    assert_operator description.length, :<=, 160
    assert_match(/\AHoltec: Designs and builds/, description)

    get company_path(slug: short.slug)
    assert_equal "GNF-A: Makes nuclear fuel. Legal name: Global Nuclear Fuel-Americas, LLC.", description
  end

  test "a fusion developer with investors says so in its title and description" do
    fusion = technology("fusion", "Fusion")
    helion = cite!(company("Helion Energy", roles: [ role("reactor_vendor") ], techs: [ fusion ], description: "Develops fusion power plants."))
    cite!(link(cite!(company("Lightspeed")), "invests_in", helion))

    get company_path(slug: helion.slug)

    assert_select "title", "Helion Energy: fusion developer, investors and deals · Nuclear Directory"
    assert_equal "Helion Energy: Develops fusion power plants. Investors include Lightspeed.", description
  end

  test "a long company name drops what the page holds before going over 60 characters" do
    name = "Northern States Power Company Minnesota Generation"
    cite!(company(name, roles: [ role("utility") ])).then { |org| cite!(link(org, "owns", cite!(plant("Prairie Island")))) }

    get company_path(slug: Organization.find_by!(name:).slug)

    assert_select "title", "#{name}: utility · Nuclear Directory"
  end

  test "a plant's title names its town and state, and owners and operator only when they're published (#291)" do
    owned = cite!(plant("Arkansas Nuclear One", facility_type: "power_reactor", status: "operating", city: "Russellville", state: "AR"))
    cite!(link(cite!(company("Entergy Arkansas")), "owns", owned))
    bare = cite!(plant("Lone Site", facility_type: "uranium_mine", city: "Crownpoint", state: "NM"))

    get plant_path(slug: owned.slug)
    assert_select "title", "Arkansas Nuclear One, Russellville, AR: owners · Nuclear Directory"
    assert_match(/in Russellville, Arkansas\./, description)

    get plant_path(slug: bare.slug)
    assert_select "title", "Lone Site, Crownpoint, NM · Nuclear Directory"
  end
end
