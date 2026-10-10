require "test_helper"

# Both fixtures are real NRC data fetched 2026-10-10: the list page's table,
# and a slice of the status file (the latest day's 95 rows plus a few older
# ones; the full file is ~1.3 MB).
class DataQuality::Plugins::NrcReactorListTest < ActiveSupport::TestCase
  Plugin = DataQuality::Plugins::NrcReactorList

  setup do
    stub_request(:get, "https://www.nrc.gov/robots.txt").to_return(body: file_fixture("nrc/robots.txt").read)
    @list = stub_request(:get, Plugin::LIST_URL).to_return(body: list_html,
      headers: { "ETag" => '"1791578421-gzip"', "Last-Modified" => "Fri, 09 Oct 2026 20:40:21 GMT" })
    @status = stub_request(:get, Plugin::STATUS_URL).to_return(body: status_txt)
  end

  def list_html = file_fixture("nrc/list-power-reactor-units.html").read
  def status_txt = file_fixture("nrc/PowerReactorStatusForLast365Days.txt").read
  def plugin = Plugin.new(fetcher: DataQuality::Fetcher.new(sleeper: ->(_) { }))
  def crawl = DataQuality::Stages::Crawl.call(plugin: plugin)
  def list_source = Source.find_by!(url: Plugin::LIST_URL)
  def status_source = Source.find_by!(url: Plugin::STATUS_URL)

  test "is the plug-in for nrc_reactor_list" do
    assert_instance_of Plugin, DataQuality::Plugin.for("nrc_reactor_list")
  end

  test "snapshots both files and cross-checks the 95 units" do
    run = crawl

    assert run.succeeded?
    assert_equal({ "list" => "changed", "status_file" => "changed", "units" => 95, "cross_check" => "ok" }, run.stats)

    list = list_source
    assert list.crawl_ok?
    assert_equal [ 200, '"1791578421-gzip"', "nrc_reactor_list" ], [ list.http_status, list.etag, list.source_kind ]
    assert_equal Digest::SHA256.hexdigest(list.content_text), list.content_sha256
    assert_equal "List of Power Reactor Units", list.title, "the page's own title"
    assert_equal "nrc_power_status", status_source.source_kind, "the status file is never extracted"
    assert_equal "NRC power reactor status, last 365 days", status_source.title, "a text file keeps the title it was given"
  end

  test "a page too large to store keeps the last good snapshot" do
    crawl
    list_source.update!(fetched_at: 2.days.ago)
    status_source.update!(fetched_at: 2.days.ago)
    stub_request(:get, Plugin::LIST_URL).to_return(body: "x" * (DataQuality::Fetcher::MAX_BYTES + 1))

    assert_equal "error", crawl.stats["list"]
    assert_equal 95, Plugin::Page.units(list_source.content_text).size
    assert_match "Larger than 20 MB", list_source.status_reason
  end

  test "fetches at most once a day" do
    crawl
    second = crawl

    assert_equal "skipped_recent", second.stats["list"]
    assert_requested @list, times: 1
  end

  test "next day, asks whether the page changed and skips extraction when it hasn't" do
    crawl
    list_source.update!(fetched_at: 2.days.ago, extracted_sha256: list_source.content_sha256)
    status_source.update!(fetched_at: 2.days.ago)
    not_modified = stub_request(:get, Plugin::LIST_URL).with(headers: { "If-None-Match" => '"1791578421-gzip"' })
      .to_return(status: 304)

    run = crawl

    assert_requested not_modified
    assert_equal "unchanged", run.stats["list"]
    assert list_source.crawl_ok?
  end

  test "on a block, records the CDN reference and stops without fetching anything else" do
    stub_request(:get, Plugin::LIST_URL).to_return(status: 403, body: file_fixture("nrc/akamai-403.html").read)

    run = crawl

    assert_equal({ "list" => "blocked", "stopped" => "list page blocked" }, run.stats)
    assert list_source.crawl_blocked?
    assert_match "reference #18.4460d017.1791618638.14c00ece", list_source.status_reason
    assert_not_requested @status
  end

  test "three blocked days in a row need a human" do
    stub_request(:get, Plugin::LIST_URL).to_return(status: 403, body: "Access Denied")

    3.times do
      crawl
      list_source.update!(fetched_at: 2.days.ago)
    end

    assert list_source.crawl_needs_human?
    assert_match "Blocked 3 fetches in a row", list_source.status_reason
  end

  test "a page without the reactor table needs a human" do
    stub_request(:get, Plugin::LIST_URL).to_return(body: "<html><body>We moved things around</body></html>")

    assert_equal 0, crawl.stats["units"]
    assert list_source.crawl_needs_human?
    assert_match "Couldn't find the reactor table", list_source.status_reason
  end

  test "units the two files disagree on need a human" do
    disagreeing = status_txt.gsub("Watts Bar 2", "Watts Bar 3") + "10/9/2026 12:00:00 AM|Example Unit 9|0\n"
    stub_request(:get, Plugin::STATUS_URL).to_return(body: disagreeing)

    run = crawl

    assert_equal "mismatch", run.stats["cross_check"]
    assert list_source.crawl_needs_human?
    assert_match "Only on the page: Watts Bar 2", list_source.status_reason
    assert_match "Only in the status file: Watts Bar 3, Example Unit 9", list_source.status_reason
  end

  test "a blocked status file skips the cross-check but keeps the list usable" do
    stub_request(:get, Plugin::STATUS_URL).to_return(status: 403, body: file_fixture("nrc/akamai-403.html").read)

    run = crawl

    assert_equal "blocked", run.stats["status_file"]
    assert_equal "skipped: status file is blocked", run.stats["cross_check"]
    assert_match "reference #18.4460d017", status_source.status_reason
    assert list_source.crawl_ok?
  end

  test "a status file that worked before but fails today isn't compared stale" do
    crawl
    [ list_source, status_source ].each { |source| source.update!(fetched_at: 2.days.ago) }
    # Today the page changes (one unit gone) and the status file errors, so
    # only yesterday's status file is on hand. Comparing against it would
    # wrongly flag a mismatch.
    stub_request(:get, Plugin::LIST_URL).to_return(body: list_html.sub(%r{<tr><td scope="row"><p><a [^>]*>Wolf Creek 1</a>.*?</tr>}m, ""))
    stub_request(:get, Plugin::STATUS_URL).to_return(status: 500)

    run = crawl

    assert_equal "error", run.stats["status_file"]
    assert_equal 94, run.stats["units"]
    assert_equal "skipped: status file is unavailable (HTTP 500)", run.stats["cross_check"]
    assert list_source.crawl_ok?
    assert status_source.crawl_ok?, "a temporary error keeps the last good snapshot"
  end

  test "fetches each source at most once per calendar day" do
    travel_to(Time.zone.parse("2026-10-10 23:00")) { crawl }

    travel_to(Time.zone.parse("2026-10-11 05:00")) do
      assert_equal "unchanged", crawl.stats["list"], "a new day allows a fetch, even 6 hours later"
      assert_equal "skipped_recent", crawl.stats["list"], "but only one that day"
    end
    assert_requested @list, times: 2
  end
end
