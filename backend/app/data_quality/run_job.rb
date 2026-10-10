# Runs the pipeline (or some stages) for a source kind in the background.
#   DataQuality::RunJob.perform_later("nrc_reactor_list")
#   DataQuality::RunJob.perform_later("nrc_reactor_list", only: "extract")
class DataQuality::RunJob < ApplicationJob
  queue_as :data_quality

  def perform(source_kind, only: nil)
    DataQuality::Pipeline.run(source_kind, only: only)
  end
end
