require "test_helper"
require_relative "../support/directory_builders"

class PagesTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  test "about, privacy, disclaimer and the crawler page are linked from every page's footer" do
    get root_path
    assert_select "footer.nd-footer nav[aria-label='About this site']" do
      assert_select "a[href='/about']", "About"
      assert_select "a[href='/privacy']", "Privacy"
      assert_select "a[href='/disclaimer']", "Disclaimer"
      assert_select "a[href='/bot']", "Our crawler"
      assert_select "a[href='mailto:hello@nuclear-directory.org']"
    end

    { about_path => "About", privacy_path => "Privacy", disclaimer_path => "Disclaimer", bot_path => "NuclearDirectoryBot" }.each do |path, heading|
      get path
      assert_response :success
      assert_select "main", 1
      assert_select "h1", heading
      assert_select "meta[name=description]"
    end
  end

  test "the about page says how facts are checked and counts what's listed today" do
    kairos = company("Kairos Power")
    company("Hidden Co", verified: false)
    plant("Plant Vogtle")
    plant("Hidden Site", verified: false)
    kairos.update_columns(verified_at: Time.zone.parse("2026-10-09 12:00"))

    get about_path

    assert_select "title", "About · Nuclear Directory"
    assert_select "link[rel=canonical][href='http://www.example.com/about']"
    assert_select "h2#checking", "How we check facts"
    assert_select "section[aria-labelledby=checking]", /Software, including AI models, reads public pages and suggests new facts. Nothing is published until a person has checked it against the source./
    assert_select "a[href='/disclaimer']", "disclaimer"
    assert_select "main a[href='/privacy']", "privacy policy"
    assert_select "main a[href='mailto:hello@nuclear-directory.org']"
    assert_select "p.type-data-sm", /1 companies · 1 plants and sites · updated 2026-10-09/
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
    assert_includes response.body, "<loc>http://www.example.com/about</loc>"
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
