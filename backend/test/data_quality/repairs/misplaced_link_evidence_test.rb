require "test_helper"

# The #226 repair against the real directory: a link candidate approved before
# its ends were resolved was merged onto an unrelated link, with its quote as
# that link's evidence. (Tests may use directory models.)
class DataQuality::Repairs::MisplacedLinkEvidenceTest < ActiveSupport::TestCase
  Repair = DataQuality::Repairs::MisplacedLinkEvidence
  BY = "human:tosin"
  QUOTE = "Farley 1 | 05000348 | NPF-2 | PWR | 18 miles E of Dothan, AL | Southern Nuclear Operating Co. | 2"

  setup do
    @farley = Facility.create!(name: "Farley 1", nrc_docket: "05000348", facility_type: "power_reactor")
    @cooper = Facility.create!(name: "Cooper", nrc_docket: "05000298", facility_type: "power_reactor")
    nppd = Organization.create!(name: "Nebraska Public Power District")
    @link = FacilityRelationship.create!(organization: nppd, facility: @cooper, relationship_type: "operates")
    @own = Evidence.create!(subject: @link, source: sources(:nrc), quote: "Cooper | 05000298 | NPPD", found_by: "crawler")
    @link.verify!(by: BY)
    @candidate = Candidate.create!(source: sources(:nrc), kind: "facility_relationship", quote: QUOTE, status: "merged",
      subject_type: "FacilityRelationship", subject_id: @link.id, reviewed_by: BY, reviewed_at: Time.current,
      payload: { "organization" => { "name" => "Southern Nuclear Operating Co." },
        "facility" => { "name" => "Farley 1", "nrc_docket" => "05000348" }, "relationship_type" => "operates" })
    @misplaced = Evidence.create!(subject: @link, source: sources(:nrc), quote: QUOTE, found_by: "crawler")
  end

  def run_repair(items = [ [ @candidate.id, @misplaced.id, @link.id ] ], dry_run: false) =
    Repair.call(items:, by: BY, dry_run:)

  test "a dry run checks and reports, and changes nothing" do
    outcome = run_repair(dry_run: true).sole

    assert_equal :would_repair, outcome.status
    assert_match "Southern Nuclear Operating Co. operates Farley 1", outcome.message
    assert Evidence.exists?(@misplaced.id)
    assert @candidate.reload.status_merged?
  end

  test "a dry run checks the evidence too, so a wrong evidence id is reported then, not at apply" do
    outcome = run_repair([ [ @candidate.id, @own.id, @link.id ] ], dry_run: true).sole

    assert_equal :skipped, outcome.status
    assert_match "isn't the source and quote given", outcome.message
  end

  test "removes the evidence from the link and reopens the candidate as new" do
    outcome = run_repair.sole

    assert_equal :repaired, outcome.status, outcome.message
    assert_equal [ @own.id ], @link.evidence.reload.ids
    assert @link.reload.verified?
    event = @link.verification_events.order(:created_at).last
    assert_equal BY, event.by
    assert_match "#226", event.reason
    assert_equal [ "#{sources(:nrc).url}: #{QUOTE}", nil ], event.changed_values["evidence"]

    @candidate.reload
    assert @candidate.status_new?
    assert_nil @candidate.subject_id
    assert_nil @candidate.reviewed_by
    assert_match "Reopened (#226)", @candidate.notes
  end

  test "a second run reports the item as already repaired" do
    run_repair

    assert_equal :already_repaired, run_repair.sole.status
    assert_equal [ @own.id ], @link.evidence.reload.ids
  end

  test "skips a candidate that is on its own plant's link" do
    southern = Organization.create!(name: "Southern Nuclear Operating Co.")
    right = FacilityRelationship.create!(organization: southern, facility: @farley, relationship_type: "operates")
    @candidate.update!(subject_id: right.id)

    outcome = run_repair([ [ @candidate.id, @misplaced.id, right.id ] ]).sole

    assert_equal :skipped, outcome.status
    assert_match "the candidate's own plant", outcome.message
    assert @candidate.reload.status_merged?
  end

  test "skips a candidate attached to a different link than listed" do
    outcome = run_repair([ [ @candidate.id, @misplaced.id, @link.id + 1 ] ]).sole

    assert_equal :skipped, outcome.status
    assert_match "not link", outcome.message
  end

  test "skips, and doesn't reopen the candidate, when the evidence isn't the candidate's quote" do
    outcome = run_repair([ [ @candidate.id, @own.id, @link.id ] ]).sole

    assert_equal :skipped, outcome.status
    assert_match "isn't the source and quote given", outcome.message
    assert_equal [ @own.id, @misplaced.id ].sort, @link.evidence.reload.ids.sort
    assert @candidate.reload.status_merged?
  end

  test "only a human runs it" do
    assert_raises(ArgumentError) { Repair.new(items: [], by: "agent:verifier") }
  end

  test "the #226 list names 24 distinct candidates and evidence rows" do
    assert_equal 24, Repair::ISSUE_226.map(&:first).uniq.size
    assert_equal 24, Repair::ISSUE_226.map(&:second).uniq.size
  end
end
