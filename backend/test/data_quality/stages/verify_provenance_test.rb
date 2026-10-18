require "test_helper"
require_relative "../support/dummy_plugin"

# A claim that changes a human-verified value is a conflict, unless every
# value it changes was last written from its own kind of source, approved
# unedited (Data Quality, 17 Oct): then the source is updating its own
# value, and the verifier checks it.
class DataQuality::Stages::VerifyProvenanceTest < ActiveSupport::TestCase
  class CountingVerifier
    attr_reader :asked

    def initialize = @asked = []

    def call(candidate)
      @asked << candidate.id
      DataQuality::Verdict.new(outcome: :publish, confidence: 0.9, reason: "The awards add up.")
    end
  end

  FIRST = "1 award from the U.S. Department of Energy totaling $1.0 million, 2021: DENE0000001."
  SECOND = "2 awards from the U.S. Department of Energy totaling $3.0 million, 2021–2023: DENE0000001, DENE0000002."

  setup do
    @source = Source.create!(url: "https://example.com/awards/1", source_kind: "dummy", crawl_status: "ok")
    doe = Organization.create!(name: "U.S. Department of Energy", verification_status: "verified", verified_by: "human:tosin")
    company = Organization.create!(name: "Imaginary Fission Co", verification_status: "verified", verified_by: "human:tosin")
    @link = Relationship.create!(from_organization: doe, to_organization: company, relationship_type: "funds",
      description: "Hand-written text.", started_on: Date.new(2020, 1, 1))
  end

  def claim(payload, source: @source, quote: "award #{Candidate.count}", **)
    Candidate.create!(source:, kind: "relationship", payload:, quote:, status: "matched",
      subject_type: "Relationship", subject_id: @link.id, **)
  end

  # The link as an earlier claim wrote it, approved by a person.
  def approve(payload, source: @source, **)
    first = claim(payload, source:, ai_recommendation: "recommend_publish", ai_confidence: 0.9)
    assert DataQuality::Review.approve([ first.id ], by: "human:tosin", **).sole.ok?
    assert_equal "human:tosin", @link.reload.verified_by
    first
  end

  def verify(candidate)
    verifier = CountingVerifier.new
    run = DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: "verify", verifier:).last
    [ candidate.reload, verifier, run ]
  end

  def assert_checked(candidate)
    candidate, verifier, = verify(candidate)
    assert_includes verifier.asked, candidate.id, candidate.notes
    assert_equal "recommend_publish", candidate.ai_recommendation
    assert_includes Candidate.recommended, candidate
  end

  def assert_conflict(candidate)
    candidate, verifier, run = verify(candidate)
    refute_includes verifier.asked, candidate.id
    assert candidate.status_needs_review?
    assert_match(/\Ahuman-verified description is /, candidate.notes)
    assert_equal 1, run.stats["conflicts"]
  end

  test "an approved, unedited link with a new total gets checked by the model" do
    approve({ "description" => FIRST, "started_on" => "2021-01-01" })

    assert_checked claim({ "description" => SECOND, "started_on" => "2021-01-01" })
  end

  test "an approval through Data Quality's recommendations (#355) counts as the pipeline's too" do
    approve({ "description" => FIRST, "started_on" => "2021-01-01" }, only_recommended: true, data_quality_reviewed: true,
      reason: "Accepted Data Quality's recommendation: the award page names it")

    assert_checked claim({ "description" => SECOND, "started_on" => "2021-01-01" })
  end

  # An older pipeline approval, then a newer person's write to the same field.
  test "the same link after a repair or an admin edit stays a conflict" do
    approve({ "description" => FIRST, "started_on" => "2021-01-01" })
    restored = DataQuality::DirectoryClient.new.decide_fact("relationship", id: @link.id, status: "verified", by: "human:tosin",
      reason: "Restored the hand-written description", attributes: { description: "Hand-written text." })
    assert restored.success?, restored.errors.to_sentence

    assert_conflict claim({ "description" => SECOND, "started_on" => "2021-01-01" })
  end

  test "an approval a person edited first stays a conflict" do
    first = claim({ "description" => FIRST, "started_on" => "2021-01-01" })
    assert DataQuality::Review.edit_and_approve(first.id, attributes: { "description" => "Edited text." }, by: "human:tosin").ok?
    event = Directory::Lookup.verification_history(type: "Relationship", id: @link.id).first
    assert_equal [ first.id, true ], [ event.context["candidate_id"], event.context["edited"] ]

    assert_conflict claim({ "description" => SECOND, "started_on" => "2021-01-01" })
  end

  test "an edited approval from before the marker is told by its evidence, which has no confidence" do
    first = approve({ "description" => FIRST, "started_on" => "2021-01-01" })
    Evidence.where(subject: @link, source: @source, quote: first.quote).update_all(confidence: nil)

    assert_conflict claim({ "description" => SECOND, "started_on" => "2021-01-01" })
  end

  test "a value last written from another kind of source stays a conflict" do
    other = Source.create!(url: "https://example.com/other/1", source_kind: "other_awards", crawl_status: "ok")
    approve({ "description" => FIRST, "started_on" => "2021-01-01" }, source: other)

    assert_conflict claim({ "description" => SECOND, "started_on" => "2021-01-01" })
  end

  test "a seeded value stays a conflict" do
    @link.verify!(by: "human:tosin")

    assert_conflict claim({ "description" => SECOND })
  end

  test "a claim changing a pipeline value and a person's value stays a conflict" do
    approve({ "description" => FIRST, "started_on" => "2021-01-01" })
    edited = DataQuality::DirectoryClient.new.decide_fact("relationship", id: @link.id, status: "verified", by: "human:tosin",
      reason: "The first award started in 2020", attributes: { started_on: Date.new(2020, 6, 1) })
    assert edited.success?, edited.errors.to_sentence

    candidate = claim({ "description" => SECOND, "started_on" => "2021-01-01" })
    assert_conflict candidate
    assert_match "human-verified started on is 2020-06-01", candidate.reload.notes
  end
end
