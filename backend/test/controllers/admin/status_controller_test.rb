require "test_helper"

# Sources (#86, #201): a row per kind of source, then, folded, sources that
# need attention with their CDN reference, the last run per stage, and spend
# against the budget.
class Admin::StatusControllerTest < ActionDispatch::IntegrationTest
  # Every test starts from the defaults ($5 budget, no dashboard link),
  # whatever the developer's or CI's environment says.
  ENV_VARS = %w[DATA_QUALITY_MONTHLY_BUDGET POSTHOG_DASHBOARD_URL].freeze
  setup { @saved_env = ENV.to_h.slice(*ENV_VARS); ENV_VARS.each { ENV.delete(_1) } }
  teardown { ENV_VARS.each { ENV.delete(_1) }; @saved_env.each { |name, value| ENV[name] = value } }

  # Sets (or clears, with nil) an environment variable for the block, then restores it.
  def with_env(name, value)
    saved = ENV[name]
    value.nil? ? ENV.delete(name) : ENV[name] = value
    yield
  ensure
    saved.nil? ? ENV.delete(name) : ENV[name] = saved
  end

  test "needs a signed-in admin; the old address leads to Sources" do
    get admin_sources_path
    assert_redirected_to new_session_path

    get "/admin/status"
    assert_redirected_to admin_sources_path
  end

  test "a row per kind of source: last read, read, same, changed, approved, rejected, live" do
    nrc = Source.create!(url: "https://www.nrc.gov/list", source_kind: "nrc_reactor_list", crawl_status: "ok", content_text: "x")
    CrawlRun.create!(stage: "crawl", source_kind: "nrc_reactor_list", status: "succeeded", started_at: Time.zone.parse("2026-10-15 04:10"),
      finished_at: Time.zone.parse("2026-10-15 04:11"), stats: {})
    CrawlRun.create!(stage: "match", source_kind: "nrc_reactor_list", status: "succeeded", started_at: Time.zone.parse("2026-10-15 04:12"),
      finished_at: Time.zone.parse("2026-10-15 04:13"), stats: { "candidates" => 219, "confirmed" => 217 })
    waiting = Candidate.create!(source: nrc, kind: "organization", payload: { "name" => "A Co" }, quote: "x", status: "needs_review", notes: "unsure")
    Candidate.create!(source: nrc, kind: "organization", payload: { "name" => "B Co" }, quote: "x", status: "rejected")
    org = Organization.create!(name: "Live Co", verification_status: "verified", verified_by: "human:tosin")
    Evidence.create!(subject: org, source: nrc, quote: "Live Co", found_by: "crawler")
    CrawlRun.create!(stage: "crawl", source_kind: "eia_generators", status: "failed", started_at: 30.minutes.ago,
      finished_at: 30.minutes.ago + 7, error: "RuntimeError: Error pulling: -1")
    sign_in_as users(:admin)

    get admin_sources_path

    assert_response :success
    assert_select "h1", /Sources\s+2/
    assert_select ".nd-shell__nav a[aria-current=page]", /Sources\s+2/
    row = css_select(".nd-numtable tbody tr").find { |tr| tr.text.include?("nrc_reactor_list") }
    assert_equal [ "NRC nrc_reactor_list", "15 Oct 04:10", "219", "217", "1", "—", "1", "1" ], row.css("td").map { |td| td.text.squish }
    assert_select "a[href=?]", admin_checks_path(source: "nrc_reactor_list"), "1"
    assert_select "tr", /EIA.*Failed/m
    assert_select "tr", /Correction requests/
    assert waiting
  end

  test "folded: blocked sources with the reason, the last run per stage and this month's spend" do
    blocked = Source.create!(url: "https://www.nrc.gov/list", source_kind: "nrc_reactor_list", crawl_status: "blocked",
      status_reason: "HTTP 403 from AkamaiGHost, reference #18.abc", blocked_streak: 2, fetched_at: Time.current)
    CrawlRun.create!(stage: "crawl", source_kind: "nrc_reactor_list", status: "succeeded", started_at: 1.hour.ago,
      finished_at: 1.hour.ago + 2, stats: { "list" => "blocked" })
    CrawlRun.create!(stage: "crawl", source_kind: "eia_generators", status: "failed", started_at: 30.minutes.ago,
      finished_at: 30.minutes.ago + 7, error: "RuntimeError: Error pulling: -1")
    sign_in_as users(:admin)

    with_env("POSTHOG_DASHBOARD_URL", nil) { get admin_sources_path }

    assert_response :success
    assert_select "details summary", /Needs attention\s+1/
    assert_select "#source-#{blocked.id}", /Blocked:.*HTTP 403 from AkamaiGHost, reference #18\.abc.*Blocked 2 days in a row/m
    assert_select ".nd-fold__row", /nrc_reactor_list · Crawl/
    assert_select ".nd-fold__row", /Error pulling: -1/
    assert_select ".nd-fold__row", /of \$5\.00/
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

    get admin_sources_path

    assert_select ".nd-fold__row .text-critical", /Failed/
    assert_select ".nd-fold__row", /72 min/
    assert_select ".nd-fold__row", /42\.9 s/
    assert_select ".nd-fold__row", /AI check: agreed 95, made up 0/
  end

  test "spend: a plain line from 80%, a status message (not an alert) once it's used up" do
    sign_in_as users(:admin)
    spent!(4.2)
    get admin_sources_path
    assert_select "p", /\$4\.20 of \$5\.00 used; model calls stop at 100%/
    assert_select ".nd-flash", 0

    spent!(1.0)
    get admin_sources_path
    assert_select "p[role=status]", /budget is used up/
    assert_select "[role=alert]", 0
  end

  test "a budget of 0 refuses every call, so it reads as used up" do
    sign_in_as users(:admin)
    with_env("DATA_QUALITY_MONTHLY_BUDGET", "0") { get admin_sources_path }
    assert_select "p[role=status]", /budget is used up/
  end

  test "links the PostHog dashboard when one is configured" do
    sign_in_as users(:admin)
    with_env("POSTHOG_DASHBOARD_URL", "https://us.posthog.com/project/1/dashboard/2") { get admin_sources_path }

    assert_select "a[href=?]", "https://us.posthog.com/project/1/dashboard/2", text: /Visitors on PostHog/
  end
end
