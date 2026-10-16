require "test_helper"

# Live and Record (#201 part 2): every record with Data Quality's tags,
# chips that narrow the list and count what they'd show, and a company's or
# plant's Record with its public view and actions.
class Admin::LiveTest < ActionDispatch::IntegrationTest
  VERIFIED = { verification_status: "verified", verified_by: "human:tosin" }.freeze

  setup do
    @web = Source.create!(url: "https://www.example.com/live", source_kind: "web_page", domain: "example.com")
    sign_in_as users(:admin)
  end

  def company(name, **attributes) = Organization.create!(name:, **VERIFIED, **attributes).tap { |o| Evidence.create!(subject: o, source: @web, quote: name, found_by: "human") }
  def names = css_select(".nd-live__table tbody td:first-child a").map(&:text)

  test "Live is in the nav with its count; it lists live records by default, newest change first" do
    old = travel_to(2.days.ago) { company("Alpha Live Co") }
    fresh = company("Beta Live Co")
    Organization.create!(name: "Pending Co")

    get admin_live_path(tab: "companies", q: "Live Co")

    assert_select ".nd-shell__nav a[aria-current=page]", /Live\s+\d+/
    assert_equal [ fresh.name, old.name ], names
    assert_select ".nd-fchip[aria-current=true]", /Live\s+2/
  end

  test "chips narrow the list: OR within a group, AND across groups, each with its count" do
    one = company("One Source Co")
    both = company("Both Co")
    Evidence.create!(subject: both, source: Source.create!(url: "https://www.nrc.gov/x", source_kind: "nrc_reactor_list", domain: "nrc.gov"), quote: "x", found_by: "crawler")
    linked = company("Linked Co")
    FacilityRelationship.create!(organization: linked, facility: Facility.create!(name: "Some Plant", **VERIFIED), relationship_type: "owns", **VERIFIED)

    get admin_live_path(tab: "companies", q: " Co", source: "multi-source")
    assert_includes names, both.name
    assert_not_includes names, one.name

    get admin_live_path(tab: "companies", q: " Co", source: "multi-source,hand-research")
    assert_includes names, one.name, "OR within Source"

    get admin_live_path(tab: "companies", q: " Co", source: "hand-research", gaps: "no-links")
    assert_not_includes names, linked.name, "AND across groups"
    assert_includes names, one.name
    no_links = css_select("a.nd-fchip").find { |chip| chip.text.include?("No links") }
    assert_no_match(/gaps=/, no_links["href"], "the chosen chip drops itself")
    assert_select "a", text: "Clear all"
  end

  test "gap and flag counts follow the Status filter: by default, only what visitors see (Data Quality, #283)" do
    company("Seen Co")
    company("Gone Lonely Co").unpublish!(by: "human:tosin", reason: "Test")
    shown = Directory::Checks.find("no-category").ids(Organization) & Organization.published.ids

    get admin_live_path(tab: "companies")
    assert_select "a.nd-fchip", /No category\s+#{shown.size}\b/

    get admin_live_path(tab: "companies", status: "unpublished")
    assert_select "a.nd-fchip", /No category\s+1\b/
    assert_select ".nd-live__foot", /Showing 1 company\b/
  end

  test "No owner counts operating power plants only, not mines or enrichment plants" do
    plant = Facility.create!(name: "Ownerless Power Plant", facility_type: "power_reactor", status: "operating", **VERIFIED)
    mine = Facility.create!(name: "Ownerless Mine", facility_type: "uranium_mine", status: "operating", **VERIFIED)

    ids = Directory::Checks.find("no-owner").ids(Facility)

    assert_includes ids, plant.id
    assert_not_includes ids, mine.id
  end

  test "a status chip replaces the status; Clear all goes back to Live" do
    company("Gone Co").unpublish!(by: "human:tosin", reason: "Test")

    get admin_live_path(tab: "companies", status: "unpublished")

    assert_includes names, "Gone Co"
    assert_select "td", /Company\s+· Removed/
    assert_select "a.nd-fchip[href=?]", admin_live_path(tab: "companies"), /Live/
  end

  test "a row opens a company's or plant's Record, a reactor or link its fact page, each with the way back" do
    c = company("Row Co")
    site = Facility.create!(name: "Row Site", **VERIFIED)
    unit = Facility.create!(name: "Row 1", parent: site, nrc_docket: "05099001", **VERIFIED)

    get admin_live_path(q: "Row")
    assert_select "a[href=?]", admin_record_path(type: "Organization", id: c.id, back: admin_live_path(q: "Row")), "Row Co"
    assert_select "a[href=?]", admin_record_path(type: "Facility", id: site.id, back: admin_live_path(q: "Row")), "Row Site"

    get admin_live_path(tab: "reactors", q: "Row")
    assert_select "a[href=?]", admin_fact_path(type: "Facility", id: unit.id, from: "live", back: admin_live_path(tab: "reactors", q: "Row")), "Row 1"
  end

  test "Record: the public view, status and actions, with Previous and Next through Live" do
    a = travel_to(1.day.ago) { company("Rec A Co", description: "Builds reactors.") }
    b = company("Rec B Co")
    back = admin_live_path(tab: "companies", q: "Rec ")

    get admin_record_path(type: "Organization", id: a.id, back:)

    assert_select ".nd-crumbs li a[href=?]", back, "Live"
    assert_select ".nd-factcard h1", "Rec A Co"
    assert_select ".nd-factcard p", "Builds reactors."
    assert_select ".nd-panel .type-admin-h2", "Live"
    assert_select ".nd-itemnav", /2 of 2/
    assert_select ".nd-itemnav a[rel=prev][href=?]", admin_record_path(type: "Organization", id: b.id, back:)
    assert_select "a", text: "Edit"
    assert_select "span[aria-disabled]", /Merge/
    assert_select "details summary", /Sources\s+1/
  end

  test "Edit saves changed values as an approval in the history, and Take off comes back to the Record" do
    c = company("Edit Me Co")
    back = admin_live_path

    get admin_record_edit_path(type: "Organization", id: c.id, back:)
    assert_select "input[name=?]", "values[hq_city]"

    patch admin_record_path(type: "Organization", id: c.id, back:), params: { values: { hq_city: "Everett", name: "Edit Me Co" }, note: "From its site" }
    assert_response :see_other
    assert_redirected_to admin_record_path(type: "Organization", id: c.id, back:)
    assert_equal "Everett", c.reload.hq_city
    event = Directory::Lookup.verification_history(type: "Organization", id: c.id).first
    assert_equal [ "From its site", [ nil, "Everett" ] ], [ event.reason, event.changed_values["hq_city"] ]

    post admin_fact_unpublish_path(type: "Organization", id: c.id), params: { reason: "Test", next: admin_record_path(type: "Organization", id: c.id, back:) }
    assert_redirected_to admin_record_path(type: "Organization", id: c.id, back:)
    assert c.reload.unpublished?

    get admin_record_edit_path(type: "Organization", id: c.id)
    assert_match "Put it back first", flash[:alert]
  end

  test "a unit has no Record page; its fact page opened from Live says Live" do
    site = Facility.create!(name: "Unit Site", **VERIFIED)
    unit = Facility.create!(name: "Unit 1", parent: site, **VERIFIED)

    get admin_record_path(type: "Facility", id: unit.id)
    assert_response :not_found

    get admin_fact_path(type: "Facility", id: unit.id, from: "live", back: admin_live_path(tab: "reactors"))
    assert_select ".nd-crumbs li a[href=?]", admin_live_path(tab: "reactors"), "Live"
  end
end
