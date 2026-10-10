require "test_helper"

# Unpublishing and the audit trail (verification_events), through FactWriter
# the way the admin's publish actions (DataQuality::Review) use it.
class Directory::VerificationAuditTest < ActiveSupport::TestCase
  def write(...) = Directory::FactWriter.write(...)
  def history(record) = Directory::Lookup.verification_history(type: record.class.name, id: record.id)

  setup { @org = organizations(:terrapower) }

  test "every change of verification is recorded: who, when, from, to, why, and its context" do
    write(:organization, { id: @org.id }, verification: { status: "verified", by: "human:tosin", reason: "checked the source",
      context: { "candidate_id" => 12, "crawl_run_id" => 4 } })
    write(:organization, { id: @org.id }, verification: { status: "unpublished", by: "human:tosin", reason: "company asked" })

    latest, first = history(@org)
    assert_equal [ "verified", "unpublished", "human:tosin", "company asked" ], latest.to_h.values_at(:from_status, :to_status, :by, :reason)
    assert_equal [ "pending", "verified", { "candidate_id" => 12, "crawl_run_id" => 4 } ], first.to_h.values_at(:from_status, :to_status, :context)
    assert_kind_of Directory::VerificationEventRef, latest
    assert latest.at
  end

  test "re-applying the same decision records nothing new" do
    2.times { write(:organization, { id: @org.id }, verification: { status: "verified", by: "human:tosin" }) }
    assert_equal 1, history(@org).size
  end

  test "an unpublished fact is hidden, remembers who and when, and can be republished by a human" do
    @org.verify!(by: "human:tosin")
    @org.unpublish!(by: "human:tosin", reason: "outdated")

    assert @org.reload.unpublished?
    assert_not_includes Organization.verified, @org
    assert @org.human_reviewed?
    assert @org.verified_at

    assert write(:organization, { id: @org.id }, verification: { status: "verified", by: "human:tosin", reason: "fixed" }).ok?
    assert @org.reload.verified?
    assert_equal %w[verified unpublished verified], history(@org).reverse.map(&:to_status)
  end

  test "automated writers can't change an unpublished fact" do
    @org.unpublish!(by: "human:tosin")

    result = write(:organization, { id: @org.id, hq_city: "Bellevue" }, protect_human_verified: true,
      evidence: [ { source_id: sources(:nrc).id, quote: "x", found_by: "crawler" } ],
      verification: { status: "verified", by: "agent:verifier/x" })

    assert_not result.ok?
    assert_match(/was unpublished by human:tosin on \d{4}-\d{2}-\d{2}; not changed/, result.errors.join)
    assert_nil @org.reload.hq_city
    assert_empty @org.evidence
  end

  test "unknown verification keys are refused" do
    result = write(:organization, { id: @org.id }, verification: { status: "verified", by: "human:tosin", because: "x" })
    assert_match "unknown verification keys: because", result.errors.join
  end

  test "events can't be edited" do
    @org.verify!(by: "human:tosin")
    event = @org.verification_events.sole
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(reason: "rewritten") }
  end

  test "history is only for fact types" do
    assert_raises(ArgumentError) { Directory::Lookup.verification_history(type: "Source", id: 1) }
  end
end
