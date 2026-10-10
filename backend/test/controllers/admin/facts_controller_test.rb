require "test_helper"

# Pending facts and the fact page (#86), through the real Review API.
class Admin::FactsControllerTest < ActionDispatch::IntegrationTest
  def seed_owns_link
    link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle),
      relationship_type: "owns")
    Evidence.create!(subject: link, source: sources(:nrc), quote: "Vogtle is operated for its owners", found_by: "human")
    link
  end

  setup { sign_in_as users(:admin) }

  test "lists pending facts of a kind with their quote, and approves one" do
    link = seed_owns_link

    get admin_pending_facts_path(kind: "facility_relationship")

    assert_response :success
    assert_select "#fact-#{link.id}" do
      assert_select ".nd-item__claim a[href=?]", admin_fact_path(type: "FacilityRelationship", id: link.id),
        text: "#{organizations(:westinghouse).name} owns #{facilities(:vogtle).name}"
      assert_select ".nd-quote", "“Vogtle is operated for its owners”"
    end

    post approve_admin_pending_facts_path(kind: "facility_relationship"), params: { type: "facility_relationship", id: link.id }

    assert_redirected_to admin_pending_facts_path(kind: "facility_relationship")
    assert_equal [ "verified", "human:tosin" ], [ link.reload.verification_status, link.verified_by ]
  end

  test "rejecting a pending fact with a reason" do
    link = seed_owns_link

    post reject_admin_pending_facts_path(kind: "facility_relationship"),
      params: { type: "facility_relationship", id: link.id, reasons: { link.id.to_s => "Not an owner" } }

    assert link.reload.rejected?
    assert_equal "Not an owner", Directory::Lookup.verification_history(type: "FacilityRelationship", id: link.id).first.reason
  end

  test "an unknown kind of fact is refused" do
    post approve_admin_pending_facts_path, params: { type: "user", id: 1 }
    assert_response :bad_request
  end

  test "the fact page shows status, values and history; unpublish, then republish" do
    terrapower = organizations(:terrapower)
    terrapower.verify!(by: "human:tosin")

    get admin_fact_path(type: "Organization", id: terrapower.id)
    assert_response :success
    assert_select "h1", "TerraPower"
    assert_select ".nd-badge--verified", /Verified/
    assert_select "a[href=?]", company_path(slug: terrapower.slug), text: /View on site/

    post admin_fact_unpublish_path(type: "Organization", id: terrapower.id), params: { reason: "Merged into another company" }
    assert_redirected_to admin_fact_path(type: "Organization", id: terrapower.id)
    assert terrapower.reload.unpublished?

    follow_redirect!
    assert_select "a", text: /View on site/, count: 0, message: "not public, so no link"
    assert_select ".nd-badge", /Unpublished/
    assert_select "td", "Merged into another company"

    post admin_fact_republish_path(type: "Organization", id: terrapower.id)
    assert terrapower.reload.verified?
  end

  test "a published plant links to its public page; a pending one doesn't" do
    plant = facilities(:vogtle)
    plant.verify!(by: "human:tosin")

    get admin_fact_path(type: "Facility", id: plant.id)
    assert_select "a[href=?]", plant_path(slug: plant.slug), text: /View on site/

    pending = Facility.create!(name: "Pending Plant")
    get admin_fact_path(type: "Facility", id: pending.id)
    assert_select "a", text: /View on site/, count: 0
  end

  test "a fact type that isn't one is not found" do
    get "/admin/facts/User/1"
    assert_response :not_found
  end
end
