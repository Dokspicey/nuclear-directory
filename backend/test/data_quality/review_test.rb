require "test_helper"
require_relative "support/dummy_plugin"

# The Review API the admin calls (#85), against the real directory.
class DataQuality::ReviewTest < ActiveSupport::TestCase
  include ReviewHelpers
  Review = DataQuality::Review
  BY = "human:tosin"

  class Recommend
    def call(candidate) = DataQuality::Verdict.new(outcome: :publish, confidence: 0.9, reason: "The row names #{candidate.payload['name']}.")
  end

  setup do
    @source = Source.create!(url: "https://www.nrc.gov/test/review.html", source_kind: "dummy", crawl_status: "ok",
      title: "NRC test page")
  end

  def candidate(kind, payload, quote: "a quote") = Candidate.create!(source: @source, kind:, payload:, quote:)
  def run_stage(stage, **) = DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, only: stage, **).last

  # ---- candidates

  test "lists recommended candidates as the admin shows them, by run" do
    c = candidate("organization", { "name" => "Imaginary Fission Co" })
    run_stage("match")
    verify = run_stage("verify", verifier: Recommend.new)

    item = Review.candidates(queue: :recommended).sole

    assert_equal [ c.id, "organization", 'There is an organization named "Imaginary Fission Co".', "a quote" ],
      [ item.candidate_id, item.kind, item.claim, item.quote ]
    assert_equal [ @source.url, "NRC test page" ], [ item.source.url, item.source.title ]
    assert_equal [ "recommend_publish", 0.9, verify.id ], [ item.ai_recommendation, item.ai_confidence.to_f, item.verify_run_id ]
    assert_equal({}, item.differences)
    assert_equal [ c.id ], Review.candidates(run_id: verify.id).map(&:candidate_id)
    assert_empty Review.candidates(run_id: verify.id + 1)
  end

  test "the needs-review queue filters by reason, and shows both values for a conflict" do
    unit = Facility.create!(name: "Hope Creek 1", nrc_docket: "05000354", state: "NJ")
    unit.verify!(by: BY)
    conflict = candidate("facility", { "name" => "Hope Creek 1", "nrc_docket" => "05000354", "state" => "DE" })
    candidate("organization", { "name" => "Imaginary Fission Co" }, quote: "not in the source")
    @source.update!(content_text: "Some other text entirely.")
    run_stage("match")
    run_stage("verify", verifier: Recommend.new)

    item = Review.candidates(queue: :needs_review, reason: "human-verified").sole

    assert_equal conflict.id, item.candidate_id
    assert_equal({ "state" => [ "NJ", "DE" ] }, item.differences)
    assert_equal 2, Review.candidates(queue: :needs_review).size
    assert_equal [ [ "The cited quote isn't in the source as stored, so it can't be checked", 1 ],
      [ "human-verified state is NJ; this source says DE", 1 ] ], Review.reasons
  end

  test "approves in bulk, recording who decided" do
    a = candidate("organization", { "name" => "Alpha Fission Co" })
    b = candidate("organization", { "name" => "Beta Fission Co" })
    run_stage("match")
    run_stage("verify", verifier: Recommend.new)

    results = Review.approve([ a.id, b.id ], by: BY)

    assert results.all?(&:ok?)
    [ a, b ].each(&:reload)
    assert [ a, b ].all?(&:status_merged?)
    assert_equal [ BY, BY ], [ a.reviewed_by, b.reviewed_by ]
    assert a.reviewed_at
    assert_empty Review.candidates
  end

  test "edit, then approve: the edited value is published; link ends and slug can't be edited" do
    c = candidate("facility", { "name" => "Hope Creek 1", "nrc_docket" => "05000354", "state" => "DE" })
    run_stage("match")
    run_stage("verify", verifier: Recommend.new)

    result = Review.edit_and_approve(c.id, attributes: { "state" => "NJ" }, by: BY, reason: "NRC lists the nearby city's state")

    assert result.ok?
    unit = Facility.find(result.ref.id)
    assert_equal [ "NJ", true ], [ unit.state, unit.human_verified? ]
    event = Review.history(type: "Facility", id: unit.id).first
    assert_equal "NRC lists the nearby city's state", event.reason

    link = candidate("facility_relationship", { "organization" => { "name" => "X" }, "facility" => { "name" => "Y" },
      "relationship_type" => "operates" })
    refused = Review.edit_and_approve(link.id, attributes: { "facility" => { "name" => "Z" } }, by: BY)
    assert_match "can't edit facility", refused.errors.join
  end

  test "a failed edit-then-approve keeps the candidate's original values" do
    c = candidate("organization", { "name" => "Imaginary Fission Co" })
    run_stage("match")

    result = Review.edit_and_approve(c.id, attributes: { "favourite_colour" => "blue" }, by: BY)

    assert_not result.ok?
    assert_match "unknown attributes", result.errors.join
    assert_equal({ "name" => "Imaginary Fission Co" }, c.reload.payload)
  end

  test "rejecting retires the record match proposed for it, as the human's decision" do
    c = candidate("organization", { "name" => "Imaginary Fission Co" })
    run_stage("match")
    proposed = Organization.find(c.reload.subject_id)

    result = Review.reject([ c.id ], by: BY, reason: "Not a real company").sole

    assert result.ok?
    assert_equal [ "rejected", "Not a real company", BY ], [ c.reload.status, c.notes, c.reviewed_by ]
    assert_equal [ "rejected", BY ], [ proposed.reload.verification_status, proposed.verified_by ]
    assert_match "already rejected", Review.reject([ c.id ], by: BY).sole.errors.join
  end

  test "only a human decides" do
    assert_raises(ArgumentError) { Review.approve([], by: "agent:verifier/x") }
    assert_raises(ArgumentError) { Review.reject([], by: "") }
    assert_raises(ArgumentError) { Review.unpublish(type: "Organization", id: 1, by: "agent:x") }
  end

  # ---- directory facts

  def seed_owns_link(source: sources(:nrc))
    link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle),
      relationship_type: "owns")
    Evidence.create!(subject: link, source:, quote: "Vogtle is operated for its owners", found_by: "human")
    link
  end

  test "lists pending directory facts with their evidence's source, leaving out ones a candidate covers" do
    link = seed_owns_link

    fact = Review.pending_facts(kind: "facility_relationship").sole

    assert_equal [ "FacilityRelationship", link.id ], [ fact.type, fact.id ]
    assert_equal "owns", fact.attributes[:relationship_type]
    assert_equal [ sources(:nrc).url, "Vogtle is operated for its owners", "human" ],
      [ fact.evidence.sole.source.url, fact.evidence.sole.quote, fact.evidence.sole.found_by ]

    Candidate.create!(source: @source, kind: "facility_relationship", payload: {}, status: "needs_review",
      subject_type: "FacilityRelationship", subject_id: link.id)
    assert_empty Review.pending_facts(kind: "facility_relationship"), "shown in the candidate queue instead"
  end

  test "approving a pending fact (with an edit), then unpublishing and republishing it, all in its history" do
    link = seed_owns_link

    assert Review.approve_fact(type: "FacilityRelationship", id: link.id, by: BY, attributes: { ownership_pct: 45.7 },
      reason: "Checked the annual report").ok?
    assert_equal [ "verified", BY, 45.7 ], [ link.reload.verification_status, link.verified_by, link.ownership_pct.to_f ]

    assert Review.unpublish(type: "FacilityRelationship", id: link.id, by: BY, reason: "Ownership changed").ok?
    assert link.reload.unpublished?
    assert_not_includes FacilityRelationship.published, link

    assert Review.approve_fact(type: "FacilityRelationship", id: link.id, by: BY, reason: "Confirmed again").ok?
    assert link.reload.verified?

    history = Review.history(type: "FacilityRelationship", id: link.id)
    assert_equal %w[verified unpublished verified], history.map(&:to_status).reverse
    assert_equal [ "Confirmed again", "Ownership changed", "Checked the annual report" ], history.map(&:reason)
  end

  test "rejecting a pending fact; a slug can't be edited here" do
    link = seed_owns_link

    assert Review.reject_fact(type: "FacilityRelationship", id: link.id, by: BY, reason: "Not an owner").ok?
    assert link.reload.rejected?
    assert_match "can't edit slug", Review.approve_fact(type: "Organization", id: organizations(:terrapower).id, by: BY,
      attributes: { slug: "x" }).errors.join
  end
end
