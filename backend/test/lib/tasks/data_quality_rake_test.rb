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

  test "correcting a state needs a person and a two-letter state" do
    Facility.create!(name: "Salem 1", nrc_docket: "05000272", state: "DE", facility_type: "power_reactor")

    assert_raises(SystemExit) { capture_io { correct_state("05000272", "NJ", by: "agent:verifier") } }
    assert_raises(SystemExit) { capture_io { correct_state("05000272", "New Jersey") } }
    assert_equal "DE", Facility.find_by(nrc_docket: "05000272").state
  end
end
