# What model calls have cost this calendar month, from the cost OpenRouter
# reports on each call (crawl_runs.stats["llm"]["cost"]). The client checks
# it before every call and refuses once the budget is used up, so a runaway
# run fails with a clear reason instead of on a provider error mid-run.
#
# It's a soft limit: calls already in flight when the budget runs out (one
# per concurrently running source kind, a fraction of a cent each) still
# complete, so spend can pass the budget by that much. Serializing every
# model call app-wide to close that gap isn't worth it; the OpenRouter key's
# own credit limit is the hard stop.
module DataQuality::Budget
  class Exceeded < StandardError; end

  # US dollars spent on model calls since the start of this month.
  def self.spent_this_month(now: Time.current)
    CrawlRun.where(started_at: now.beginning_of_month..)
      .pick(Arel.sql("COALESCE(SUM((stats -> 'llm' ->> 'cost')::numeric), 0)")).to_f
  end

  def self.check!(budget)
    spent = spent_this_month
    return if spent < budget

    raise Exceeded, format("Monthly model budget of $%.2f is used up ($%.4f spent since %s). " \
      "Raise DATA_QUALITY_MONTHLY_BUDGET or wait until next month.", budget, spent, Time.current.beginning_of_month.to_date)
  end
end
