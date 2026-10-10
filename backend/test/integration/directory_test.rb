require "test_helper"
require_relative "../support/directory_builders"

class DirectoryTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  setup do
    vendor = role("reactor_vendor")
    @kairos = company("Kairos Power", city: "Alameda", state: "CA", roles: [ vendor ],
      description: "Develops salt-cooled reactors.")
    company("Oklo", roles: [ vendor ])
    company("Pending Reactors", roles: [ vendor ], verified: false)
    plant("Plant Vogtle", state: "GA", facility_type: "power_reactor", status: "operating")
  end

  test "a category lists its verified companies" do
    get companies_path(category: "reactor-developers")

    assert_response :success
    assert_select "title", "Reactor developers · Nuclear Directory"
    assert_select "h1", /Reactor developers/
    assert_select "h1 .nd-num", "2 companies"
    assert_select "a.nd-pill[aria-current=page]", /Reactor developers/
    assert_select "a.nd-listrow[href='/companies/kairos-power']", /Develops salt-cooled reactors./
    assert_select "a.nd-listrow", text: /Pending Reactors/, count: 0
  end

  test "a company without a description or HQ still lists" do
    get companies_path(category: "reactor-developers")

    assert_select "a.nd-listrow[href='/companies/oklo'] .nd-listrow__desc", count: 0
  end

  test "search results group companies and power plants" do
    company("Vogtle Services Co", roles: [ role("reactor_services") ])
    get companies_path(q: "vogtle")

    assert_select "h1", /Results for “vogtle”/
    assert_select "#companies-heading", "Companies"
    assert_select "#plants-heading", "Plants and sites"
    assert_select "a.nd-listrow[href='/plants/plant-vogtle']", /Power plant · Operating/
  end

  test "the search field keeps the query" do
    get companies_path(q: "kairos")

    assert_select ".nd-sitebar input[name=q][value=kairos]"
    assert_select "form.nd-filters input[type=hidden][name=q][value=kairos]"
  end

  test "no results offers to clear the search" do
    get companies_path(category: "reactor-developers", q: "molten salt pump")

    assert_select ".nd-notice", /No results for “molten salt pump” in Reactor developers./
    assert_select ".nd-notice a[href=?]", "/companies?category=reactor-developers", text: "Clear search"
  end

  test "filters that match nothing offer to clear them" do
    get companies_path(category: "reactor-developers", state: "WY")

    assert_select ".nd-notice", /Nothing matches these filters./
    assert_select ".nd-notice a", "Clear filters"
  end

  test "power plants have no technology filter" do
    get companies_path(category: "plants")

    assert_select "select[name=technology]", count: 0
    assert_select "select[name=state]"
    assert_select "h1 .nd-num", "1 plant"
  end

  test "filters work without JavaScript" do
    get companies_path(category: "reactor-developers")

    assert_select "form.nd-filters[action='/companies'][method=get]"
    assert_select "form.nd-filters input[type=hidden][name=category][value=reactor-developers]"
    assert_select "form.nd-filters button[type=submit]", "Apply"
  end
end
