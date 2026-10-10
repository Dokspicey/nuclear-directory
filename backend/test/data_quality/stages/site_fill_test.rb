require "test_helper"
require_relative "../support/dummy_plugin"

# A verified NRC unit fills its seed site's missing details, through the
# real directory.
class DataQuality::Stages::SiteFillTest < ActiveSupport::TestCase
  class UnitPlugin < DataQuality::Plugin
    def source_kind = "dummy"
  end

  setup do
    facilities(:vogtle).destroy!
    @site = Facility.create!(name: "Plant Vogtle Units 3 & 4", state: "GA")
    @site.verify!(by: "human:tosin")
    source = Source.create!(url: "https://www.nrc.gov/test/site-fill.html", source_kind: "dummy", crawl_status: "ok")
    Candidate.create!(source: source, kind: "facility", quote: "Vogtle 3 05200025 PWR Waynesboro, GA",
      payload: { "name" => "Vogtle 3", "nrc_docket" => "05200025", "facility_type" => "power_reactor",
        "status" => "operating", "state" => "TX" })
  end

  def run_stage(stage, **) = DataQuality::Pipeline.run("dummy", plugin: UnitPlugin.new, only: stage, **)

  def agree_on_state! = Candidate.sole.then { |c| c.update!(payload: c.payload.merge("state" => "GA")) }

  test "publishing a unit fills only its site's blank fields, and keeps the site's verification" do
    agree_on_state!
    run_stage("match")
    run_stage("verify", verifier: PublishEverything.new)

    @site.reload
    assert_equal [ "power_reactor", "operating" ], [ @site.facility_type, @site.status ], "blanks filled"
    assert_equal "GA", @site.state, "a field the site already had is kept"
    assert_equal [ true, "human:tosin" ], [ @site.verified?, @site.verified_by ]
    assert_equal [ "crawler" ], @site.evidence.pluck(:found_by)
  end

  test "a unit that disagrees with its human-reviewed site is published, but sent to review and fills nothing" do
    run_stage("match")
    run_stage("verify", verifier: PublishEverything.new)

    candidate = Candidate.sole
    assert Facility.find(candidate.subject_id).verified?, "the unit itself is published"
    assert candidate.status_needs_review?
    assert_match "Published, but its site disagrees: human-verified state is GA; this source says TX", candidate.notes
    assert_nil @site.reload.facility_type
    assert_empty @site.evidence
  end

  test "the site is filled from the unit as stored, not from the candidate" do
    run_stage("match")
    unit = Facility.find_by!(nrc_docket: "05200025")
    unit.update!(state: "GA")
    unit.verify!(by: "human:tosin")
    # The candidate no longer says where the unit is; the site gets the unit's own state.
    Candidate.find_by!(subject_id: unit.id).then { |c| c.update!(payload: c.payload.except("state")) }
    @site.update!(state: nil)

    run_stage("verify", verifier: PublishEverything.new)

    assert_equal "GA", @site.reload.state
  end

  test "a unit a human rejected doesn't fill its site" do
    run_stage("match")
    Facility.find_by!(nrc_docket: "05200025").reject!(by: "human:tosin")

    run_stage("verify", verifier: PublishEverything.new)

    assert_nil @site.reload.facility_type
  end

  test "the quote is evidence only for fields the site was missing" do
    @site.update!(facility_type: "power_reactor", status: "operating")
    run_stage("match")
    run_stage("verify", verifier: PublishEverything.new)

    assert_empty @site.reload.evidence, "the site had everything but a disagreeing state; nothing to fill"
  end

  test "a site a human rejected isn't filled, and the candidate says so" do
    run_stage("match")
    @site.reject!(by: "human:tosin")

    run = run_stage("verify", verifier: PublishEverything.new).last

    assert_nil @site.reload.facility_type
    assert_empty @site.evidence
    assert_equal 1, run.stats["site_not_filled"]
    assert_match "Site not filled:", Candidate.find_by!(kind: "facility").notes
  end

  test "nothing is filled until the unit is verified" do
    run_stage("match")
    run_stage("verify") # default verifier sends everything to review

    assert_nil @site.reload.facility_type
  end
end
