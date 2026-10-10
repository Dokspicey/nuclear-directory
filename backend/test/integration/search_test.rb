require "test_helper"
require_relative "../support/directory_builders"

class SearchTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  setup do
    vendor = role("reactor_vendor")
    company("Kairos Power", city: "Alameda", state: "CA", roles: [ vendor ])
    company("Kairos Ghost", roles: [ vendor ], verified: false)
    plant("Kairos Hermes", facility_type: "research_reactor", city: "Oak Ridge", state: "TN")
  end

  test "instant results come back grouped in a Turbo Frame, without the layout" do
    get search_path(q: "kairos")

    assert_response :success
    assert_not_includes response.body, "<html"
    assert_select "turbo-frame#instant-results[target=_top]"
    assert_select "#instant-companies", "Companies"
    assert_select ".nd-instant__row[href='/companies/kairos-power']", /Kairos Power.*Reactor developer · Alameda, CA/m
    assert_select "#instant-plants", "Plants and sites"
    assert_select ".nd-instant__row[href='/plants/kairos-hermes']", /Test reactor · Oak Ridge, TN/
    assert_select ".nd-instant[data-instant-search-count='2']"
    assert_select ".nd-instant__all[href=?]", "/companies?q=kairos", text: /All results for “kairos”/
  end

  test "only verified records appear" do
    get search_path(q: "ghost")

    assert_select ".nd-instant__row", count: 0
    assert_select ".nd-instant__empty", "No results for “ghost”"
  end

  test "a query shorter than two characters returns an empty frame" do
    get search_path(q: "k")

    assert_select "turbo-frame#instant-results"
    assert_select ".nd-instant", count: 0
  end

  test "results are capped so the list stays short" do
    vendor = Role.find_by!(key: "reactor_vendor")
    8.times { |i| company("Kairos Clone #{i}", roles: [ vendor ]) }
    get search_path(q: "kairos")

    assert_select "ul[aria-labelledby=instant-companies] li", SearchController::COMPANY_LIMIT
  end
end
