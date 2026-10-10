# Runs the pipeline (or some stages) for a source kind in the background.
#   DataQuality::RunJob.perform_later("nrc_reactor_list")
#   DataQuality::RunJob.perform_later("nrc_reactor_list", only: "extract")
#
# One job per source kind at a time: Solid Queue holds a second one back
# until the first finishes (Pipeline.run's lock also guards runs started
# outside jobs). Solid Queue's hold expires after `duration`, so it's set
# well above any real run; and if a job still finds a run in progress
# (released early, or a run started from the console), it waits and
# retries instead of being lost.
class DataQuality::RunJob < ApplicationJob
  queue_as :data_quality
  limits_concurrency to: 1, key: ->(source_kind, **) { source_kind }, duration: 6.hours
  retry_on DataQuality::Pipeline::AlreadyRunning, wait: 10.minutes, attempts: 30

  def perform(source_kind, only: nil)
    DataQuality::Pipeline.run(source_kind, only: only)
  end
end
