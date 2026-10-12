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
end
