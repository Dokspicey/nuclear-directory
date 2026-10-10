require "test_helper"

class DataQuality::StatusReportTest < ActiveSupport::TestCase
  def report = DataQuality::StatusReport.call(budget: 5.0)

  test "shows sources that need attention, with the reason" do
    Source.create!(url: "https://www.nrc.gov/status.txt", source_kind: "nrc_power_status", crawl_status: "blocked",
      status_reason: "HTTP 403 from AkamaiGHost, reference #18.4460d017")
    Source.create!(url: "https://example.com/moved", source_kind: "web_page", crawl_status: "needs_human",
      status_reason: "robots.txt disallows /moved")

    text = report

    assert_match(/blocked\s+nrc_power_status\s+https:\/\/www.nrc.gov\/status.txt/, text)
    assert_match "reference #18.4460d017", text
    assert_match "robots.txt disallows /moved", text
  end

  test "shows the last run of each stage, failures with their error, and runs in progress" do
    CrawlRun.create!(stage: "crawl", source_kind: "nrc_reactor_list", started_at: 2.hours.ago, finished_at: 2.hours.ago + 3,
      status: "succeeded", stats: { "list" => "unchanged" })
    CrawlRun.create!(stage: "crawl", source_kind: "nrc_reactor_list", started_at: 1.hour.ago, finished_at: 1.hour.ago + 2,
      status: "succeeded", stats: { "list" => "changed" })
    CrawlRun.create!(stage: "extract", source_kind: "nrc_reactor_list", started_at: 50.minutes.ago,
      finished_at: 49.minutes.ago, status: "failed", error: "Monthly model budget of $5.00 is used up")
    CrawlRun.create!(stage: "verify", source_kind: "nrc_reactor_list", started_at: 5.minutes.ago)

    text = report

    assert_match(/nrc_reactor_list\s+crawl\s+succeeded.*\{"list":"changed"\}/, text)
    assert_no_match(/"list":"unchanged"/, text, "only the latest run per stage")
    assert_match(/extract\s+failed.*ERROR Monthly model budget/, text)
    assert_match(/Running now:\n.*verify\s+running/, text)
  end

  test "a stage that's running again still shows its last finished run" do
    CrawlRun.create!(stage: "extract", source_kind: "nrc_reactor_list", started_at: 1.hour.ago, finished_at: 59.minutes.ago,
      status: "succeeded", stats: { "candidates" => 219 })
    CrawlRun.create!(stage: "extract", source_kind: "nrc_reactor_list", started_at: 1.minute.ago)

    last_runs, running = report.split("Running now:")

    assert_match(/extract\s+succeeded.*"candidates":219/, last_runs)
    assert_no_match(/extract\s+running/, last_runs)
    assert_match(/extract\s+running/, running)
  end

  test "groups the review queue by reason and totals model spend against the budget" do
    source = sources(:nrc)
    2.times { Candidate.create!(source:, kind: "organization", payload: {}, status: "needs_review", notes: "organization: no exact match for X") }
    Candidate.create!(source:, kind: "facility", payload: {}, status: "needs_review", notes: "The verifier couldn't confirm this")
    Candidate.create!(source:, kind: "organization", payload: {}, status: "needs_review",
      notes: 'no exact match for "Dominion Generation", but similar: Dominion Energy')
    Candidate.create!(source:, kind: "organization", payload: {}, status: "needs_review",
      notes: 'no exact match for "Duke Energy Carolinas, LLC", but similar: Duke Energy Progress')
    CrawlRun.create!(stage: "extract", source_kind: "nrc_reactor_list", status: "succeeded",
      stats: { "llm" => { "calls" => 4, "total_tokens" => 12_045, "cost" => 0.0042 } })

    text = report

    assert_match(/Review queue: 5 candidates\n\s+2  no exact match for "…", but similar\n\s+2  organization\n\s+1  The verifier/, text,
      "reasons that differ only by a name count together")
    assert_match "Model spend this month: 4 calls, 12,045 tokens, $0.0042 of the $5.00 budget", text
  end
end
