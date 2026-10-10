# The daily crawl (#53), queued by config/recurring.yml in production: the
# whole pipeline for each source, one after the other, so EIA (which
# enriches NRC's units) always starts after NRC has finished. A source that
# fails doesn't stop the next one; the first error is raised at the end so
# the job shows as failed and reaches Sentry.
#
# If a source is already being run (from the console, say), the job queues
# itself again for that source and the ones after it, so a retry never
# repeats a source that already ran, and still fails for any that failed.
class DataQuality::DailyCrawlJob < ApplicationJob
  SOURCE_KINDS = %w[nrc_reactor_list eia_generators].freeze
  RETRY_WAIT = 10.minutes
  ATTEMPTS = 30

  queue_as :data_quality
  limits_concurrency to: 1, key: "daily_crawl", duration: 6.hours

  def perform(source_kinds = SOURCE_KINDS, attempt: 1)
    errors = []
    source_kinds.each_with_index do |source_kind, index|
      DataQuality::Pipeline.run(source_kind)
    rescue DataQuality::Pipeline::AlreadyRunning
      raise if attempt >= ATTEMPTS
      self.class.set(wait: RETRY_WAIT).perform_later(source_kinds.drop(index), attempt: attempt + 1)
      break
    rescue StandardError => error
      errors << error
    end
    raise errors.first if errors.any?
  end
end
