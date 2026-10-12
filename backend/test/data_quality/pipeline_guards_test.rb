require "test_helper"
require_relative "support/fake_directory"
require_relative "support/dummy_plugin"

# One run per source kind at a time, and runs that were cut off don't stay
# "running" forever.
class DataQuality::PipelineGuardsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def run_crawl = DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, directory: FakeDirectory.client, only: "crawl")

  # A separate Postgres session, like another worker would have. (Tests pin
  # Rails' pool to one connection, and a session can always re-take its
  # own advisory lock.)
  def other_session
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    PG.connect(host: config[:host], port: config[:port], dbname: config[:database],
      user: config[:username], password: config[:password])
  end

  # Releases the session's locks before closing it: close only sends
  # Terminate, and the server can hold the lock a moment longer, long enough
  # for the next test to find it taken.
  def close_session(session)
    return unless session

    session.exec("SELECT pg_advisory_unlock_all()")
    session.close
  end

  test "a second run of the same source kind stops while the first holds the lock" do
    key = Zlib.crc32("data_quality:dummy")
    other = other_session
    assert_equal "t", other.exec("SELECT pg_try_advisory_lock(#{key})").getvalue(0, 0), "another session takes the lock"

    error = assert_raises(DataQuality::Pipeline::AlreadyRunning) { run_crawl }
    assert_match "dummy pipeline run is already in progress", error.message
    assert_equal 0, CrawlRun.where(source_kind: "dummy").count, "nothing ran"
  ensure
    close_session(other)
  end

  test "the lock is free for other sessions once a run finishes" do
    run_crawl

    other = other_session
    assert_equal "t", other.exec("SELECT pg_try_advisory_lock(#{Zlib.crc32('data_quality:dummy')})").getvalue(0, 0)
  ensure
    close_session(other)
  end

  test "the lock is released after a run, even a failed one" do
    run_crawl
    run_crawl

    broken = DummyPlugin.new
    def broken.crawl(_run) = raise("site is down")
    assert_raises(RuntimeError) { DataQuality::Pipeline.run("dummy", plugin: broken, only: "crawl") }

    assert run_crawl.sole.succeeded?, "a run after the failure still gets the lock"
  end

  test "runs a dead process left running are marked failed when the next run starts, however recent" do
    stuck = CrawlRun.create!(stage: "extract", source_kind: "dummy", started_at: 3.hours.ago)
    recent = CrawlRun.create!(stage: "crawl", source_kind: "dummy", started_at: 1.minute.ago)
    other_kind = CrawlRun.create!(stage: "extract", source_kind: "nrc_reactor_list", started_at: 3.hours.ago)

    run_crawl

    [ stuck, recent ].each do |run|
      assert run.reload.failed?, "nothing else can be running while this run holds the lock"
      assert_equal DataQuality::Pipeline::ABANDONED, run.error
      assert run.finished_at
    end
    assert other_kind.reload.running?, "another source kind is swept by its own runs"
  end

  test "the sweep for every kind leaves alone a kind that's mid-run" do
    dead = CrawlRun.create!(stage: "crawl", source_kind: "dummy", started_at: 1.minute.ago)
    working = CrawlRun.create!(stage: "crawl", source_kind: "nrc_reactor_list", started_at: 1.minute.ago)
    other = other_session
    other.exec("SELECT pg_advisory_lock(#{Zlib.crc32('data_quality:nrc_reactor_list')})")

    assert_equal 1, DataQuality::Pipeline.sweep_all_abandoned

    assert dead.reload.failed?
    assert working.reload.running?, "its lock is held, so it's really running"
  ensure
    close_session(other)
  end

  test "the background job allows one run per source kind" do
    job = DataQuality::RunJob.new("nrc_reactor_list", only: "crawl")

    assert_equal 1, DataQuality::RunJob.concurrency_limit
    assert_includes job.concurrency_key, "nrc_reactor_list"
    assert_not_equal job.concurrency_key, DataQuality::RunJob.new("dummy").concurrency_key
    assert_operator DataQuality::RunJob.concurrency_duration, :>, 1.hour,
      "the hold outlasts any real run"
  end

  test "a job that finds a run in progress waits and retries instead of being lost" do
    other = other_session
    other.exec("SELECT pg_advisory_lock(#{Zlib.crc32('data_quality:nrc_reactor_list')})")

    assert_enqueued_with(job: DataQuality::RunJob, args: [ "nrc_reactor_list" ]) do
      DataQuality::RunJob.perform_now("nrc_reactor_list")
    end
    assert_equal 0, CrawlRun.where(source_kind: "nrc_reactor_list").count, "nothing ran while the other run held the lock"
  ensure
    close_session(other)
  end
end
