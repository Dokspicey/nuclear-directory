module DeployData
  # The deploy's data step (#301), run by bin/deploy-data in Render's
  # pre-deploy step after db:migrate. In order:
  #
  # 1. Nothing to do unless the seed files (or the code that loads them)
  #    changed since the last run, or a db/data/ migration is new.
  # 2. Hold the crawl's locks, or stop: never write during the daily crawl.
  # 3. Take a fresh encrypted backup; stop if it fails.
  # 4. seed:check; stop on any collision.
  # 5. db:seed, then
  # 6. each new data migration, all in one transaction: if any fails,
  #    nothing from 5 or 6 is written and the next deploy runs them all
  #    again (so a migration's fix is never left out after a re-seed).
  # 7. Report: deploy log, a comment on the PR, and Sentry when it needs a look.
  #
  # "Stop" writes nothing, alerts, and lets the code deploy go on.
  #
  # AUTO_DATA_DEPLOY (set in the dashboard) picks the mode:
  # - "on": all of the above.
  # - "report": the backup, then steps 4 to 6 in a transaction that's rolled
  #   back, and the would-be report on the PR, while the steps are still done
  #   by hand. Run for a few data PRs and compare before switching to "on".
  # - anything else, or blank: off (the kill switch).
  #
  # dry_run: Data Quality's rehearsal on a restored backup. Steps 4 to 6,
  # rolled back; no backup, record or post, whatever the mode.
  class Run
    class Stop < StandardError; end
    class TimedOut < StandardError; end
    class MigrationFailed < StandardError; end

    MODES = %w[on report].freeze
    SEED_COUNTS = "tmp/seed_counts.json".freeze

    attr_reader :report

    def initialize(dry_run: false, commit: ENV["RENDER_GIT_COMMIT"], mode: ENV["AUTO_DATA_DEPLOY"],
      backup: Backup, github: GitHub.new, migrations: Migrations.new, root: Rails.root, lock: CrawlLock,
      seeder: -> { Rails.application.load_seed },
      checker: -> { Seed::OrganizationLoader.new(Rails.root.join("db/seeds/organizations")).collisions })
      @dry_run = dry_run
      @mode = MODES.include?(mode.to_s.strip) ? mode.to_s.strip : "off"
      @commit = commit.presence
      @backup = backup
      @github = github
      @migrations = migrations
      @root = root
      @lock = lock
      @seeder = seeder
      @checker = checker
    end

    # Returns :disabled, :nothing, :applied, :reported, :stopped or :failed
    # (:reported for a dry run that got to the end).
    def call
      if !@dry_run && @mode == "off"
        puts "deploy-data: off (AUTO_DATA_DEPLOY isn't \"on\" or \"report\"); the seed and data migrations didn't run."
        return :disabled
      end

      @started_at = Time.current
      @fingerprint = Fingerprint.current(@root)
      @last = DataDeploy.baseline(report_mode: report_mode?)
      @changed = @fingerprint.changed_since(@last&.files)
      @seed_changed = @last.nil? || @last.seed_digest != @fingerprint.digest
      @pending = @migrations.pending
      @pending = @pending.reject { |pending| DataDeploy.reported_migrations.include?(pending.version) } if report_mode?
      unless @seed_changed || @pending.any?
        puts "deploy-data: nothing to do (the seed is unchanged since #{short(@last.commit)} and no data migrations are new)."
        return :nothing
      end

      pull_request = @github.pull_request_for(@commit)
      @reason = [ "deploy #{short(@commit)}", ("PR ##{pull_request}" if pull_request) ].compact.join(", ")
      @report = Report.new(commit: @commit, pull_request:, label:)
      @status = rolled_back? ? :reported : :applied

      held = @lock.hold { steps }
      stop!("stopped: the daily crawl is running, so nothing was written; it runs again on the next deploy") unless held
      finish
    rescue Stop
      finish
    rescue TimedOut, StandardError, ScriptError => error
      @report ||= Report.new(commit: @commit, pull_request: nil, label:)
      @status = :failed
      @report.outcome = "failed: #{error.class.name.demodulize}: #{error.message.lines.first&.strip}"
      @error = error.full_message(highlight: false)
      finish
    end

    private
      def report_mode? = !@dry_run && @mode == "report"
      def rolled_back? = @dry_run || report_mode?

      def label
        if @dry_run then "Dry run (rolled back)"
        elsif report_mode? then "Report mode (rolled back; apply by hand)"
        else "Data deploy"
        end
      end

      def short(commit) = commit.to_s[0, 7].presence || "unknown"

      def steps
        take_backup
        check if @seed_changed
        in_one_transaction do
          @report.rows_before = Census.rows
          @report.totals_before = Census.public_totals
          seed if @seed_changed
          @report.seed ||= "skipped (unchanged since #{short(@last.commit)})"
          migrate
          @report.rows_after = Census.rows
          @report.totals_after = Census.public_totals
        end
        @report.outcome ||= rolled_back? ? "would apply" : "applied"
      end

      def take_backup
        @report.backup = @dry_run ? "skipped (dry run)" : @backup.take!
      rescue Backup::Failed => error
        stop!("stopped: #{error.message}, so nothing was written")
      end

      def check
        collisions = @checker.call
        @report.seed_check = collisions.empty? ? "no collisions" : "#{collisions.size} #{'collision'.pluralize(collisions.size)}"
        return if collisions.empty?

        @report.notes.concat(collisions)
        stop!("stopped: seed:check found collisions, so nothing was written")
      end

      def seed
        first_event = Census.last_event_id
        counts_file = @root.join(SEED_COUNTS)
        File.delete(counts_file) if File.exist?(counts_file)
        log = capturing_output { ActiveRecord::Base.transaction { @seeder.call } }
        @report.seed = @last ? "ran (#{@changed.size} #{'file'.pluralize(@changed.size)} changed since #{short(@last.commit)})" : "ran (first automatic run)"
        @report.seed_counts = File.exist?(counts_file) ? JSON.parse(File.read(counts_file)) : SeedLog.counts(log)

        events = VerificationEvent.where("id > ?", first_event).to_a
        @report.seed_events = events.map(&:subject_type).tally
        flip_flops(events)
      end

      # Runs the block, printing its output as usual and returning it too.
      def capturing_output
        original = $stdout
        captured = StringIO.new
        $stdout = SeedLog::Tee.new(original, captured)
        yield
        captured.string
      ensure
        $stdout = original
      end

      def flip_flops(events)
        if @last.nil?
          @report.notes << "first automatic run: there's no earlier file list, so flip-flops can't be told from changes"
        else
          @report.flags = FlipFlops.find(events, changed: @changed)
          if Fingerprint.code_changed?(@changed) && @report.flags.any?
            @report.notes << "the seed's code changed (#{@changed.grep(Fingerprint::CODE).join(', ')}), so flagged events may be expected"
          end
        end
      end

      def migrate
        first_event = Census.last_event_id
        @pending.each do |pending|
          @report.migrations << @migrations.run(pending, reason: @reason, commit: @commit)
        rescue StandardError, ScriptError => error
          raise MigrationFailed, "data migration #{pending.version} #{pending.name}: #{error.class.name}: #{error.message}"
        end
        @report.migration_events = VerificationEvent.where("id > ?", first_event).pluck(:subject_type).tally if @pending.any?
      end

      # The seed and data migrations commit together, or (a rehearsal) not at all.
      def in_one_transaction
        ActiveRecord::Base.transaction do
          yield
          raise ActiveRecord::Rollback if rolled_back?
        end
      end

      def stop!(outcome)
        @status = :stopped
        @report.outcome = outcome
        raise Stop
      end

      def finish
        puts @report
        return @status if @dry_run

        record
        url = @github.post(@report.to_markdown, pull_request: @report.pull_request, title: @report.title)
        puts "Report posted: #{url}" if url
        alert if @report.alert?
        @status
      end

      def record
        backup_tag = @report.backup if @report.backup.to_s.start_with?("backup-")
        DataDeploy.create!(commit: @commit, status: @status, backup_tag:,
          seed_digest: @fingerprint&.digest, files: @fingerprint&.files || {},
          report: { text: @report.to_s, migrations: @report.migrations.map(&:version) },
          error: @error, started_at: @started_at || Time.current, finished_at: Time.current)
      rescue StandardError => error
        warn "deploy-data: couldn't record the run: #{error.message}"
      end

      def alert
        return unless defined?(Sentry) && Sentry.initialized?

        Sentry.capture_message("Data deploy needs a look: #{@report.outcome}", level: @status == :failed || @status == :stopped ? :error : :warning,
          extra: { report: @report.to_s })
      end
  end
end
