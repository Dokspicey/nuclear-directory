require "test_helper"

class CandidateTest < ActiveSupport::TestCase
  setup do
    @candidate = Candidate.create!(source: sources(:press_release), kind: "organization",
      payload: { "name" => "TerraPower", "domain" => "terrapower.com" }, quote: "TerraPower, founded by Bill Gates")
  end

  test "starts new" do
    assert @candidate.status_new?
    assert_includes Candidate.status_new, @candidate
    assert_equal "TerraPower", @candidate.payload["name"]
  end

  test "points at the fact it became once matched" do
    @candidate.update!(status: "matched", subject: organizations(:terrapower))
    assert_equal organizations(:terrapower), @candidate.reload.subject
  end

  test "can't be matched without a subject" do
    assert_not @candidate.update(status: "matched")
  end

  test "kind and status must be known values" do
    assert_not Candidate.new(source: sources(:nrc), kind: "gossip").valid?
    assert_not Candidate.new(source: sources(:nrc), kind: "facility", status: "maybe").valid?
  end
end
