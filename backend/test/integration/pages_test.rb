require "test_helper"
require_relative "../support/directory_builders"

class PagesTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  test "the privacy page says what analytics records, and that PostHog doesn't store IP addresses (#203)" do
    get privacy_path

    assert_select "meta[name=description][content*=?]", "dead clicks, the country you're visiting from"
    assert_select "h2#counts", "Analytics"
    assert_select "#counts + p", /page views, searches .*how long a page stays open, and dead clicks/m
    assert_select "#counts ~ p", /cookieless mode.*no session recordings/m
    # #205: we look up the country and send only that; PostHog uses the IP to count visitors and drops it.
    assert_select "#counts ~ p", /country you're in from your IP address, on this site's server, and send PostHog only the country/
    assert_select "#counts ~ p", /uses only to count unique visitors, and it doesn't store the IP address/
    assert_select "#counts ~ p a[href='https://db-ip.com']", "IP Geolocation by DB-IP"
    assert_select "#counts ~ p", /go through this site rather than straight to PostHog/
    assert_select "p", /Last updated\s+2026-10-12/
    assert_no_match(/set to discard IP addresses/, response.body)
  end

  test "privacy, disclaimer and the crawler page are linked from every page's footer" do
    get root_path
    assert_select "footer.nd-footer nav[aria-label='About this site']" do
      assert_select "a[href='/privacy']", "Privacy"
      assert_select "a[href='/disclaimer']", "Disclaimer"
      assert_select "a[href='/bot']", "Our crawler"
      assert_select "a[href='mailto:hello@nuclear-directory.org']"
    end

    { privacy_path => "Privacy", disclaimer_path => "Disclaimer", bot_path => "NuclearDirectoryBot" }.each do |path, heading|
      get path
      assert_response :success
      assert_select "main", 1
      assert_select "h1", heading
      assert_select "meta[name=description]"
    end
  end

  test "the crawler page shows the user agent the crawler actually sends" do
    get bot_path

    assert_select "pre", DataQuality::Fetcher::USER_AGENT
    assert_select "pre", /User-agent: NuclearDirectoryBot\s+Disallow: \//
    assert_equal "https://nuclear-directory.org/bot", DataQuality::Fetcher::USER_AGENT[/\(\+(\S+)\)/, 1]
  end

  test "the sitemap lists public companies and plants, not hidden ones" do
    company("Kairos Power")
    company("Hidden Co", verified: false)
    company("Unpublished Co").unpublish!(by: "human:test")
    plant("Plant Vogtle")
    plant("Hidden Site", verified: false)

    get "/sitemap.xml"

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, "<loc>http://www.example.com/companies/kairos-power</loc>"
    assert_includes response.body, "<loc>http://www.example.com/plants/plant-vogtle</loc>"
    assert_includes response.body, "<loc>http://www.example.com/companies?category=reactor-developers</loc>"
    assert_not_includes response.body, "<lastmod>"
    assert_not_includes response.body, "hidden"
    assert_not_includes response.body, "unpublished-co"
  end

  test "robots.txt keeps crawlers out of admin, forms and search, and points to the sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_equal "text/plain", response.media_type
    %w[/admin /corrections /search /design].each { |path| assert_includes response.body, "Disallow: #{path}\n" }
    assert_includes response.body, "Sitemap: http://www.example.com/sitemap.xml"
  end
end
