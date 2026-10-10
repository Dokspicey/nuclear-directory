require "test_helper"

# The list page fixture is the real NRC table (fetched 2026-10-10). The
# status file fixture is built from the same unit names in the documented
# "ReportDt|Unit|Power" format, because NRC's CDN blocked the real file
# when this was written.
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
    assert_equal "nrc_power_status", status_source.source_kind, "the status file is never extracted"
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
    assert list_source.crawl_ok?
  end
end
