require "test_helper"
require_relative "../../data_quality/support/dummy_plugin"

# The review queue (#86), through the real Review API and directory.
class Admin::CandidatesControllerTest < ActionDispatch::IntegrationTest
  class Recommend
    def call(candidate) = DataQuality::Verdict.new(outcome: :publish, confidence: 0.92, reason: "The row names #{candidate.payload['name']}.")
  end

  setup do
    @source = Source.create!(url: "https://www.nrc.gov/test/admin.html", source_kind: "dummy", crawl_status: "ok", title: "NRC test page")
  end

  def candidate(kind, payload, quote: "a quote") = Candidate.create!(source: @source, kind:, payload:, quote:)

  def match_and_verify
    DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: "match")
    DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: "verify", verifier: Recommend.new)
  end

  test "needs a signed-in admin" do
    get admin_root_path
    assert_redirected_to new_session_path

    post approve_admin_candidates_path, params: { candidate_id: 1 }
    assert_redirected_to new_session_path
  end

  test "lists recommended claims with their quote, source and the verifier's reason, not indexed" do
    c = candidate("organization", { "name" => "Imaginary Fission Co" })
    match_and_verify
    sign_in_as users(:admin)

    get admin_root_path

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "#claim-#{c.id}" do
      assert_select ".nd-item__claim", "There is a company named “Imaginary Fission Co”."
      assert_select ".nd-quote", "“a quote”"
      assert_select "a[href=?]", @source.url, text: /NRC test page/
      assert_select ".nd-item__why", /Verifier recommends publishing.*92% sure.*The row names Imaginary Fission Co/m
      assert_select "button[name=candidate_id][value=?]", c.id.to_s, text: "Approve"
    end
    assert_select ".nd-pill[aria-current=page]", /Recommended\s+1/
  end

  test "approving one claim publishes it as the signed-in person" do
    c = candidate("organization", { "name" => "Imaginary Fission Co" })
    match_and_verify
    sign_in_as users(:admin)

    post approve_admin_candidates_path, params: { candidate_id: c.id, candidate_ids: [ c.id + 1000 ] }

    assert_redirected_to admin_candidates_path
    assert_equal "Approved 1 item.", flash[:notice]
    organization = Organization.find(c.reload.subject_id)
    assert_equal [ "verified", "human:tosin" ], [ organization.verification_status, organization.verified_by ]
  end

  test "approving the selected claims, and nothing when none is selected" do
    a = candidate("organization", { "name" => "Alpha Fission Co" })
    b = candidate("organization", { "name" => "Beta Fission Co" })
    match_and_verify
    sign_in_as users(:admin)

    post approve_admin_candidates_path, params: {}
    assert_equal "Select at least one claim to approve.", flash[:alert]

    post approve_admin_candidates_path(queue: "recommended"), params: { candidate_ids: [ a.id, b.id ] }

    assert_redirected_to admin_candidates_path(queue: "recommended")
    assert_equal "Approved 2 items.", flash[:notice]
    assert [ a, b ].all? { |x| x.reload.status_merged? }
  end

  test "bulk approval is for recommended claims only" do
    recommended = candidate("organization", { "name" => "Imaginary Fission Co" })
    unsure = candidate("organization", { "name" => "Quoted Co" }, quote: "not in the source")
    @source.update!(content_text: "Imaginary Fission Co appears here, and a quote too: a quote")
    match_and_verify
    assert unsure.reload.status_needs_review?
    sign_in_as users(:admin)

    get admin_candidates_path(queue: "needs_review")
    assert_select ".nd-bulk", 0
    assert_select "input[name='candidate_ids[]']", 0

    post approve_admin_candidates_path, params: { candidate_ids: [ recommended.id, unsure.id ] }

    assert_equal "Approved 1 item.", flash[:notice]
    assert_match "Claim #{unsure.id}: it isn't recommended, so approve it on its own", flash[:alert]
    assert unsure.reload.status_needs_review?

    post approve_admin_candidates_path, params: { candidate_id: unsure.id }
    assert unsure.reload.status_merged?, "on its own, it can be approved"
  end

  test "approve all: every recommended claim on every page, in the background, as the signed-in person (#188)" do
    stub_const(Admin::CandidatesController, :PAGE, 2) do
      claims = %w[Alpha Beta Gamma].map { |name| candidate("organization", { "name" => "#{name} Fission Co" }) }
      unsure = candidate("organization", { "name" => "Quoted Co" }, quote: "not in the source")
      @source.update!(content_text: "Alpha Fission Co Beta Fission Co Gamma Fission Co a quote")
      match_and_verify
      sign_in_as users(:admin)

      get admin_candidates_path(queue: "recommended")
      assert_select ".nd-items > li", 2, "one page"
      assert_select "p", /On all pages: 3 recommended claims/
      assert_select "form[action=?] button", approve_all_admin_candidates_path(queue: "recommended"), "Approve all 3"

      perform_enqueued_jobs { post approve_all_admin_candidates_path(queue: "recommended") }

      assert_redirected_to admin_candidates_path(queue: "recommended")
      assert_match "Approving 3 recommended claims", flash[:notice]
      claims.each do |claim|
        assert claim.reload.status_merged?, claim.payload["name"]
        assert_equal "human:tosin", Organization.find(claim.subject_id).verified_by
      end
      assert unsure.reload.status_needs_review?, "a claim needing review is never approved in bulk"
    end
  end

  test "approve all keeps to the queue's filters, and says when nothing matches" do
    candidate("organization", { "name" => "Alpha Fission Co" })
    match_and_verify
    sign_in_as users(:admin)

    assert_no_enqueued_jobs only: DataQuality::ApproveAllJob do
      post approve_all_admin_candidates_path(queue: "recommended", reason: "no such reason")
    end
    assert_equal "Nothing to approve: no recommended claims match these filters.", flash[:alert]
  end

  test "rejecting a claim with a reason" do
    c = candidate("organization", { "name" => "Imaginary Fission Co" })
    match_and_verify
    sign_in_as users(:admin)

    post reject_admin_candidates_path, params: { candidate_id: c.id, reasons: { c.id.to_s => "Not a real company" } }

    assert_equal "Rejected 1 item.", flash[:notice]
    assert_equal [ "rejected", "Not a real company", "human:tosin" ], [ c.reload.status, c.notes, c.reviewed_by ]
  end

  test "a claim that disagrees with a human-verified record shows both values" do
    unit = Facility.create!(name: "Hope Creek 1", nrc_docket: "05000354", state: "NJ")
    unit.verify!(by: "human:tosin")
    c = candidate("facility", { "name" => "Hope Creek 1", "nrc_docket" => "05000354", "state" => "DE" })
    match_and_verify
    sign_in_as users(:admin)

    get admin_candidates_path(queue: "needs_review")

    assert_select "#claim-#{c.id}" do
      assert_select ".nd-item__why", /Human-verified state is NJ; this source says DE/
      assert_select "tbody tr", 1 do
        assert_select "th", "State"
        assert_select "td", "NJ"
        assert_select "td", "DE"
      end
    end
  end

  test "filtering the queue by reason" do
    candidate("organization", { "name" => "Quoted Co" }, quote: "not in the source")
    @source.update!(content_text: "Other text.")
    match_and_verify
    sign_in_as users(:admin)

    get admin_candidates_path(queue: "needs_review", reason: "The cited quote isn't in the source as stored, so it can't be checked")
    assert_select ".nd-item", 1

    get admin_candidates_path(queue: "needs_review", reason: "No such reason")
    assert_select ".nd-item", 0
    assert_select ".nd-notice", /No claims match these filters/
  end

  test "edit, then approve: publishes the edited value; link ends can't be posted" do
    c = candidate("facility", { "name" => "Hope Creek 1", "nrc_docket" => "05000354", "state" => "DE" })
    match_and_verify
    sign_in_as users(:admin)

    get edit_admin_candidate_path(c)
    assert_select "input[name=?][value=?]", "values[state]", "DE"

    patch admin_candidate_path(c), params: { values: { state: "NJ", facility: "Somewhere else" }, note: "NRC lists the nearby city's state" }

    assert_redirected_to admin_candidates_path
    unit = Facility.find(c.reload.subject_id)
    assert_equal [ "NJ", "human:tosin" ], [ unit.state, unit.verified_by ]
    assert_equal "NRC lists the nearby city's state", Directory::Lookup.verification_history(type: "Facility", id: unit.id).first.reason
  end

  test "a failed edit shows the error and keeps the form" do
    c = candidate("organization", { "name" => "Imaginary Fission Co", "founded_year" => "1990" })
    match_and_verify
    sign_in_as users(:admin)

    patch admin_candidate_path(c), params: { values: { founded_year: "not a year" } }

    assert_response :unprocessable_content
    assert_select ".nd-alert[role=alert]", /Not approved. Fix this and approve again/
    assert c.reload.status_matched?, "nothing approved"
  end
end
