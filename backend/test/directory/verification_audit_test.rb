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

  test "an event records the values the same write changed, before and after" do
    @org.update!(hq_state: "DE")
    write(:organization, { id: @org.id, hq_state: "WA", hq_city: "Bellevue" },
      verification: { status: "verified", by: "human:tosin", reason: "approved the crawl's HQ" })

    event = history(@org).first
    assert_equal({ "hq_state" => [ "DE", "WA" ], "hq_city" => [ nil, "Bellevue" ] }, event.changed_values)
  end

  test "a human editing values without changing the decision is recorded too" do
    @org.verify!(by: "human:tosin")
    write(:organization, { id: @org.id, hq_city: "Bellevue" }, verification: { status: "verified", by: "human:tosin" })

    latest = history(@org).first
    assert_equal [ "verified", "verified", { "hq_city" => [ nil, "Bellevue" ] } ],
      latest.to_h.values_at(:from_status, :to_status, :changed_values)
  end

  test "write_many approves a batch in one transaction, each audited, failures kept separate" do
    other = organizations(:westinghouse)
    results = Directory::FactWriter.write_many([
      { kind: :organization, attributes: { id: @org.id }, verification: { status: "verified", by: "human:tosin", reason: "bulk" } },
      { kind: :organization, attributes: { id: other.id, status: "bogus" }, verification: { status: "verified", by: "human:tosin" } },
      { kind: :organization, attributes: { id: other.id }, verification: { status: "verified", by: "human:tosin", reason: "bulk" } }
    ])

    assert_equal [ true, false, true ], results.map(&:ok?)
    assert [ @org, other ].all? { |o| o.reload.verified? }
    assert_equal [ "bulk", "bulk" ], [ history(@org).first.reason, history(other).first.reason ]
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

  test "only a human unpublishes, or reopens a closed decision" do
    assert_raises(ActiveRecord::RecordInvalid) { @org.unpublish!(by: "agent:verifier/x") }

    @org.reject!(by: "agent:verifier/x") # the pipeline retiring its own proposal
    assert_raises(ActiveRecord::RecordInvalid) { @org.verify!(by: "agent:verifier/x") }
    unprotected = write(:organization, { id: @org.id }, verification: { status: "verified", by: "agent:verifier/x" })
    assert_match "was rejected by agent:verifier/x", unprotected.errors.join

    @org.reload.verify!(by: "human:tosin")
    assert @org.reload.verified?
  end

  test "a bare status update names no one, so it can't reopen a human's rejection" do
    @org.reject!(by: "human:tosin")

    assert_raises(ActiveRecord::RecordInvalid) { @org.reload.update!(verification_status: "verified") }
    assert @org.reload.rejected?
  end

  test "any decision on an existing fact must say who makes it, so no event is misattributed" do
    @org.verify!(by: "human:tosin")

    error = assert_raises(ActiveRecord::RecordInvalid) { @org.reload.update!(verification_status: "pending") }
    assert_match "needs who decided", error.message
    assert_equal 1, history(@org).size
  end

  test "an agent repeating a closed decision can't edit the fact" do
    @org.reject!(by: "agent:verifier/x")

    result = write(:organization, { id: @org.id, hq_city: "Bellevue" }, verification: { status: "rejected", by: "agent:verifier/x" })
    assert_not result.ok?
    assert_nil @org.reload.hq_city
  end

  test "write_many fails a write missing its kind or attributes, not the batch" do
    results = Directory::FactWriter.write_many([
      { attributes: { id: @org.id } },
      { kind: :organization, attributes: { id: @org.id }, verification: { status: "verified", by: "human:tosin" } }
    ])

    assert_equal [ false, true ], results.map(&:ok?)
    assert_match "missing write keys: kind", results.first.errors.join
  end

  test "write_many fails a write with a misspelled key instead of dropping it" do
    results = Directory::FactWriter.write_many([
      { kind: :organization, attributes: { id: @org.id }, verfication: { status: "verified", by: "human:tosin" } },
      { kind: :organization, attributes: { id: @org.id }, verification: { status: "verified", by: "human:tosin" } }
    ])

    assert_equal [ false, true ], results.map(&:ok?)
    assert_match "unknown write keys: verfication", results.first.errors.join
  end

  test "events can't be edited" do
    @org.verify!(by: "human:tosin")
    event = @org.verification_events.sole
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(reason: "rewritten") }
  end

  test "a decision must say who made it" do
    result = write(:organization, { id: @org.id }, verification: { status: "verified" })

    assert_match "verification needs by:", result.errors.join
    assert @org.reload.pending?
    assert_raises(ActiveRecord::NotNullViolation) do
      VerificationEvent.insert!({ subject_type: "Organization", subject_id: @org.id, to_status: "verified", created_at: Time.current })
    end
  end

  test "the same decision again keeps its date, so the date matches the history" do
    @org.verify!(by: "human:tosin")
    decided_at = @org.reload.verified_at

    travel 1.day do
      @org.verify!(by: "human:tosin")
    end

    assert_equal decided_at, @org.reload.verified_at
    assert_equal 1, history(@org).size
  end

  test "deleting a fact keeps its history" do
    @org.verify!(by: "human:tosin")
    id = @org.id
    @org.destroy!

    assert_equal [ "verified" ], VerificationEvent.where(subject_type: "Organization", subject_id: id).pluck(:to_status)
    assert_raises(ActiveRecord::ReadOnlyRecord) { VerificationEvent.find_by!(subject_id: id).destroy! }
  end

  test "history is only for fact types" do
    assert_raises(ArgumentError) { Directory::Lookup.verification_history(type: "Source", id: 1) }
  end
end
