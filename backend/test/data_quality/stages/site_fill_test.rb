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
    # The candidate states the state (here the same GA the curated unit has; a
    # different one would be a disagreement, sent to review). The site gets the
    # unit's stored value.
    Candidate.find_by!(subject_id: unit.id).then { |c| c.update!(payload: c.payload.merge("state" => "GA")) }
    @site.update!(state: nil)

    run_stage("verify", verifier: PublishEverything.new)

    assert_equal "GA", @site.reload.state
  end

  test "only fields the candidate states are filled, so the evidence is the document that stated them" do
    run_stage("match")
    unit = Facility.find_by!(nrc_docket: "05200025")
    unit.update!(latitude: 33.14, longitude: -81.76)
    Candidate.find_by!(subject_id: unit.id).then { |c| c.update!(payload: c.payload.merge("state" => "GA")) }

    run_stage("verify", verifier: PublishEverything.new)

    @site.reload
    assert_equal "power_reactor", @site.facility_type, "stated by the NRC row"
    assert_nil @site.latitude, "the NRC row says nothing about coordinates"
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

  test "a unit whose site a human rejected after match isn't published, and the site isn't filled" do
    run_stage("match")
    @site.reject!(by: "human:tosin")

    run_stage("verify", verifier: PublishEverything.new)

    candidate = Candidate.find_by!(kind: "facility")
    assert candidate.status_needs_review?
    assert_match "site #{@site.name} was rejected by human:tosin; no units under it", candidate.notes
    assert Facility.find(candidate.subject_id).pending?, "the unit waits for a human too"
    assert_nil @site.reload.facility_type
    assert_empty @site.evidence
  end

  test "nothing is filled until the unit is verified" do
    run_stage("match")
    run_stage("verify") # default verifier sends everything to review

    assert_nil @site.reload.facility_type
  end
end
