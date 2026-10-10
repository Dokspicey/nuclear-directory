require "test_helper"
require "fugit"

# The daily crawl (#53): config/recurring.yml runs the whole pipeline once a
# day in production, NRC then EIA.
class DataQuality::DailyCrawlScheduleTest < ActiveSupport::TestCase
  def tasks = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")

  def first_run(task) = Fugit.parse(task.fetch("schedule")).next_time(Time.utc(2026, 10, 11, 12)).to_t

  test "each source runs its whole pipeline once a day at a quiet US hour, as Solid Queue accepts" do
    { "daily_nrc_reactor_list" => [ "nrc_reactor_list", 3 ], "daily_eia_generators" => [ "eia_generators", 4 ] }.each do |key, (kind, hour)|
      task = tasks.fetch(key)
      recurring = SolidQueue::RecurringTask.from_configuration(key, **task.symbolize_keys)

      assert recurring.valid?, "#{key}: #{recurring.errors.full_messages.to_sentence}"
      assert_equal [ "DataQuality::RunJob", [ kind ] ], [ task["class"], task["args"] ]
      assert DataQuality::Plugin.for(kind), "#{kind} has a plug-in"

      schedule = Fugit.parse(task["schedule"])
      times = 3.times.each_with_object([ first_run(task) ]) { |_, list| list << schedule.next_time(list.last).to_t }
      assert_equal [ 1.day ] * 3, times.each_cons(2).map { |a, b| b - a }, "#{key}: once a day"
      assert_equal hour, times.first.in_time_zone("America/New_York").hour, "#{key}: at #{hour}am Eastern"
    end
  end

  test "EIA runs after NRC, since its rows enrich NRC's units" do
    assert first_run(tasks.fetch("daily_eia_generators")) > first_run(tasks.fetch("daily_nrc_reactor_list"))
  end

  test "the scheduled job runs the whole pipeline for its source" do
    ran = []
    pipeline = DataQuality::Pipeline.singleton_class
    original = pipeline.instance_method(:run)
    pipeline.define_method(:run) { |source_kind, only: nil, **| ran << [ source_kind, only ]; [] }

    DataQuality::RunJob.perform_now(*tasks.fetch("daily_nrc_reactor_list")["args"])

    assert_equal [ [ "nrc_reactor_list", nil ] ], ran, "every stage, not just one"
  ensure
    pipeline.define_method(:run, original)
  end
end
