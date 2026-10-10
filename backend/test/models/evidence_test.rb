require "test_helper"

class EvidenceTest < ActiveSupport::TestCase
  setup { @org = organizations(:terrapower) }

  def add_evidence(source, confidence, subject: @org)
    Evidence.create!(subject: subject, source: sources(source), found_by: "crawler", confidence: confidence,
      quote: "TerraPower is developing the Natrium reactor.")
  end

  test "a fact with one piece of evidence takes its confidence" do
    add_evidence(:press_release, 0.6)
    assert_equal 0.6, @org.reload.confidence
  end

  test "confidence is the strongest piece of evidence" do
    add_evidence(:press_release, 0.4)
    add_evidence(:press_release_same_domain, 0.7)
    assert_equal 0.7, @org.reload.confidence
  end

  test "two independent sources bump confidence" do
    add_evidence(:press_release, 0.6)
    add_evidence(:nrc, 0.5)
    assert_equal 0.7, @org.reload.confidence
  end

  test "pages on the same domain don't count as independent" do
    add_evidence(:press_release, 0.6)
    add_evidence(:press_release_same_domain, 0.6)
    assert_equal 0.6, @org.reload.confidence
  end

  test "confidence never goes above 1" do
    add_evidence(:press_release, 0.95)
    add_evidence(:nrc, 0.95)
    assert_equal 1, @org.reload.confidence
  end

  test "removing evidence lowers confidence again" do
    add_evidence(:press_release, 0.6)
    nrc = add_evidence(:nrc, 0.9)
    nrc.destroy!
    assert_equal 0.6, @org.reload.confidence
  end

  test "evidence without a confidence leaves the fact unscored" do
    Evidence.create!(subject: @org, source: sources(:nrc), found_by: "human")
    assert_nil @org.reload.confidence
  end

  test "works on any fact table" do
    rel = Relationship.create!(from_organization: organizations(:westinghouse), to_organization: @org,
      relationship_type: "supplies")
    add_evidence(:nrc, 0.8, subject: rel)
    assert_equal 0.8, rel.reload.confidence
    assert_equal 1, rel.evidence.count
  end

  test "deleting a fact deletes its evidence" do
    add_evidence(:nrc, 0.8)
    assert_difference("Evidence.count", -1) { @org.destroy! }
  end

  test "found_by must be a known value" do
    assert_not Evidence.new(subject: @org, source: sources(:nrc), found_by: "rumour").valid?
  end
end
