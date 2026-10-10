require "test_helper"
require "fugit"

# The daily crawl (#53): config/recurring.yml runs the whole pipeline once a
# day in production, NRC then EIA.
class DataQuality::DailyCrawlScheduleTest < ActiveSupport::TestCase
  def task = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production").fetch("daily_crawl")

  # Runs the job with Pipeline.run stubbed: records each call, and raises
  # what `fail` gives for a source kind.
  def run_daily(fail: {})
    ran = []
    pipeline = DataQuality::Pipeline.singleton_class
    original = pipeline.instance_method(:run)
    pipeline.define_method(:run) do |source_kind, only: nil, **|
      ran << [ source_kind, only ]
      raise fail[source_kind] if fail[source_kind]
      []
    end
    error = begin
      DataQuality::DailyCrawlJob.new.perform
      nil
    rescue StandardError => raised
      raised
    end
    [ ran, error ]
  ensure
    pipeline.define_method(:run, original)
  end

  test "Solid Queue accepts the schedule, and every source it runs has a plug-in" do
    recurring = SolidQueue::RecurringTask.from_configuration("daily_crawl", **task.symbolize_keys)

    assert recurring.valid?, recurring.errors.full_messages.to_sentence
    assert_equal "DataQuality::DailyCrawlJob", task["class"]
    DataQuality::DailyCrawlJob::SOURCE_KINDS.each { |kind| assert DataQuality::Plugin.for(kind), "#{kind} has a plug-in" }
  end

  test "it runs once a day at 3am Eastern, through the change back from daylight saving time" do
    schedule = Fugit.parse(task["schedule"])
    times = 5.times.each_with_object([ schedule.next_time(Time.utc(2026, 10, 30, 12)).to_t ]) do |_, list|
      list << schedule.next_time(list.last).to_t
    end
    local = times.map { |time| time.in_time_zone("America/New_York") }

    assert_equal (Date.new(2026, 10, 31)..Date.new(2026, 11, 5)).to_a, local.map(&:to_date)
    assert_equal [ 3 ] * 6, local.map(&:hour)
  end

  test "it runs the whole pipeline for NRC, then for EIA" do
    ran, error = run_daily

    assert_nil error
    assert_equal [ [ "nrc_reactor_list", nil ], [ "eia_generators", nil ] ], ran
  end

  test "a failing source doesn't stop the next one, and the job still fails" do
    ran, error = run_daily(fail: { "nrc_reactor_list" => RuntimeError.new("NRC page changed") })

    assert_equal %w[nrc_reactor_list eia_generators], ran.map(&:first)
    assert_equal "NRC page changed", error.message
  end

  test "a source already being run stops the job, so it retries instead of running EIA alongside NRC" do
    ran, error = run_daily(fail: { "nrc_reactor_list" => DataQuality::Pipeline::AlreadyRunning.new })

    assert_equal %w[nrc_reactor_list], ran.map(&:first)
    assert_kind_of DataQuality::Pipeline::AlreadyRunning, error
  end
end
