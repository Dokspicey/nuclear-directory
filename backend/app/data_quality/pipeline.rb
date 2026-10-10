# Runs stages for one source kind, in order:
#   crawl → extract → match → verify (publish or review)
# Each stage reads its input from the database and writes its output back,
# so any stage can be rerun alone: Pipeline.run("nrc_reactor_list", only: "match").
#
# Only one run per source kind at a time: a Postgres advisory lock is held
# for the whole run, so a second run (a manual one during the scheduled
# one, say) stops with AlreadyRunning instead of racing the first. Each run
# starts by marking runs left "running" for too long as failed.
class DataQuality::Pipeline
  STAGES = {
    "crawl" => DataQuality::Stages::Crawl,
    "extract" => DataQuality::Stages::Extract,
    "match" => DataQuality::Stages::Match,
    "verify" => DataQuality::Stages::Verify
  }.freeze

  # A run still "running" after this long was cut off (a stopped worker,
  # a crash) and will never finish.
  ABANDONED_AFTER = 2.hours

  class AlreadyRunning < StandardError; end

  # Returns the CrawlRun of each stage that ran. Stops at the first stage
  # that fails (its run is marked failed and the error is raised).
  def self.run(source_kind, only: nil, plugin: DataQuality::Plugin.for(source_kind),
    directory: DataQuality::DirectoryClient.new, verifier: nil)
    stage_names = only ? Array(only).map(&:to_s) : STAGES.keys
    unknown = stage_names - STAGES.keys
    raise ArgumentError, "Unknown stage(s): #{unknown.join(', ')}" if unknown.any?

    with_lock(plugin.source_kind) do
      sweep_abandoned(plugin.source_kind)

      stage_names.map do |name|
        options = { plugin: plugin, directory: directory }
        options[:verifier] = verifier if name == "verify" && verifier
        STAGES.fetch(name).call(**options)
      end
    end
  end

  # Marks this source kind's runs that have been "running" longer than
  # ABANDONED_AFTER as failed. Returns how many.
  def self.sweep_abandoned(source_kind)
    stale = CrawlRun.running.where(source_kind: source_kind).where(started_at: ...ABANDONED_AFTER.ago).to_a
    stale.each do |run|
      run.fail!("Abandoned: still running after #{(ABANDONED_AFTER / 1.hour).round} hours, so the worker " \
        "probably stopped. Rerun the stage.")
    end
    stale.size
  end

  def self.with_lock(source_kind)
    key = Zlib.crc32("data_quality:#{source_kind}")
    connection = CrawlRun.connection
    unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      raise AlreadyRunning, "A #{source_kind} pipeline run is already in progress; try again when it finishes"
    end

    begin
      yield
    ensure
      connection.select_value("SELECT pg_advisory_unlock(#{key})")
    end
  end
  private_class_method :with_lock
end
