# Runs stages for one source kind, in order:
#   crawl → extract → match → verify (publish or review)
# Each stage reads its input from the database and writes its output back,
# so any stage can be rerun alone: Pipeline.run("nrc_reactor_list", only: "match").
class DataQuality::Pipeline
  STAGES = {
    "crawl" => DataQuality::Stages::Crawl,
    "extract" => DataQuality::Stages::Extract,
    "match" => DataQuality::Stages::Match,
    "verify" => DataQuality::Stages::Verify
  }.freeze

  # Returns the CrawlRun of each stage that ran. Stops at the first stage
  # that fails (its run is marked failed and the error is raised).
  def self.run(source_kind, only: nil, plugin: DataQuality::Plugin.for(source_kind),
    directory: DataQuality::DirectoryClient.new, verifier: nil)
    stage_names = only ? Array(only).map(&:to_s) : STAGES.keys
    unknown = stage_names - STAGES.keys
    raise ArgumentError, "Unknown stage(s): #{unknown.join(', ')}" if unknown.any?

    stage_names.map do |name|
      options = { plugin: plugin, directory: directory }
      options[:verifier] = verifier if name == "verify" && verifier
      STAGES.fetch(name).call(**options)
    end
  end
end
