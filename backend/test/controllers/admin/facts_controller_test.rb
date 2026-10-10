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

  test "a pending fact with no source can't be approved" do
    link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle), relationship_type: "owns")

    get admin_pending_facts_path(kind: "facility_relationship")
    assert_select "#fact-#{link.id}" do
      assert_select "button", text: "Approve", count: 0
      assert_select "p", /No source recorded, so it can't be published/
    end

    post approve_admin_pending_facts_path(kind: "facility_relationship"), params: { type: "facility_relationship", id: link.id }
    assert_match "it has no source", flash[:alert]
    assert link.reload.pending?
  end

  test "the history shows what a decision changed and the claim behind it" do
    link = seed_owns_link
    DataQuality::Review.approve_fact(type: "FacilityRelationship", id: link.id, by: "human:tosin", attributes: { ownership_pct: 45.7 })

    get admin_fact_path(type: "FacilityRelationship", id: link.id)

    assert_select "td", /ownership pct?\s*blank to 45\.7|ownership blank to 45\.7/
    assert_select "td", "human:tosin"
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
    Evidence.create!(subject: terrapower, source: sources(:nrc), quote: "TerraPower", found_by: "human") # republishing needs a source

    get admin_fact_path(type: "Organization", id: terrapower.id)
    assert_response :success
    assert_select "h1", "TerraPower"
    assert_select ".nd-badge--verified", /Verified/

    post admin_fact_unpublish_path(type: "Organization", id: terrapower.id), params: { reason: "Merged into another company" }
    assert_redirected_to admin_fact_path(type: "Organization", id: terrapower.id)
    assert terrapower.reload.unpublished?

    follow_redirect!
    assert_select ".nd-badge", /Unpublished/
    assert_select "td", "Merged into another company"

    post admin_fact_republish_path(type: "Organization", id: terrapower.id)
    assert terrapower.reload.verified?
  end

  test "a fact type that isn't one is not found" do
    get "/admin/facts/User/1"
    assert_response :not_found
  end
end
