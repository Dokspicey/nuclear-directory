# How the pipeline is doing, in plain text: bin/rails data_quality:status
# - sources that need attention (blocked, needs_human), with the reason
# - the last run of each stage per source kind, and anything running now
# - the review queue, grouped by reason
# - model calls, tokens and cost this month against the budget
# The values come from DataQuality::Status, which the admin shows too.
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
    status = DataQuality::Status.sources
    counts = status.by_status.map { |crawl_status, n| "#{crawl_status} #{n}" }.join(", ")
    attention = status.attention.map do |source|
      "  #{source.crawl_status.ljust(11)} #{source.source_kind.ljust(18)} #{source.url}\n" \
        "              #{source.status_reason.presence || 'no reason recorded'}"
    end

    [ "Sources: #{status.total} (#{counts.presence || 'none'})", "Needing attention:", *(attention.presence || [ "  none" ]) ]
  end

  def self.runs
    runs = DataQuality::Status.runs

    [
      "Last run per stage:",
      *(runs.latest.map { |run| "  #{run_line(run)}" }.presence || [ "  none yet" ]),
      *(runs.running.any? ? [ "Running now:", *runs.running.map { |run| "  #{run_line(run)}" } ] : [])
    ]
  end

  def self.run_line(run)
    duration = run.duration ? "#{run.duration}s" : "running"
    detail = run.failed? ? "ERROR #{run.error}" : run.stats.to_json
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
    spend = DataQuality::Status.spend(now:, budget:)
    format("Model spend this month: %d calls, %s tokens, $%.4f of the $%.2f budget",
      spend.calls, ActiveSupport::NumberHelper.number_to_delimited(spend.total_tokens), spend.cost, spend.budget)
  end
  private_class_method :sources, :runs, :run_line, :review_queue, :spend
end
