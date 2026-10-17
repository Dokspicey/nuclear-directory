require "test_helper"

# Sources by category (#166, Design's spec): which of the 9 categories have
# a live source, each category's sources with their status, and General.
class Admin::SourcesByCategoryTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  # Runs a crawler, so its sources are live.
  def run_crawler(kind, at: 1.hour.ago)
    Source.create!(url: "https://example.gov/#{kind}-#{SecureRandom.hex(3)}", source_kind: kind)
    CrawlRun.create!(stage: "crawl", source_kind: kind, status: "succeeded", started_at: at)
  end

  def category(key) = css_select("details##{key}").first

  test "the switch: Source by source type and Source by category, each its own address" do
    get admin_sources_path
    assert_select "nav.nd-seg a[aria-current=page][href=?]", admin_sources_path, /Source by source type/
    assert_select "nav.nd-seg a[href=?]", admin_sources_path(by: "category"), /Source by category/

    get admin_sources_path(by: "category")
    assert_select "nav.nd-seg a[aria-current=page][href=?]", admin_sources_path(by: "category")
    assert_select "nav.nd-seg a", /By category/, "the short label for phones"
    assert_select "input[placeholder=?]", "Search all sources"
  end

  test "a category with no live source shows the flag, and the count line agrees" do
    run_crawler("nrc_reactor_list")

    get admin_sources_path(by: "category")

    flagged = css_select("details.nd-cov__cat summary .nd-flag").size
    assert_equal 8, flagged
    assert_select "p .nd-flag", "8 of 9 categories have no live source"
    assert_select "details#utilities-and-operators[open] summary", /1 of 4.*Live/m
    assert_select "details#waste-and-decommissioning:not([open]) summary .nd-flag", "No live source"
  end

  test "a built source isn't live until its crawler has read something and run lately" do
    get admin_sources_path(by: "category")
    assert_select "details#government-and-research .nd-cov__src", /DOE awards \(USAspending\).*Built · #260, not running yet/m

    run_crawler("usaspending_doe_awards", at: 5.days.ago)
    get admin_sources_path(by: "category")
    assert_select "details#government-and-research summary .nd-flag", "No live source", "a run 5 days ago isn't live"

    run_crawler("usaspending_doe_awards")
    get admin_sources_path(by: "category")
    assert_select "details#government-and-research summary", /1 of 2.*Live/m
    assert_select "details#government-and-research .nd-cov__src a[href=?]", admin_source_path(key: "usaspending_doe_awards"), "DOE awards (USAspending)"
  end

  test "an issue number links out to GitHub in a new tab; a source with none is Missing" do
    get admin_sources_path(by: "category")

    assert_select "details#waste-and-decommissioning a[href=?][target=_blank]", "https://github.com/tosinoladokun/nuclear-directory/issues/274", "#274"
    assert_select "details#government-and-research .text-critical", "Missing · no issue yet"
    assert_select "details#reactor-developers .nd-cov__src", /GAIN directory\s*leads only/
  end

  test "General lists the whole industry's sources; the lead researcher brings leads, not facts" do
    Source.create!(url: "https://www.world-nuclear-news.org/a", source_kind: "web_page", domain: "world-nuclear-news.org")

    get admin_sources_path(by: "category")

    assert_select "#general-heading", /General\s*whole industry/
    assert_select ".nd-cov__src", /World Nuclear News.*Hand research · 1 document\b/m
    assert_select ".nd-cov__src", /Daily lead researcher\s*leads for Data Quality, not facts.*Planned · #278/m
    assert_select "p", "Hand-research pages count in the category of the company or plant they back."
  end
end
