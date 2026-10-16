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

  test "Checks lists pending facts under Facts, with their quote behind Details, and approves one" do
    link = seed_owns_link

    get admin_pending_facts_path(kind: "facility_relationship")
    assert_redirected_to admin_checks_path(category: "facts")
    follow_redirect!

    assert_response :success
    assert_select ".nd-fchip[aria-current=page]", /Facts\s+\d+/
    assert_select "#fact-FacilityRelationship-#{link.id}" do
      assert_select ".type-kicker", "Pending plant owner or operator · nrc.gov"
      assert_select ".type-subject a[href=?]", admin_fact_path(type: "FacilityRelationship", id: link.id, from: "checks", back: "/admin/checks?category=facts"),
        text: "#{organizations(:westinghouse).name} owns #{facilities(:vogtle).name}"
      assert_select "details .nd-quote", "“Vogtle is operated for its owners”"
    end

    post approve_admin_pending_facts_path(category: "facts"), params: { type: "FacilityRelationship", id: link.id }

    assert_redirected_to admin_checks_path(category: "facts")
    assert_equal [ "verified", "human:tosin" ], [ link.reload.verification_status, link.verified_by ]
  end

  test "a pending fact with no source can't be approved" do
    link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle), relationship_type: "owns")

    get admin_checks_path(category: "facts")
    assert_select "#fact-FacilityRelationship-#{link.id}" do
      assert_select "button", text: "Approve", count: 0
      assert_select "button", text: "Reject"
      assert_select "details p", /No source, so it can't be published/
    end

    post approve_admin_pending_facts_path, params: { type: "facility_relationship", id: link.id }
    assert_match "it has no source", flash[:alert]
    assert link.reload.pending?
  end

  test "the history shows what a decision changed and the claim behind it" do
    link = seed_owns_link
    DataQuality::Review.approve_fact(type: "FacilityRelationship", id: link.id, by: "human:tosin", attributes: { ownership_pct: 45.7 })

    get admin_fact_path(type: "FacilityRelationship", id: link.id)

    assert_select "details", /History\s+1/
    assert_select ".nd-fold__row", /ownership pct?\s*blank to 45\.7|ownership blank to 45\.7/
    assert_select ".nd-fold__row", /tosin/
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

  test "the fact page shows its status, values and history beside Take off (reason required), then Put back" do
    terrapower = organizations(:terrapower)
    terrapower.verify!(by: "human:tosin")
    Evidence.create!(subject: terrapower, source: sources(:nrc), quote: "TerraPower", found_by: "human") # republishing needs a source

    get admin_fact_path(type: "Organization", id: terrapower.id)
    assert_response :success
    assert_select "h1", "TerraPower"
    assert_select ".nd-panel .type-admin-h2", "Live"
    assert_select "a[href=?]", company_path(slug: terrapower.slug), text: /Open/
    assert_select "form[action=?]", admin_fact_unpublish_path(type: "Organization", id: terrapower.id) do
      assert_select "input[name=reason][required]"
      assert_select "button", "Take off"
    end

    post admin_fact_unpublish_path(type: "Organization", id: terrapower.id), params: { reason: "   " }
    assert_equal "Say why it's taken off.", flash[:alert]
    assert terrapower.reload.verified?, "no reason, nothing taken off"

    post admin_fact_unpublish_path(type: "Organization", id: terrapower.id), params: { reason: "Merged into another company" }
    assert_redirected_to admin_fact_path(type: "Organization", id: terrapower.id)
    assert terrapower.reload.unpublished?

    follow_redirect!
    assert_select "a", text: /Open/, count: 0, message: "not public, so no link"
    assert_select ".nd-panel .type-admin-h2", "Removed"
    assert_select ".nd-fold__row", /Merged into another company/
    assert_select "button", "Put back"

    post admin_fact_republish_path(type: "Organization", id: terrapower.id)
    assert terrapower.reload.verified?
  end

  test "a published plant links to its public page; a pending one doesn't" do
    plant = facilities(:vogtle)
    plant.verify!(by: "human:tosin")

    get admin_fact_path(type: "Facility", id: plant.id)
    assert_select "a[href=?]", plant_path(slug: plant.slug), text: /Open/

    pending = Facility.create!(name: "Pending Plant")
    get admin_fact_path(type: "Facility", id: pending.id)
    assert_select "a[href=?]", plant_path(slug: pending.slug), count: 0
    assert_select ".nd-panel .type-admin-h2", "Waiting"
    # Decided here, then back to the list it came from.
    get admin_fact_path(type: "Facility", id: pending.id, from: "checks", back: admin_checks_path(category: "facts"))
    assert_select ".nd-decide input[name=back][value=?]", admin_checks_path(category: "facts")
    assert_select ".nd-decide button", "Reject"
  end

  test "a pending site that's public through a published unit links to its page and says so" do
    site = Facility.create!(name: "Plant Example Site")
    unit = Facility.create!(name: "Example 1", parent: site, nrc_docket: "05099991")
    unit.verify!(by: "human:tosin")
    assert site.reload.pending?
    assert_includes Facility.published, site, "#104: a pending site shows once a unit is published"

    get admin_fact_path(type: "Facility", id: site.id)

    assert_select "a[href=?]", plant_path(slug: site.slug), text: /Open/
    assert_select ".nd-panel .type-admin-h2", "Pending, shown with its units"
  end

  test "a fact type that isn't one is not found" do
    get "/admin/facts/User/1"
    assert_response :not_found
  end
end
