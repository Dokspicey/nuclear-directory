# Runs the pipeline (or some stages) for a source kind in the background.
#   DataQuality::RunJob.perform_later("nrc_reactor_list")
#   DataQuality::RunJob.perform_later("nrc_reactor_list", only: "extract")
#
# One job per source kind at a time: Solid Queue holds a second one back
# until the first finishes (Pipeline.run's lock also guards runs started
# outside jobs).
class DataQuality::RunJob < ApplicationJob
  queue_as :data_quality
  limits_concurrency to: 1, key: ->(source_kind, **) { source_kind }, duration: DataQuality::Pipeline::ABANDONED_AFTER

  def perform(source_kind, only: nil)
    DataQuality::Pipeline.run(source_kind, only: only)
  end
end
