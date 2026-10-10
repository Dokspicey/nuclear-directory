require "test_helper"

class DataQuality::TitleBackfillTest < ActiveSupport::TestCase
  setup do
    # Only this test's sources are untitled.
    Source.update_all(title: "Fixture")
    @sleeps = []
    @now = 0.0
    @fetcher = DataQuality::Fetcher.new(sleeper: ->(s) { @sleeps << s; @now += s }, clock: -> { @now })
    %w[https://news.example https://www.energy.gov https://blocked.example].each do |site|
      stub_request(:get, "#{site}/robots.txt").to_return(status: 404)
    end

    @article = Source.create!(url: "https://news.example/kairos-tva", source_kind: "web_page")
    @second = Source.create!(url: "https://news.example/kairos-hermes", source_kind: "web_page")
    @pdf = Source.create!(url: "https://www.energy.gov/files/haleu.pdf", source_kind: "web_page",
      published_on: Date.new(2024, 3, 4))
    @blocked = Source.create!(url: "https://blocked.example/page", source_kind: "web_page")
    @titled = Source.create!(url: "https://news.example/already", source_kind: "web_page", title: "Kept as is")

    stub_request(:get, @article.url).to_return(body: "<title>Kairos and TVA sign deal</title>", headers: { "Content-Type" => "text/html" })
    stub_request(:get, @second.url).to_return(body: "<title>Hermes reactor update</title>", headers: { "Content-Type" => "text/html" })
    stub_request(:get, @pdf.url).to_return(body: "%PDF-1.7", headers: { "Content-Type" => "application/pdf" })
    stub_request(:get, @blocked.url).to_return(status: 403, body: "Access Denied")
  end

  def run_backfill = DataQuality::TitleBackfill.run(fetcher: @fetcher)

  test "titles each untitled source once, politely, and leaves the rest alone" do
    stats = run_backfill

    assert_equal({ "titled" => 2, "fallback" => 1, "skipped" => 1 }, stats)
    assert_equal "Kairos and TVA sign deal", @article.reload.title
    assert_equal "Hermes reactor update", @second.reload.title, "two articles from one site are now told apart"
    assert_equal "energy.gov, March 4, 2024", @pdf.reload.title
    assert_nil @blocked.reload.title, "a block is skipped, not worked around"
    assert_equal "Kept as is", @titled.reload.title
    assert_not_requested :get, @titled.url

    assert_requested :get, "https://news.example/robots.txt", times: 1
    assert_includes @sleeps, DataQuality::Fetcher::HOST_INTERVAL, "waits between the two news.example pages"
  end

  test "only keeps the title, never the page" do
    run_backfill

    assert_nil @article.reload.content_text
    assert @article.crawl_pending?
  end

  test "fetches a source at most once a day: its fetch counts as today's, and a source fetched today is skipped" do
    @article.update!(fetched_at: Time.current)

    stats = run_backfill

    assert_not_requested :get, @article.url
    assert_nil @article.reload.title
    assert_equal 2, stats["skipped"], "the source fetched today, and the blocked one"
    assert_equal Date.current, @second.reload.fetched_at.to_date, "a backfill fetch is today's fetch"
    assert_equal Date.current, @blocked.reload.fetched_at.to_date, "so is a blocked one"

    assert_equal :skipped_recent, DataQuality::Snapshot.take(@second, fetcher: @fetcher), "Snapshot won't fetch it again today"
  end

  test "asks conditionally; not modified takes the title from the stored page, and no validators are stored" do
    @article.update!(etag: '"v1"', last_modified: "Wed, 01 Oct 2026 00:00:00 GMT", fetched_at: 2.days.ago,
      content_text: "<html><head><title>Stored page title</title></head></html>")
    stub_request(:get, @article.url).with(headers: { "If-None-Match" => '"v1"' })
      .to_return(status: 304, headers: { "ETag" => '"v2"', "Last-Modified" => "Fri, 10 Oct 2026 00:00:00 GMT" })
    stub_request(:get, @second.url).to_return(body: "<title>Hermes reactor update</title>",
      headers: { "Content-Type" => "text/html", "ETag" => '"partial"', "Last-Modified" => "Fri, 10 Oct 2026 00:00:00 GMT" })

    run_backfill

    @article.reload
    assert_equal "Stored page title", @article.title
    assert_equal [ '"v1"', "Wed, 01 Oct 2026 00:00:00 GMT" ], [ @article.etag, @article.last_modified ], "the stored snapshot's validators are kept"
    @second.reload
    assert_equal "Hermes reactor update", @second.title
    assert_equal [ nil, nil ], [ @second.etag, @second.last_modified ], "a partial read's validators are discarded"
  end

  test "the once-a-day check re-reads the source under its lock, so an overlapping fetch is skipped" do
    stale = Source.find(@article.id)  # loaded before another process fetched it today
    @article.update!(fetched_at: Time.current)

    assert_equal :skipped_recent, DataQuality::Snapshot.take(stale, fetcher: @fetcher)
    DataQuality::TitleBackfill.run(sources: Source.where(id: stale.id), fetcher: @fetcher)

    assert_not_requested :get, @article.url
  end

  test "reads at most the top of a page" do
    huge = "<html><head><title>Big page</title></head><body>#{'x' * 2.megabytes}</body></html>"
    stub_request(:get, @article.url).to_return(body: huge, headers: { "Content-Type" => "text/html" })

    run_backfill

    assert_equal "Big page", @article.reload.title
  end
end
