# The daily crawl (#53), queued by config/recurring.yml in production: the
# whole pipeline for each source, one after the other, so EIA (which
# enriches NRC's units) always starts after NRC has finished. A source that
# fails doesn't stop the next one; the first error is raised at the end so
# the job shows as failed and reaches Sentry. If a source is already being
# run (from the console, say), the job waits and retries, like RunJob.
class DataQuality::DailyCrawlJob < ApplicationJob
  SOURCE_KINDS = %w[nrc_reactor_list eia_generators].freeze

  queue_as :data_quality
  limits_concurrency to: 1, key: "daily_crawl", duration: 6.hours
  retry_on DataQuality::Pipeline::AlreadyRunning, wait: 10.minutes, attempts: 30

  def perform
    errors = SOURCE_KINDS.filter_map do |source_kind|
      DataQuality::Pipeline.run(source_kind)
      nil
    rescue DataQuality::Pipeline::AlreadyRunning
      raise
    rescue StandardError => error
      error
    end
    raise errors.first if errors.any?
  end
end
