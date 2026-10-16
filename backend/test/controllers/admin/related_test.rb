require "test_helper"

# A Record's related items (#201, Design's spec on #166): a plant's units
# and companies, a company's deals and plants, each with its status, the
# claims waiting on it and a menu of actions that come back to its row.
class Admin::RelatedTest < ActionDispatch::IntegrationTest
  VERIFIED = { verification_status: "verified", verified_by: "human:tosin" }.freeze

  setup do
    @web = Source.create!(url: "https://www.example.com/related", source_kind: "web_page", domain: "example.com")
    sign_in_as users(:admin)
    @site = sourced(Facility.create!(name: "Plant Vogtle", facility_type: "power_reactor", status: "operating", state: "GA", **VERIFIED))
    @u1 = sourced(Facility.create!(name: "Vogtle 1", parent: @site, reactor_type: "PWR", capacity_mw: 1150, **VERIFIED))
    @u2 = sourced(Facility.create!(name: "Vogtle 2", parent: @site, reactor_type: "PWR", capacity_mw: 1152, **VERIFIED))
    @georgia = sourced(Organization.create!(name: "Georgia Power", **VERIFIED))
    @southern = sourced(Organization.create!(name: "Southern Nuclear", **VERIFIED))
    @owns = sourced(FacilityRelationship.create!(organization: @georgia, facility: @site, relationship_type: "owns", ownership_pct: 45.7, **VERIFIED))
    @operates = sourced(FacilityRelationship.create!(organization: @southern, facility: @u1, relationship_type: "operates", **VERIFIED))
  end

  def sourced(fact) = fact.tap { Evidence.create!(subject: fact, source: @web, quote: "q", found_by: "human") }
  def record(fact, **params) = admin_record_path(type: fact.class.name, id: fact.id, **params)
  def rows(section) = css_select("##{section} tbody tr").map { |tr| tr.css("td").first.text.squish }

  test "a plant shows its units, then its companies, owners first with their share" do
    get record(@site)

    assert_equal [ "Vogtle 1", "Vogtle 2" ], rows("units")
    assert_select "#units tbody tr:first-child", /PWR.*1,150 MW.*Live/m
    assert_equal [ "Georgia Power", "Southern Nuclear" ], rows("companies")
    assert_select "#companies tbody tr:first-child td", /owns\s+· 45.7%/
    assert_select "#companies tbody tr:last-child td", /operates\s+· Vogtle 1/
    assert_select "#companies a[href=?]", record(@georgia, from: "record", section: "companies", row: "FacilityRelationship-#{@owns.id}", back: record(@site)), "Georgia Power"
  end

  test "a company shows its deals and links, then its plants" do
    google = sourced(Organization.create!(name: "Google", **VERIFIED))
    sourced(Relationship.create!(from_organization: google, to_organization: @georgia, relationship_type: "offtake_with", **VERIFIED))

    get record(@georgia)

    assert_select "section.nd-related h2", text: /Deals and links|Plants and sites/, count: 2
    assert_equal [ "Google" ], rows("deals")
    assert_select "#deals td", /offtakes from Georgia Power\s+· Power deal/
    assert_equal [ "Plant Vogtle" ], rows("plants")
    assert_select "#plants td", /owns\s+· Power plant · Operating · GA · 45.7%/
  end

  test "status and claims waiting; removed rows show on request" do
    Candidate.create!(source: @web, kind: "facility", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: @u2.id, payload: { "name" => "Vogtle 2" })
    @u1.unpublish!(by: "human:tosin", reason: "Test")

    get record(@site)

    assert_equal [ "Vogtle 2" ], rows("units")
    assert_select "#units tbody tr td", /Live\s+· 1 waiting/
    assert_select "#units a", "Show removed (1)"

    get record(@site, removed: "units")
    assert_equal [ "Vogtle 1", "Vogtle 2" ], rows("units")
    assert_select "#item-Facility-#{@u1.id} td", /Removed/
    assert_select "#item-Facility-#{@u1.id} button", "Put back"
  end

  test "Take off from a row needs a reason, then comes back to the Record at that row" do
    here = "#{record(@site)}#item-FacilityRelationship-#{@owns.id}"

    get record(@site)
    assert_select "#item-FacilityRelationship-#{@owns.id} details.nd-rowmenu summary[aria-label=?]", "Actions for Georgia Power"
    assert_select "#item-FacilityRelationship-#{@owns.id} input[name=reason][required]"

    post admin_fact_unpublish_path(type: "FacilityRelationship", id: @owns.id), params: { reason: "", next: here }
    assert @owns.reload.verified?

    post admin_fact_unpublish_path(type: "FacilityRelationship", id: @owns.id), params: { reason: "Sold its share", next: here }
    assert_response :see_other
    assert_redirected_to here
    assert @owns.reload.unpublished?
    assert_match(/\ATaken off: /, flash[:notice])
  end

  test "Edit from a row edits the unit and comes back to its row; a link's ends can't be edited" do
    here = "#{record(@site)}#item-Facility-#{@u1.id}"

    get admin_fact_edit_path(type: "Facility", id: @u1.id, back: record(@site), next: here)
    assert_select "input[name=?]", "values[capacity_mw]"
    patch admin_fact_path(type: "Facility", id: @u1.id), params: { values: { capacity_mw: "1160" }, next: here }
    assert_redirected_to here
    assert_equal 1160, @u1.reload.capacity_mw

    get admin_fact_edit_path(type: "FacilityRelationship", id: @owns.id)
    assert_select "input[name=?]", "values[ownership_pct]"
    assert_select "input[name=?]", "values[organization_id]", 0
    assert_select "input[name=?]", "values[relationship_type]", 0
  end

  test "Decide goes through the item's waiting claims, then back to the Record at its row" do
    claim = ->(state) { Candidate.create!(source: @web, kind: "facility", quote: "q", status: "needs_review", notes: "unsure", subject_type: "Facility", subject_id: @u2.id, payload: { "name" => "Vogtle 2", "state" => state }) }
    first, second = claim.("GA"), claim.("AL")
    here = "#{record(@site)}#item-Facility-#{@u2.id}"
    context = { claims: 1, from: "record", section: "units", row: "Facility-#{@u2.id}", back: here }

    get record(@site)
    assert_select "#item-Facility-#{@u2.id} .nd-rowmenu a[href=?]", admin_fact_path(type: "Facility", id: @u2.id, claim: first.id, **context), "Decide"

    get admin_fact_path(type: "Facility", id: @u2.id, claim: first.id, **context)
    assert_select ".nd-itemnav", /1 of 2 waiting/
    following = admin_fact_path(type: "Facility", id: @u2.id, **context.except(:claims), claims: 1, claim: second.id)
    assert_select ".nd-itemnav a[rel=next][href=?]", following

    post reject_admin_candidates_path, params: { candidate_id: first.id, back: here, next: following }
    assert_redirected_to following
    post reject_admin_candidates_path, params: { candidate_id: second.id, back: here }
    assert_redirected_to here
  end

  test "Edit from a row: Live / the Record / the item / Edit" do
    get admin_fact_edit_path(type: "Facility", id: @u1.id, from: "record", section: "units", row: "Facility-#{@u1.id}", back: record(@site), next: "#{record(@site)}#item-Facility-#{@u1.id}")

    assert_equal [ "Live", "Plant Vogtle", "Vogtle 1", "Edit" ], css_select(".nd-crumbs li").map { |li| li.text.squish }
  end

  test "a related row's page: Live / the Record / it, with Previous and Next through its section" do
    live = admin_live_path(tab: "plants")
    parent = record(@site, back: live)
    context = ->(unit) { { from: "record", section: "units", row: "Facility-#{unit.id}", back: parent } }

    get admin_fact_path(type: "Facility", id: @u1.id, **context.(@u1))

    assert_select ".nd-crumbs li a[href=?]", live, "Live"
    assert_select ".nd-crumbs li a[href=?]", parent, "Plant Vogtle"
    assert_select ".nd-crumbs li[aria-current]", "Vogtle 1"
    assert_select ".nd-itemnav", /1 of 2/
    assert_select ".nd-itemnav a[rel=next][href=?]", admin_fact_path(type: "Facility", id: @u2.id, **context.(@u2))

    get record(@georgia, from: "record", section: "companies", row: "FacilityRelationship-#{@owns.id}", back: parent)
    assert_select ".nd-crumbs li a[href=?]", parent, "Plant Vogtle"
    assert_select ".nd-itemnav", /1 of 2/
  end
end
