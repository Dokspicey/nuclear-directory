require "test_helper"

# Directory::FactWriter.remove_evidence: a human takes a misplaced quote off a fact (#226).
class Directory::RemoveEvidenceTest < ActiveSupport::TestCase
  BY = "human:tosin"
  REASON = "Quote is about another plant (#226)"

  setup do
    @link = FacilityRelationship.create!(organization: organizations(:westinghouse), facility: facilities(:vogtle),
      relationship_type: "operates")
    @right = Evidence.create!(subject: @link, source: sources(:nrc), quote: "Vogtle 1 | Westinghouse", found_by: "crawler", confidence: 0.9)
    @wrong = Evidence.create!(subject: @link, source: sources(:press_release), quote: "Farley 1 | Southern Nuclear",
      found_by: "crawler", confidence: 0.9)
    @link.verify!(by: BY)
  end

  def remove(evidence = @wrong, **options)
    Directory::FactWriter.remove_evidence(type: "FacilityRelationship", id: @link.id, evidence_id: evidence.id,
      source_id: evidence.source_id, quote: evidence.quote, by: BY, reason: REASON, **options)
  end

  def remove_from(type, id, evidence, by: BY)
    Directory::FactWriter.remove_evidence(type:, id:, evidence_id: evidence.id, source_id: evidence.source_id,
      quote: evidence.quote, by:, reason: REASON)
  end

  test "removes the row and records what was removed, who and why" do
    result = remove

    assert result.ok?, result.errors.inspect
    assert_equal [ @right.id ], @link.evidence.reload.ids
    event = @link.verification_events.order(:created_at).last
    assert_equal [ "verified", "verified", BY, REASON ], [ event.from_status, event.to_status, event.by, event.reason ]
    assert_equal({ "evidence" => [ "#{sources(:press_release).url}: Farley 1 | Southern Nuclear", nil ] }, event.changed_values)
    assert @link.reload.verified?
  end

  test "the fact counts as changed: updated_at moves and the public snapshot expires" do
    updated_at = @link.reload.updated_at
    generation = DirectorySnapshot.generation

    travel 1.minute do
      assert remove.ok?
    end

    assert_operator @link.reload.updated_at, :>, updated_at
    assert_operator DirectorySnapshot.generation, :>, generation
  end

  test "only a human removes evidence, with a reason" do
    agent = remove_from("FacilityRelationship", @link.id, @wrong, by: "agent:verifier/x")
    no_reason = remove(reason: " ")

    assert_match "a human's decision", agent.errors.join
    assert_match "needs a reason", no_reason.errors.join
    assert_equal 2, @link.evidence.count
  end

  test "evidence on another fact isn't removed" do
    other = FacilityRelationship.create!(organization: organizations(:terrapower), facility: facilities(:vogtle),
      relationship_type: "owns")
    elsewhere = Evidence.create!(subject: other, source: sources(:nrc), quote: "TerraPower", found_by: "crawler")

    result = remove(elsewhere)

    refute result.ok?
    assert_match "isn't on", result.errors.join
    assert Evidence.exists?(elsewhere.id)
  end

  test "the source and quote given must be the row's" do
    other_quote = remove(quote: "Vogtle 1 | Westinghouse")
    other_source = remove(source_id: sources(:nrc).id)
    loose_source = remove(source_id: "#{@wrong.source_id}oops")
    no_quote = Evidence.create!(subject: @link, source: sources(:nrc), quote: nil, found_by: "crawler")
    blank_for_nil = remove(no_quote, quote: "")

    [ other_quote, other_source, loose_source, blank_for_nil ].each { |result| assert_match "isn't the source and quote given", result.errors.join }
    assert Evidence.exists?(@wrong.id)
    assert Evidence.exists?(no_quote.id)
  end

  test "a published fact keeps its last evidence" do
    assert remove.ok?

    result = remove(@right)

    refute result.ok?
    assert_match "only evidence", result.errors.join
    assert Evidence.exists?(@right.id)
  end

  test "a pending site that is public through a verified unit keeps its last evidence" do
    site = Facility.create!(name: "Acme Site")
    Facility.create!(name: "Acme 1", parent: site, nrc_docket: "05099999").verify!(by: BY)
    only = Evidence.create!(subject: site, source: sources(:nrc), quote: "Acme Site", found_by: "crawler")
    assert site.reload.pending?

    result = remove_from("Facility", site.id, only)

    refute result.ok?
    assert_match "only evidence", result.errors.join
    assert Evidence.exists?(only.id)
  end

  test "a pending fact can lose its last evidence" do
    link = FacilityRelationship.create!(organization: organizations(:terrapower), facility: facilities(:vogtle),
      relationship_type: "owns")
    only = Evidence.create!(subject: link, source: sources(:nrc), quote: "TerraPower", found_by: "crawler")

    result = remove_from("FacilityRelationship", link.id, only)

    assert result.ok?, result.errors.inspect
    assert_empty link.evidence.reload
  end

  test "a rejected or unpublished fact isn't changed" do
    @link.reject!(by: BY, reason: "test")

    result = remove

    refute result.ok?
    assert_match "was rejected", result.errors.join
    assert Evidence.exists?(@wrong.id)
  end

  test "a refused destroy is an error, not an exception, and changes nothing" do
    wrong_id = @wrong.id
    refuse = -> { throw :abort if id == wrong_id }
    Evidence.set_callback(:destroy, :before, refuse)
    result = remove

    refute result.ok?
    assert Evidence.exists?(@wrong.id)
    assert_empty @link.verification_events.where("changed_values ? 'evidence'")
  ensure
    Evidence.skip_callback(:destroy, :before, refuse)
  end

  test "an unknown type or id is an error, not an exception" do
    assert_match "not a fact type", remove_from("Source", 1, @wrong).errors.join
    assert_match "no FacilityRelationship", remove_from("FacilityRelationship", 0, @wrong).errors.join
  end
end
