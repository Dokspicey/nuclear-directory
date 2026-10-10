# How the pipeline is doing, in plain text: bin/rails data_quality:status
# - sources that need attention (blocked, needs_human), with the reason
# - the last run of each stage per source kind, and anything running now
# - the review queue, grouped by reason
# - model calls, tokens and cost this month against the budget
module DataQuality::StatusReport
  def self.call(now: Time.current, budget: DataQuality::Config.from_env.monthly_budget)
    [
      "Data quality status, #{now.utc.strftime('%Y-%m-%d %H:%M')} UTC",
      "",
      *sources,
      "",
      *runs,
      "",
      *review_queue,
      "",
      spend(now, budget)
    ].join("\n")
  end

  def self.sources
    counts = Source.group(:crawl_status).count.sort.map { |status, n| "#{status} #{n}" }.join(", ")
    attention = Source.where(crawl_status: %w[blocked needs_human]).order(:source_kind, :url).map do |source|
      "  #{source.crawl_status.ljust(11)} #{source.source_kind.ljust(18)} #{source.url}\n" \
        "              #{source.status_reason.presence || 'no reason recorded'}"
    end

    [ "Sources: #{Source.count} (#{counts.presence || 'none'})", "Needing attention:", *(attention.presence || [ "  none" ]) ]
  end

  def self.runs
    # Finished runs only; a run in progress is listed under "Running now" and
    # mustn't hide its stage's last result.
    latest = CrawlRun.where.not(status: "running")
      .select("DISTINCT ON (source_kind, stage) *").order(:source_kind, :stage, started_at: :desc)
    running = CrawlRun.running.order(:started_at)

    [
      "Last run per stage:",
      *(latest.map { |run| "  #{run_line(run)}" }.presence || [ "  none yet" ]),
      *(running.any? ? [ "Running now:", *running.map { |run| "  #{run_line(run)}" } ] : [])
    ]
  end

  def self.run_line(run)
    duration = run.finished_at ? "#{(run.finished_at - run.started_at).round(1)}s" : "running"
    detail = run.failed? ? "ERROR #{run.error}" : run.stats.except("llm").to_json
    "#{run.source_kind.to_s.ljust(18)} #{run.stage.ljust(7)} #{run.status.ljust(9)} " \
      "#{run.started_at.utc.strftime('%Y-%m-%d %H:%M')} #{duration.rjust(8)}  #{detail.truncate(140)}"
  end

  # Grouped by kind of question: the reason's first clause, with quoted
  # names blanked ('no exact match for "Dominion Generation"' and '… for
  # "Duke Energy …"' count together), so the most common ones stand out.
  def self.review_queue
    waiting = Candidate.status_needs_review
    reasons = waiting.pluck(:notes).map do |notes|
      notes.to_s.split(":").first.to_s.gsub(/"[^"]*"/, '"…"').squish.truncate(90).presence || "no reason"
    end
    [
      "Review queue: #{reasons.size} candidates",
      *reasons.tally.sort_by { |reason, n| [ -n, reason ] }.first(10).map { |reason, n| "  #{n.to_s.rjust(4)}  #{reason}" }
    ]
  end

  # The same month-split totals the budget guard uses.
  def self.spend(now, budget)
    usage = DataQuality::Budget.usage_this_month(now:)
    format("Model spend this month: %d calls, %s tokens, $%.4f of the $%.2f budget",
      usage[:calls], ActiveSupport::NumberHelper.number_to_delimited(usage[:total_tokens]), usage[:cost], budget)
  end
  private_class_method :sources, :runs, :run_line, :review_queue, :spend
end
