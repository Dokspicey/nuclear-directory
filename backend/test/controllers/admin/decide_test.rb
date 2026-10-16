require "test_helper"

# Deciding on an item page (#269, Design's spec on #166): the buttons by
# kind of item, then on to the next item in the list, the list after the
# last, and the result once nothing waits.
class Admin::DecideTest < ActionDispatch::IntegrationTest
  setup do
    @nrc = Source.create!(url: "https://www.nrc.gov/test/decide.html", source_kind: "nrc_reactor_list", crawl_status: "ok")
    @back = "/admin/checks"
    sign_in_as users(:admin)
  end

  def waiting(name, notes: "unsure")
    subject = Organization.create!(name:)
    Candidate.create!(source: @nrc, kind: "organization", payload: { "name" => name }, quote: "q", status: "needs_review", notes:,
      subject_type: "Organization", subject_id: subject.id)
  end

  def open(candidate) = get admin_fact_path(type: candidate.subject_type, id: candidate.subject_id, from: "checks", back: @back)
  def bar_buttons = css_select(".nd-decide__buttons > button, .nd-decide__buttons > a, .nd-decide__buttons summary").map { |b| b.text.squish }

  test "a new claim: Approve, Reject, Edit" do
    open(waiting("Alpha Co"))
    assert_equal [ "Approve", "Reject", "Edit" ], bar_buttons
  end

  test "a claim that changes a human-verified value: Approve new value, Keep current, Edit" do
    unit = Facility.create!(name: "Hope Creek 1", nrc_docket: "05000354", state: "NJ", verification_status: "verified", verified_by: "human:tosin")
    claim = Candidate.create!(source: @nrc, kind: "facility", quote: "q", status: "needs_review", notes: "human-verified state is NJ; this source says DE",
      subject_type: "Facility", subject_id: unit.id, payload: { "name" => "Hope Creek 1", "nrc_docket" => "05000354", "state" => "DE" })

    open(claim)

    assert_equal [ "Approve new value", "Keep current", "Edit" ], bar_buttons
    post reject_admin_candidates_path(kept: 1), params: { candidate_id: claim.id, back: @back }
    assert_equal "NJ", unit.reload.state
  end

  test "before approving, the page shows what the claim proposes: NJ → DE, its quote and source" do
    unit = Facility.create!(name: "Hope Creek 1", nrc_docket: "05000354", state: "NJ", verification_status: "verified", verified_by: "human:tosin")
    claim = Candidate.create!(source: @nrc, kind: "facility", quote: "Hope Creek 1, Hancocks Bridge, DE", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: unit.id, payload: { "name" => "Hope Creek 1", "nrc_docket" => "05000354", "state" => "DE" })

    open(claim)

    assert_select "#proposed" do
      assert_select "dd", 1, "a changed value lists only what it changes"
      assert_select "dd", /NJ → DE/
      assert_select "dd .text-ink-muted", "NJ →"
      assert_select "dd .type-body-strong", "DE"
      assert_select ".nd-quote", "“Hope Creek 1, Hancocks Bridge, DE”"
      assert_select "a[href=?]", @nrc.url
    end
  end

  test "a changed value worked out from the claim (a website's domain) still shows old → new" do
    company = Organization.create!(name: "Kairos Power", domain: "kairospower.com", verification_status: "verified", verified_by: "human:tosin")
    claim = Candidate.create!(source: @nrc, kind: "organization", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Organization", subject_id: company.id, payload: { "name" => "Kairos Power", "website" => "https://kairos-power.example" })

    open(claim)

    assert_select "#proposed dd", /kairospower\.com → kairos-power\.example/
  end

  test "reopening a decided claim shows its own result, not another claim's buttons" do
    unit = Facility.create!(name: "Catawba 2", nrc_docket: "05000414", verification_status: "verified", verified_by: "human:tosin")
    eia = Source.create!(url: "https://www.eia.gov/decide2.xlsx", source_kind: "eia_generators", crawl_status: "ok")
    Candidate.create!(source: @nrc, kind: "facility", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: unit.id, payload: { "name" => "Catawba 2", "state" => "SC" })
    from_eia = Candidate.create!(source: eia, kind: "facility", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: unit.id, payload: { "identify" => { "name" => "Catawba", "unit" => "2" }, "capacity_mw" => "1150.1" })
    post reject_admin_candidates_path, params: { candidate_id: from_eia.id, reasons: { from_eia.id.to_s => "Wrong unit" } }

    get admin_fact_path(type: "Facility", id: unit.id, from: "checks", back: admin_checks_path(source: "eia_generators"), claim: from_eia.id)

    assert_select ".nd-decide", 0
    assert_select ".nd-decide__result", /Rejected by tosin/
  end

  test "Take off and Put back come back to the claim the page was opened for" do
    unit = Facility.create!(name: "Catawba 2", nrc_docket: "05000414", verification_status: "verified", verified_by: "human:tosin")
    Evidence.create!(subject: unit, source: @nrc, quote: "Catawba 2", found_by: "crawler")
    eia = Source.create!(url: "https://www.eia.gov/decide3.xlsx", source_kind: "eia_generators", crawl_status: "ok")
    Candidate.create!(source: @nrc, kind: "facility", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: unit.id, payload: { "name" => "Catawba 2", "state" => "SC" })
    from_eia = Candidate.create!(source: eia, kind: "facility", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: unit.id, payload: { "identify" => { "name" => "Catawba", "unit" => "2" }, "capacity_mw" => "1150.1" })
    here = { from: "checks", back: admin_checks_path(source: "eia_generators"), claim: from_eia.id }

    get admin_fact_path(type: "Facility", id: unit.id, **here)
    assert_select "form[action=?]", admin_fact_unpublish_path(type: "Facility", id: unit.id, **here)

    post admin_fact_unpublish_path(type: "Facility", id: unit.id, **here), params: { reason: "Test" }
    assert_redirected_to admin_fact_path(type: "Facility", id: unit.id, **here)
    follow_redirect!
    assert_select ".nd-decide button[value=?]", from_eia.id.to_s, minimum: 1

    post admin_fact_republish_path(type: "Facility", id: unit.id, **here)
    assert_redirected_to admin_fact_path(type: "Facility", id: unit.id, **here)
  end

  test "the bar decides the claim that was opened, when two sources have one on the same fact" do
    unit = Facility.create!(name: "Catawba 2", nrc_docket: "05000414", verification_status: "verified", verified_by: "human:tosin")
    eia = Source.create!(url: "https://www.eia.gov/decide.xlsx", source_kind: "eia_generators", crawl_status: "ok")
    from_nrc = Candidate.create!(source: @nrc, kind: "facility", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: unit.id, payload: { "name" => "Catawba 2", "state" => "SC" })
    from_eia = Candidate.create!(source: eia, kind: "facility", quote: "q", status: "needs_review", notes: "unsure",
      subject_type: "Facility", subject_id: unit.id, payload: { "identify" => { "name" => "Catawba", "unit" => "2" }, "capacity_mw" => "1150.1" })

    get admin_fact_path(type: "Facility", id: unit.id, from: "checks", back: admin_checks_path(source: "eia_generators"), claim: from_eia.id)

    assert_select ".nd-decide button[name=candidate_id][value=?]", from_eia.id.to_s, minimum: 1
    assert_select ".nd-decide button[value=?]", from_nrc.id.to_s, 0
    assert_select ".nd-itemnav", /1 of 1/, "the list is the EIA one"
  end

  test "a pending fact whose claim is still open (a lapsed recommendation) isn't decided on its own" do
    link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle), relationship_type: "owns")
    Evidence.create!(subject: link, source: @nrc, quote: "owns", found_by: "crawler")
    Candidate.create!(source: @nrc, kind: "facility_relationship", quote: "q", status: "matched", ai_recommendation: "recommend_publish",
      ai_source_sha256: "an older snapshot", subject_type: "FacilityRelationship", subject_id: link.id, payload: { "relationship_type" => "owns" })

    get admin_fact_path(type: "FacilityRelationship", id: link.id, from: "checks", back: @back)

    assert_select ".nd-decide", 0
    assert_select "button", text: "Approve", count: 0
  end

  test "a possible duplicate: Merge (not built yet), Keep separate, Reject" do
    open(waiting("GENERAL ATOMICS", notes: 'no exact match for "GENERAL ATOMICS", but similar: General Matter. Same record, or a new one?'))

    assert_equal [ "Merge", "Keep separate", "Reject" ], bar_buttons
    assert_select ".nd-decide button[disabled]", "Merge"
  end

  test "a pending fact: Approve, disabled without a source, and Reject" do
    link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle), relationship_type: "owns")

    get admin_fact_path(type: "FacilityRelationship", id: link.id, from: "checks", back: @back)

    assert_equal [ "Approve", "Reject" ], bar_buttons
    assert_select ".nd-decide button[disabled]", "Approve"
    assert_select ".nd-decide__hint", "Needs a source to approve"
  end

  test "deciding opens the next item, with where it is, then the list after the last" do
    a, b = waiting("Alpha Co"), waiting("Beta Co")
    open(a)
    following = css_select(".nd-decide input[name=next]").first["value"]
    assert_equal admin_fact_path(type: "Organization", id: b.subject_id, from: "checks", back: @back, claim: b.id), following

    post approve_admin_candidates_path, params: { candidate_id: a.id, back: @back, next: following }
    assert_response :see_other
    assert_redirected_to following
    follow_redirect!
    assert_select ".nd-flash", "Approved. 1 of #{1 + DataQuality::Review.pending_count}."

    post reject_admin_candidates_path, params: { candidate_id: b.id, back: @back, reasons: { b.id.to_s => "Not a company" } }
    assert_redirected_to @back
    assert_equal "Not a company", b.reload.notes
  end

  test "a decided item shows its result instead of the buttons, so Back can't post it twice" do
    a = waiting("Alpha Co")
    post approve_admin_candidates_path, params: { candidate_id: a.id, back: @back }

    open(a)

    assert_select ".nd-decide", 0
    assert_select ".nd-decide__result", /Approved by tosin · \d+ \w+ \d\d:\d\d/
  end

  test "a rejected fact's status reads who and when, short: 'Rejected by tosin · 16 Oct 14:02'" do
    travel_to Time.zone.parse("2026-10-16 14:02")
    link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle), relationship_type: "owns")
    post reject_admin_pending_facts_path, params: { type: "FacilityRelationship", id: link.id }

    get admin_fact_path(type: "FacilityRelationship", id: link.id)

    assert_select ".nd-panel p", "Rejected by tosin · 16 Oct 14:02"
  end

  test "Edit, then approve has Reject too, and it moves on to the next claim" do
    a, b = waiting("Alpha Co"), waiting("Beta Co")

    get edit_admin_candidate_path(a, back: @back)
    following = css_select("details input[name=next]").first["value"]
    assert_equal edit_admin_candidate_path(b, back: @back), following

    post reject_admin_candidates_path, params: { candidate_id: a.id, back: @back, next: following, reasons: { a.id.to_s => "Duplicate" } }
    assert_redirected_to following
    assert_equal [ "rejected", "Duplicate" ], [ a.reload.status, a.notes ]
  end
end
