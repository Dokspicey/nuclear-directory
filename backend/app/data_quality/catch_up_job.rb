# Hourly, in production (config/recurring.yml). When the instance restarts
# mid-run (#188: it ran out of memory during the EIA crawl), the run is left
# "running" and Solid Queue drops the job without retrying it. This job:
# - marks runs left "running" by a process that died as failed, without
#   waiting for that source's next run (Pipeline.sweep_all_abandoned)
# - queues today's daily crawl again, from the first source whose run today
#   was cut off that way, or that hasn't run at all by CATCH_UP_AFTER
#
# Each source is caught up at most once a day, so a source that keeps
# killing the instance waits for a person instead of looping. Fetching is
# still once a day per source (Snapshot), so a catch-up re-uses what was
# already fetched today.
class DataQuality::CatchUpJob < ApplicationJob
  ZONE = "America/New_York"
  DAILY_AT = 3 # config/recurring.yml's daily_crawl
  # Late enough that the daily crawl has started.
  CATCH_UP_AFTER = 4
  # Remembers which sources were caught up today. The app's cache is
  # database-backed in production (Solid Cache), so it survives the restart
  # that caused the catch-up; tests use their own, since the test cache
  # keeps nothing.
  CACHE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

  queue_as :data_quality
  limits_concurrency to: 1, key: "data_quality_catch_up"

  def perform(now: Time.current)
    DataQuality::Pipeline.sweep_all_abandoned

    local = now.in_time_zone(ZONE)
    return if local.hour < CATCH_UP_AFTER

    since = local.beginning_of_day.change(hour: DAILY_AT)
    kinds = DataQuality::DailyCrawlJob::SOURCE_KINDS
    first = kinds.index { |kind| needs_catching_up?(kind, since) }
    return unless first

    behind = kinds.drop(first)
    behind.each { |kind| caught_up!(kind, local.to_date) }
    DataQuality::DailyCrawlJob.perform_later(behind)
  end

  private
    def needs_catching_up?(kind, since)
      return false if caught_up?(kind, since.to_date)

      last = CrawlRun.where(source_kind: kind, started_at: since..).order(:started_at).last
      last.nil? || (last.failed? && last.error == DataQuality::Pipeline::ABANDONED)
    end

    def caught_up?(kind, date) = CACHE.exist?(marker(kind, date))
    def caught_up!(kind, date) = CACHE.write(marker(kind, date), true, expires_in: 2.days)
    def marker(kind, date) = "data_quality:catch_up:#{kind}:#{date.iso8601}"
end
