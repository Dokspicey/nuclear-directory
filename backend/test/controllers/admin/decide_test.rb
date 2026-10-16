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
    assert_equal admin_fact_path(type: "Organization", id: b.subject_id, from: "checks", back: @back), following

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
