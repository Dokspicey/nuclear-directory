require "test_helper"
require_relative "../../data_quality/support/dummy_plugin"

# Data Quality's recommendations (#306): paste its list, see exactly what
# Accept decides and what's left for a person, then accept as one decision.
class Admin::RecommendationsTest < ActionDispatch::IntegrationTest
  class Recommend
    def call(candidate) = DataQuality::Verdict.new(outcome: :publish, confidence: 0.92, reason: "The row names #{candidate.payload['name']}.")
  end

  setup do
    @source = Source.create!(url: "https://www.nrc.gov/test/recs.html", source_kind: "dummy", crawl_status: "ok", title: "NRC test page")
    sign_in_as users(:admin)
  end

  # A claim from the source's first batch (held from Approve all) about a
  # company the directory has pending, so match attaches it; the verifier
  # then recommends it.
  def claim(name)
    Directory::FactWriter.write(:organization, { name: }) # pending, with its name as an alias
    run = CrawlRun.where(source_kind: "dummy", stage: "crawl").first_or_create!(status: "succeeded", started_at: 1.hour.ago)
    Candidate.create!(source: @source, kind: "organization", payload: { "name" => name }, quote: "a quote", crawl_run: run)
  end

  def match_and_verify
    DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: "match")
    DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: "verify", verifier: Recommend.new)
  end

  def paste(text) = post admin_recommendations_path, params: { list: text }

  test "a pasted list is recorded and decides nothing; lines it can't read are listed, comments skipped" do
    a, b = claim("Alpha Fission Co"), claim("Beta Fission Co")
    match_and_verify

    paste("# DOE awards, 18 Oct\n\n#{a.id} approve: the page names Alpha\n#{b.id} Reject: a subcontract\nplease approve the rest\n999999 approve: x")

    assert_response :unprocessable_content
    assert_select ".nd-alert li", /line 5: .*isn't “<claim id> approve: <reason>”/
    assert_select ".nd-alert li", "line 6: there's no claim 999999"
    assert_equal [ "approve", "the page names Alpha" ], a.reload.slice(:dq_recommendation, :dq_reason).values
    assert_equal "reject", b.reload.dq_recommendation
    assert a.status_matched?, "recording decides nothing"
    assert_equal users(:admin).actor, a.dq_by
  end

  test "JSON works too" do
    a = claim("Alpha Fission Co")
    match_and_verify

    paste([ { id: a.id, recommendation: "approve", reason: "named on the page" } ].to_json)

    assert_response :success
    assert_equal "approve", a.reload.dq_recommendation
  end

  test "the preview lists exactly what Accept decides, and what's left with why" do
    held = claim("Alpha Fission Co")
    rejected = claim("Beta Fission Co")
    changed = claim("Gamma Fission Co")
    match_and_verify
    unrecommended = claim("Delta Fission Co") # matched, but never verified
    DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: "match")
    paste("#{held.id} approve: named on the page\n#{rejected.id} reject: not nuclear\n#{changed.id} approve: ok\n#{unrecommended.id} approve: ok")
    changed.update!(quote: "a different quote")

    get admin_recommendations_path

    assert_select "#accept-heading", /To accept\s*2/
    assert_select "#rec-#{held.id}", /Alpha Fission Co.*Approve.*named on the page/m
    assert_select "#rec-#{rejected.id}", /Reject.*not nuclear/m
    assert_select "#left-heading", /Left for you\s*2/
    assert_select "#rec-#{changed.id}", /It changed after Data Quality looked at it/
    assert_select "#rec-#{unrecommended.id}", /The verifier didn't recommend it/
  end

  test "Accept decides the shown list as the person, lifting only the first-batch hold" do
    held = claim("Alpha Fission Co")
    rejected = claim("Beta Fission Co")
    match_and_verify
    assert_equal DataQuality::Review::FIRST_BATCH, DataQuality::Review.held_reason(held.reload), "held from Approve all"
    paste("#{held.id} approve: named on the page\n#{rejected.id} reject: not nuclear")
    get admin_recommendations_path
    shown = css_select("form[action='#{admin_recommendations_accept_path}'] input[name=shown]").first["value"]

    post admin_recommendations_accept_path, params: { shown: }

    assert_redirected_to admin_recommendations_path
    assert_equal "Accepted 2 recommendations.", flash[:notice]
    assert held.reload.status_merged?
    assert_equal users(:admin).actor, held.reviewed_by
    company = Organization.find(held.subject_id)
    assert_equal "Accepted Data Quality's recommendation: named on the page", company.verification_events.order(:id).last.reason
    assert rejected.reload.status_rejected?
    assert_equal "Accepted Data Quality's recommendation: not nuclear", rejected.notes
  end

  test "if the list changed since it was shown, nothing is accepted" do
    a, b = claim("Alpha Fission Co"), claim("Beta Fission Co")
    match_and_verify
    paste("#{a.id} approve: ok")
    get admin_recommendations_path
    shown = css_select("form[action='#{admin_recommendations_accept_path}'] input[name=shown]").first["value"]
    paste("#{b.id} approve: added after the page loaded")

    post admin_recommendations_accept_path, params: { shown: }

    assert_match "The list changed since you opened it", flash[:alert]
    assert a.reload.status_matched?
    assert b.reload.status_matched?
  end

  test "a claim a person decided, or one whose company isn't settled, is never accepted" do
    a = claim("Alpha Fission Co")
    match_and_verify
    Organization.find(a.reload.subject_id).verify!(by: "human:tosin")
    paste("#{a.id} approve: ok")

    get admin_recommendations_path
    assert_select "#rec-#{a.id}", /It would change a record a person decided/

    plan = DataQuality::Recommendations.plan
    assert_empty plan.accept
    assert_equal [ "it would change a record a person decided" ], DataQuality::Recommendations.accept([ a.id ], by: users(:admin).actor).first.errors
    assert a.reload.status_matched?
  end

  test "Checks shows each claim's recommendation and how many Accept would decide" do
    a = claim("Alpha Fission Co")
    match_and_verify

    get admin_checks_path
    assert_select "a.nd-btn[href=?]", admin_recommendations_path, "Add Data Quality's list"

    paste("#{a.id} approve: named on the page")
    get admin_checks_path
    assert_select "a.nd-btn[href=?]", admin_recommendations_path, "Data Quality's recommendations (1)"
    assert_select "#claim-#{a.id}", /Data Quality recommends approving:\s*named on the page/
  end
end
