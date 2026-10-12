require "test_helper"

# The hourly catch-up (#188): a run cut off by a restart is marked failed,
# and today's daily crawl is queued again once, from that source on.
class DataQuality::CatchUpJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Job = DataQuality::CatchUpJob
  NOW = Time.find_zone("America/New_York").local(2026, 10, 12, 6, 30)
  TODAY_3AM = NOW.change(hour: 3)

  setup { Job::CACHE.clear }

  def catch_up(at: NOW) = Job.new.perform(now: at)
  def make_run(kind, stage, status, at: TODAY_3AM + 1.minute, error: nil)
    CrawlRun.create!(source_kind: kind, stage:, status:, started_at: at, error:)
  end

  test "an NRC run cut off by a restart is failed, and the crawl is queued again for NRC then EIA, once" do
    make_run("nrc_reactor_list", "crawl", "succeeded")
    cut_off = make_run("nrc_reactor_list", "extract", "running", at: TODAY_3AM + 2.minutes)

    catch_up

    assert_equal DataQuality::Pipeline::ABANDONED, cut_off.reload.error
    assert_enqueued_with job: DataQuality::DailyCrawlJob, args: [ %w[nrc_reactor_list eia_generators] ]

    clear_enqueued_jobs
    catch_up(at: NOW + 1.hour)
    # Once a day, so a source that keeps failing waits for a person.
    assert_no_enqueued_jobs only: DataQuality::DailyCrawlJob
  end

  test "only EIA is queued again when NRC finished" do
    make_run("nrc_reactor_list", "verify", "succeeded")
    make_run("eia_generators", "crawl", "running", at: TODAY_3AM + 5.minutes)

    catch_up

    assert_enqueued_with job: DataQuality::DailyCrawlJob, args: [ %w[eia_generators] ]
  end

  test "the night of 12 Oct: NRC fetched, then failed on the key; EIA cut off. Only EIA is queued again" do
    make_run("nrc_reactor_list", "crawl", "succeeded")
    make_run("nrc_reactor_list", "extract", "failed", at: TODAY_3AM + 2.minutes,
      error: "OpenRouter rejected the API key: check OPENROUTER_API_KEY (OpenRouter 401: User not found.)")
    make_run("eia_generators", "crawl", "running", at: TODAY_3AM + 3.minutes)

    catch_up

    # NRC isn't fetched again today: it goes through data_quality:rerun, from its snapshot.
    assert_enqueued_jobs 1, only: DataQuality::DailyCrawlJob
    assert_enqueued_with job: DataQuality::DailyCrawlJob, args: [ %w[eia_generators] ]
  end

  test "a restart between stages, with no run left running, is caught up too" do
    make_run("nrc_reactor_list", "verify", "succeeded")
    make_run("eia_generators", "crawl", "succeeded", at: TODAY_3AM + 3.minutes) # extract never started

    catch_up

    assert_enqueued_with job: DataQuality::DailyCrawlJob, args: [ %w[eia_generators] ]
  end

  test "if queueing fails, nothing is remembered, so the next hour tries again" do
    failing = DataQuality::DailyCrawlJob.singleton_class
    original = failing.instance_method(:perform_later)
    failing.define_method(:perform_later) { |*| raise ActiveJob::EnqueueError, "queue unavailable" }
    assert_raises(ActiveJob::EnqueueError) { catch_up }
    failing.define_method(:perform_later, original)

    catch_up(at: NOW + 1.hour)

    assert_enqueued_with job: DataQuality::DailyCrawlJob, args: [ %w[nrc_reactor_list eia_generators] ]
  ensure
    failing.define_method(:perform_later, original)
  end

  test "a daily crawl that never started is queued after 4am" do
    catch_up(at: NOW.change(hour: 3, min: 30))
    assert_no_enqueued_jobs only: DataQuality::DailyCrawlJob

    catch_up
    assert_enqueued_with job: DataQuality::DailyCrawlJob, args: [ %w[nrc_reactor_list eia_generators] ]
  end

  test "an ordinary failure, like a refused key, waits for a person" do
    make_run("nrc_reactor_list", "extract", "failed", error: "OpenRouter rejected the API key: check OPENROUTER_API_KEY")
    make_run("eia_generators", "verify", "succeeded")

    catch_up

    assert_no_enqueued_jobs only: DataQuality::DailyCrawlJob
  end

  test "yesterday's runs don't count for today" do
    make_run("nrc_reactor_list", "verify", "succeeded", at: TODAY_3AM - 1.day)
    make_run("eia_generators", "verify", "succeeded", at: TODAY_3AM - 1.day)

    catch_up

    assert_enqueued_with job: DataQuality::DailyCrawlJob, args: [ %w[nrc_reactor_list eia_generators] ]
  end

  test "runs hourly in production" do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "data_quality_catch_up")
    recurring = SolidQueue::RecurringTask.from_configuration("data_quality_catch_up", **task.symbolize_keys)

    assert recurring.valid?, recurring.errors.full_messages.to_sentence
    assert_equal "DataQuality::CatchUpJob", task["class"]
  end
end
