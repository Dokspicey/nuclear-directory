require "test_helper"

class DataQuality::FetcherTest < ActiveSupport::TestCase
  PAGE = "https://example.gov/reactors"
  ROBOTS = "https://example.gov/robots.txt"

  setup do
    @sleeps = []
    @now = 0.0
    @fetcher = DataQuality::Fetcher.new(sleeper: ->(s) { @sleeps << s; @now += s }, clock: -> { @now })
    stub_request(:get, ROBOTS).to_return(body: "User-agent: *\nDisallow: /private/\n")
  end

  test "identifies itself honestly and returns the page with its validators" do
    stub = stub_request(:get, PAGE)
      .with(headers: { "User-Agent" => "NuclearDirectoryBot/0.1 (+https://nuclear-directory.org/bot)" })
      .to_return(body: "<p>hi</p>", headers: { "ETag" => '"v1"', "Last-Modified" => "Fri, 09 Oct 2026 20:40:21 GMT",
        "Content-Type" => "text/html; charset=utf-8" })

    response = @fetcher.get(PAGE)

    assert_requested stub
    assert_equal [ :ok, 200, "<p>hi</p>", '"v1"' ], [ response.kind, response.status, response.body, response.etag ]
    assert_equal Encoding::UTF_8, response.body.encoding
    assert_equal [ "text/html", false ], [ response.content_type, response.truncated ]
  end

  test "stops reading at max_bytes and says so" do
    stub_request(:get, PAGE).to_return(body: "a" * 5_000)

    response = @fetcher.get(PAGE, max_bytes: 1_000)

    assert_equal :ok, response.kind
    assert response.truncated
    assert_equal 1_000, response.body.bytesize
  end

  test "a body of exactly max_bytes is complete, not truncated" do
    stub_request(:get, PAGE).to_return(body: "a" * 1_000)

    response = @fetcher.get(PAGE, max_bytes: 1_000)

    assert_not response.truncated
    assert_equal 1_000, response.body.bytesize
  end

  test "asks whether the page changed and understands 304" do
    stub = stub_request(:get, PAGE)
      .with(headers: { "If-None-Match" => '"v1"', "If-Modified-Since" => "Fri, 09 Oct 2026 20:40:21 GMT" })
      .to_return(status: 304)

    response = @fetcher.get(PAGE, etag: '"v1"', last_modified: "Fri, 09 Oct 2026 20:40:21 GMT")

    assert_requested stub
    assert_equal :not_modified, response.kind
  end

  test "reports a block with Akamai's reference id, and doesn't retry" do
    stub_request(:get, PAGE).to_return(status: 403, body: file_fixture("nrc/akamai-403.html").read,
      headers: { "Server" => "AkamaiGHost" })

    response = @fetcher.get(PAGE)

    assert_equal :blocked, response.kind
    assert_equal "18.4460d017.1791618638.14c00ece", response.block_reference
    assert_match "HTTP 403 from AkamaiGHost, reference #18.4460d017", response.reason
    assert_requested :get, PAGE, times: 1
  end

  test "prefers the reference header when there is one" do
    stub_request(:get, PAGE).to_return(status: 403, headers: { "X-Reference-Error" => "18.abc" }, body: "Access Denied")

    assert_equal "18.abc", @fetcher.get(PAGE).block_reference
  end

  test "never fetches what robots.txt disallows" do
    response = @fetcher.get("https://example.gov/private/page")

    assert_equal :disallowed, response.kind
    assert_not_requested :get, "https://example.gov/private/page"
  end

  test "reads robots.txt once per host and waits between requests to it" do
    stub_request(:get, PAGE).to_return(body: "a")
    stub_request(:get, "#{PAGE}/2").to_return(body: "b")

    @fetcher.get(PAGE)
    @fetcher.get("#{PAGE}/2")

    assert_requested :get, ROBOTS, times: 1
    assert_equal [ DataQuality::Fetcher::HOST_INTERVAL ] * 2, @sleeps
  end

  test "robots.txt is per origin: a redirect to another scheme or port reads that origin's file" do
    stub_request(:get, "http://example.gov/robots.txt").to_return(body: "User-agent: *\nDisallow: /\n")
    stub_request(:get, "https://example.gov:8443/robots.txt").to_return(body: "User-agent: *\nDisallow: /\n")
    stub_request(:get, PAGE).to_return(status: 301, headers: { "Location" => "http://example.gov/reactors" })

    assert_equal :disallowed, @fetcher.get(PAGE).kind, "http:// has its own robots.txt"
    assert_equal :disallowed, @fetcher.get("https://example.gov:8443/reactors").kind, "so does a non-default port"
    assert_requested :get, "https://example.gov:8443/robots.txt"
  end

  test "follows redirects, checking robots.txt for the new location" do
    stub_request(:get, PAGE).to_return(status: 301, headers: { "Location" => "/private/moved" })

    response = @fetcher.get(PAGE)

    assert_equal :disallowed, response.kind
    assert_match "/private/moved", response.reason
  end

  test "a missing robots.txt allows everything; a blocked or broken one stops the crawl" do
    stub_request(:get, ROBOTS).to_return(status: 404)
    stub_request(:get, PAGE).to_return(body: "ok")
    assert_equal :ok, @fetcher.get(PAGE).kind

    blocked = DataQuality::Fetcher.new(sleeper: ->(_) { })
    stub_request(:get, ROBOTS).to_return(status: 403, body: file_fixture("nrc/akamai-403.html").read)
    assert_equal :blocked, blocked.get(PAGE).kind

    broken = DataQuality::Fetcher.new(sleeper: ->(_) { })
    stub_request(:get, ROBOTS).to_return(status: 503)
    response = broken.get(PAGE)
    assert_equal :error, response.kind
    assert_match "not crawling", response.reason
  end

  test "server errors and timeouts are reported, not raised" do
    stub_request(:get, PAGE).to_return(status: 500).then.to_timeout

    assert_equal [ :error, 500 ], @fetcher.get(PAGE).then { |r| [ r.kind, r.status ] }
    assert_equal :error, @fetcher.get(PAGE).kind
  end
end
