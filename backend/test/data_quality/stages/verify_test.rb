require "test_helper"
require_relative "../support/dummy_plugin"

# Verify against the real directory: what a rejection does to the record
# match proposed, and how link details arrive on publish.
class DataQuality::Stages::VerifyTest < ActiveSupport::TestCase
  class RejectEverything
    def call(_candidate) = DataQuality::Verdict.new(outcome: :reject, reason: "not a real company")
  end

  setup do
    @source = Source.create!(url: "https://example.com/verify-test", source_kind: "dummy", crawl_status: "ok")
  end

  def candidate(kind, payload) = Candidate.create!(source: @source, kind: kind, payload: payload, quote: "a quote")
  def run_stage(stage, **) = DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: stage, **).last

  test "rejecting a proposal retires the record match created" do
    c = candidate("organization", { "name" => "Imaginary Fission Co" })
    run_stage("match")
    proposed = Organization.find(c.reload.subject_id)
    assert c.proposed_subject?

    run_stage("verify", verifier: RejectEverything.new)

    assert c.reload.status_rejected?
    assert proposed.reload.rejected?
  end

  test "rejecting a candidate attached to an existing record leaves that record alone" do
    c = candidate("organization", { "name" => "TerraPower, Inc." })
    run_stage("match")
    assert_not c.reload.proposed_subject?

    run_stage("verify", verifier: RejectEverything.new)

    assert organizations(:terrapower).reload.pending?
  end

  test "a proposal another live candidate also points at isn't retired" do
    first, second = 2.times.map { candidate("organization", { "name" => "Entergy Nuclear Operations, Inc." }) }
    run_stage("match")
    second.reload.update!(status: "needs_review")

    run_stage("verify", verifier: RejectEverything.new)

    assert first.reload.status_rejected?
    assert Organization.find(first.subject_id).pending?
  end

  test "a shared proposal is retired when its last candidate is rejected, whichever created it" do
    first, second = 2.times.map { candidate("organization", { "name" => "Imaginary Fission Co" }) }
    run_stage("match")
    assert_equal [ true, false ], [ first, second ].map { |c| c.reload.proposed_subject? }

    run_stage("verify", verifier: RejectEverything.new)

    assert Organization.find(first.subject_id).rejected?
  end

  test "a rejected match leaves no alias behind" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "domain" => "terrapower.com" })
    run_stage("match")
    assert_equal organizations(:terrapower).id, c.reload.subject_id

    run_stage("verify", verifier: RejectEverything.new)

    assert_nil Directory::Lookup.organization(name: "TP Nuclear Holdings")
  end

  test "a record a human rejects between match and verify isn't changed by publishing" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "domain" => "terrapower.com" })
    run_stage("match")
    organizations(:terrapower).reject!(by: "human:tosin")

    verify = run_stage("verify", verifier: PublishEverything.new)

    assert c.reload.status_needs_review?
    assert_match "TerraPower was rejected by human:tosin", c.notes
    assert_equal [ 0, 1 ], verify.stats.values_at("write_errors", "needs_review"), "caught before the verifier is asked"
    assert_nil Directory::Lookup.organization(name: "TP Nuclear Holdings")
  end

  test "a record unpublished after match sends its candidate to review, even with a review-only verifier" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "domain" => "terrapower.com" })
    run_stage("match")
    organizations(:terrapower).tap { |o| o.verify!(by: "human:tosin") }.unpublish!(by: "human:tosin")

    run_stage("verify")

    assert c.reload.status_needs_review?
    assert_match(/TerraPower was unpublished by human:tosin on \d{4}-\d{2}-\d{2} after this was matched/, c.notes)
  end

  test "a decision made while the verifier is thinking still wins" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "domain" => "terrapower.com" })
    run_stage("match")
    terrapower = organizations(:terrapower)
    slow = Object.new
    slow.define_singleton_method(:call) do |_candidate|
      terrapower.tap { |o| o.verify!(by: "human:tosin") }.unpublish!(by: "human:tosin")
      DataQuality::Verdict.new(outcome: :reject, reason: "not a real company")
    end

    run_stage("verify", verifier: slow)

    assert c.reload.status_needs_review?, "sent to review, not rejected"
    assert_match "TerraPower was unpublished by human:tosin", c.notes
  end

  test "a link unpublished after match sends its candidate to review too" do
    link = FacilityRelationship.create!(organization: organizations(:terrapower), facility: facilities(:vogtle),
      relationship_type: "owns")
    c = candidate("facility_relationship", { "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => facilities(:vogtle).name }, "relationship_type" => "owns" })
    run_stage("match")
    link.verify!(by: "human:tosin")
    link.unpublish!(by: "human:tosin")

    run_stage("verify", verifier: RejectEverything.new)

    assert c.reload.status_needs_review?, "not rejected by the verifier"
    assert_match "The fact “TerraPower owns #{facilities(:vogtle).name}” was unpublished by human:tosin", c.notes
  end

  test "publishing a match keeps the company's own name, adding the candidate's as an alias" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "domain" => "terrapower.com" })
    run_stage("match")

    run_stage("verify", verifier: PublishEverything.new)

    assert c.reload.status_merged?
    assert_equal "TerraPower", organizations(:terrapower).reload.name
    assert_equal organizations(:terrapower).id, Directory::Lookup.organization(name: "TP Nuclear Holdings").id
  end

  test "matching an existing link adds no evidence before it's published" do
    link = FacilityRelationship.create!(organization: organizations(:terrapower), facility: facilities(:vogtle),
      relationship_type: "owns")
    candidate("facility_relationship", { "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => "Vogtle Electric Generating Plant" }, "relationship_type" => "owns" })

    run_stage("match")

    assert_empty link.reload.evidence
  end

  test "a link's details arrive when it's published, not at match" do
    candidate("organization", { "name" => "Example Operating Co" })
    candidate("facility", { "name" => "Example 1", "nrc_docket" => "05000999", "facility_type" => "power_reactor" })
    link = candidate("facility_relationship", { "organization" => { "name" => "Example Operating Co" },
      "facility" => { "name" => "Example 1", "nrc_docket" => "05000999" }, "relationship_type" => "operates",
      "description" => "Licensed operator" })

    run_stage("match")
    record = FacilityRelationship.find(link.reload.subject_id)
    assert_nil record.description, "pending links carry only what identifies them"

    run_stage("verify", verifier: PublishEverything.new)
    assert_equal "Licensed operator", record.reload.description
  end

  test "matching an existing link doesn't overwrite its details before verification" do
    link = FacilityRelationship.create!(organization: organizations(:terrapower), facility: facilities(:vogtle),
      relationship_type: "owns", description: "From an earlier crawl")
    c = candidate("facility_relationship", { "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => "Vogtle Electric Generating Plant" }, "relationship_type" => "owns",
      "description" => "Unverified new text" })

    run_stage("match")

    assert_equal link.id, c.reload.subject_id
    assert_equal "From an earlier crawl", link.reload.description
  end
end
