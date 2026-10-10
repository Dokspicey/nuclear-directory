require "test_helper"

# Sources and runs (#86): blocked sources with their CDN reference, the last
# run per stage, and spend against the budget.
class Admin::StatusControllerTest < ActionDispatch::IntegrationTest
  test "needs a signed-in admin" do
    get admin_status_path
    assert_redirected_to new_session_path
  end

  test "shows blocked sources with the reason, the last run per stage and this month's spend" do
    blocked = Source.create!(url: "https://www.nrc.gov/list", source_kind: "nrc_reactor_list", crawl_status: "blocked",
      status_reason: "HTTP 403 from AkamaiGHost, reference #18.abc", blocked_streak: 2, fetched_at: Time.current)
    CrawlRun.create!(stage: "crawl", source_kind: "nrc_reactor_list", status: "succeeded", started_at: 1.hour.ago,
      finished_at: 1.hour.ago + 2, stats: { "list" => "blocked" })
    CrawlRun.create!(stage: "crawl", source_kind: "eia_generators", status: "failed", started_at: 30.minutes.ago,
      finished_at: 30.minutes.ago + 7, error: "RuntimeError: Error pulling: -1")
    sign_in_as users(:admin)

    get admin_status_path

    assert_response :success
    assert_select "#source-#{blocked.id}" do
      assert_select ".nd-item__claim", /Blocked/
      assert_select ".nd-item__why", "HTTP 403 from AkamaiGHost, reference #18.abc"
      assert_select ".nd-item__meta", /Blocked 2 days in a row/
    end
    assert_select "td", "nrc_reactor_list"
    assert_select "td", /Error pulling: -1/
    assert_select "section", /of the \$5\.00 monthly budget/
    assert_select "a", text: /PostHog/, count: 0
  end

  def spent!(cost)
    CrawlRun.create!(stage: "verify", source_kind: "nrc_reactor_list", status: "succeeded", started_at: Time.current,
      finished_at: Time.current, stats: { "llm" => { "calls" => 10, "total_tokens" => 1000, "cost" => cost } })
  end

  test "a failed run reads as an error; durations and stat names read as words" do
    CrawlRun.create!(stage: "crawl", source_kind: "eia_generators", status: "failed", started_at: 2.hours.ago,
      finished_at: 2.hours.ago + 4321, error: "RuntimeError: boom")
    CrawlRun.create!(stage: "extract", source_kind: "nrc_reactor_list", status: "succeeded", started_at: 1.hour.ago,
      finished_at: 1.hour.ago + 42.9, stats: { "ai_check" => { "agreed" => 95, "made_up" => 0 } })
    sign_in_as users(:admin)

    get admin_status_path

    assert_select "td[data-label=Result] .text-critical", /Failed/
    assert_select "td[data-label=Time]", "72 min"
    assert_select "td[data-label=Time]", "42.9 s"
    assert_select "td[data-label=Detail]", "AI check: agreed 95, made up 0"
  end

  test "spend: a plain line from 80%, a status message (not an alert) once it's used up" do
    sign_in_as users(:admin)
    spent!(4.2)
    get admin_status_path
    assert_select "p", /\$4\.20 of \$5\.00 used; model calls stop at 100%/
    assert_select ".nd-flash", 0

    spent!(1.0)
    get admin_status_path
    assert_select ".nd-flash[role=status]", /budget is used up/
    assert_select "[role=alert]", 0
  end

  test "links the PostHog dashboard when one is configured" do
    sign_in_as users(:admin)
    ENV["POSTHOG_DASHBOARD_URL"] = "https://us.posthog.com/project/1/dashboard/2"

    get admin_status_path

    assert_select "a[href=?]", "https://us.posthog.com/project/1/dashboard/2", text: /Open the PostHog dashboard/
  ensure
    ENV.delete("POSTHOG_DASHBOARD_URL")
  end
end
