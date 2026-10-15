require "test_helper"
require "rake"

class DataQualityRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("data_quality:rerun")
  end

  test "rerun queues extract, match and verify from the stored snapshot, without fetching (#188)" do
    assert_output(/Queued extract, match, verify for nrc_reactor_list from its stored snapshot/) do
      Rake::Task["data_quality:rerun"].execute(Rake::TaskArguments.new([ :source_kind ], [ "nrc_reactor_list" ]))
    end

    assert_enqueued_with job: DataQuality::RunJob, args: [ "nrc_reactor_list", { only: %w[extract match verify] } ]
    assert_not_includes DataQuality::Pipeline::FROM_SNAPSHOT, "crawl"
  end

  test "rerun refuses a source kind with no plug-in, before queueing anything" do
    assert_raises(DataQuality::Plugin::UnknownSourceKind) do
      Rake::Task["data_quality:rerun"].execute(Rake::TaskArguments.new([ :source_kind ], [ "no_such_source" ]))
    end
    assert_no_enqueued_jobs
  end

  def correct_state(docket, state, by: "human:tosin")
    ENV["BY"] = by
    Rake::Task["data_quality:correct_unit_state"].execute(Rake::TaskArguments.new(%i[nrc_docket state], [ docket, state ]))
  ensure
    ENV.delete("BY")
  end

  test "correcting a unit's state is a recorded human decision, with its reason (#197)" do
    hope_creek = Facility.create!(name: "Hope Creek 1", nrc_docket: "05000354", state: "DE", facility_type: "power_reactor")
    hope_creek.evidence.create!(source: sources(:nrc), quote: "Hope Creek 1 | 05000354", found_by: "human")
    hope_creek.verify!(by: "human:tosin")

    assert_output(/Hope Creek 1 \(05000354\): state NJ, recorded as human:tosin/) { correct_state("05000354", "NJ") }

    assert_equal [ "NJ", "verified" ], [ hope_creek.reload.state, hope_creek.verification_status ]
    event = Directory::Lookup.verification_history(type: "Facility", id: hope_creek.id).first
    assert_match "State corrected from DE to NJ", event.reason
    assert_equal "human:tosin", event.by
  end

  test "correcting a state needs a named person and a two-letter state" do
    salem = Facility.create!(name: "Salem 1", nrc_docket: "05000272", state: "DE", facility_type: "power_reactor")
    salem.evidence.create!(source: sources(:nrc), quote: "Salem 1 | 05000272", found_by: "human")
    salem.verify!(by: "human:tosin")

    [ [ "NJ", "agent:verifier" ], [ "NJ", "human:" ], [ "New Jersey", "human:tosin" ] ].each do |state, by|
      _, err = capture_io { assert_raises(SystemExit) { correct_state("05000272", state, by:) } }
      assert_match "Usage:", err, "#{state} as #{by}"
    end
    assert_equal "DE", salem.reload.state
  end

  test "only a published unit's state is corrected; a pending one isn't published as a side effect" do
    pending = Facility.create!(name: "Salem 2", nrc_docket: "05000311", state: "DE", facility_type: "power_reactor")
    pending.evidence.create!(source: sources(:nrc), quote: "Salem 2 | 05000311", found_by: "human")

    _, err = capture_io { assert_raises(SystemExit) { correct_state("05000311", "NJ") } }

    assert_match "isn't published (pending)", err
    assert_equal [ "DE", "pending" ], [ pending.reload.state, pending.verification_status ]
  end

  def reopen(**env)
    env.each { |key, value| ENV[key.to_s] = value }
    Rake::Task["data_quality:reopen"].execute
  ensure
    env.each_key { |key| ENV.delete(key.to_s) }
  end

  test "reopen puts rejected candidates back, as the named person, and says which it couldn't (#228)" do
    source = Source.create!(url: "https://www.eia.gov/test/reopen.xlsx", source_kind: "eia_generators", crawl_status: "ok")
    rejected = Candidate.create!(source:, kind: "facility", quote: "row", status: "rejected", payload: { "identify" => { "name" => "Salem" } })
    open = Candidate.create!(source:, kind: "facility", quote: "row", status: "needs_review", payload: { "identify" => { "name" => "Salem" } })

    assert_output(/Candidate #{rejected.id}: reopened\nCandidate #{open.id}: it isn't rejected\nCandidate 0: not found\n.*data_quality:rerun\[eia_generators\]/) do
      reopen(BY: "human:tosin", REASON: "rejected while the state was wrong", IDS: "#{rejected.id},#{open.id},0")
    end
    assert_equal [ "new", "human:tosin" ], [ rejected.reload.status, rejected.reopenings.sole["by"] ]
    out, = capture_io { reopen(BY: "human:tosin", REASON: "again", IDS: "#{open.id},0") }
    assert_no_match "Next:", out, "nothing reopened, nothing to rerun"

    assert_raises(SystemExit) { capture_io { reopen(BY: "human:tosin", IDS: rejected.id.to_s) } }
    assert_raises(SystemExit) { capture_io { reopen(BY: "tosin", REASON: "why", IDS: rejected.id.to_s) } }
  end

  def confirm_identical(**env)
    env.each { |key, value| ENV[key.to_s] = value }
    Rake::Task["data_quality:confirm_identical"].execute
  ensure
    env.each_key { |key| ENV.delete(key.to_s) }
  end

  test "confirm_identical is a dry run until APPLY=1, and says why each one it leaves stays open (#240)" do
    # A kind with no plug-in: only each claim's own quote counts as still in the source.
    source = Source.create!(url: "https://example.com/test/units", source_kind: "units_by_hand", crawl_status: "ok")
    unit = Facility.create!(name: "Zephyr Point 1", nrc_docket: "05099001", status: "operating", verification_status: "verified",
      verified_by: "human:tosin")
    Evidence.create!(subject: unit, source:, quote: "row", found_by: "crawler")
    same = Candidate.create!(source:, kind: "facility", quote: "row", status: "matched", subject: unit,
      payload: { "name" => "Zephyr Point 1", "nrc_docket" => "05099001", "status" => "operating" })
    changed = Candidate.create!(source:, kind: "facility", quote: "row", status: "matched", subject: unit,
      payload: { "name" => "Zephyr Point 1", "nrc_docket" => "05099001", "status" => "shut_down" })

    assert_output(/candidate #{changed.id}\s+stays open: it differs: status operating → shut_down\n1 would be confirmed, 1 stay open\nDry run/) do
      confirm_identical(BY: "human:tosin")
    end
    assert same.reload.status_matched?

    assert_output(/1 confirmed, 1 stay open/) { confirm_identical(BY: "human:tosin", APPLY: "1") }
    assert same.reload.status_confirmed?
    assert_raises(SystemExit) { capture_io { confirm_identical(BY: "human:") } }
    assert_raises(SystemExit) { capture_io { confirm_identical(BY: "human:tosin", IDS: "x") } }
  end
end
