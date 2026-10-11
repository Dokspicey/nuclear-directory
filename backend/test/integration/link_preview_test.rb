require "test_helper"
require_relative "../support/directory_builders"

class LinkPreviewTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  test "every public page carries the shared preview image, once" do
    company("Kairos Power")
    [ root_path, companies_path, company_path(slug: "kairos-power"), privacy_path ].each do |path|
      get path

      assert_select "meta[property='og:image']", 1
      assert_select "meta[property='og:image'][content^='http://www.example.com/assets/og-default-'][content$='.png']"
      assert_select "meta[property='og:image:width'][content='1200']"
      assert_select "meta[property='og:image:height'][content='630']"
      assert_select "meta[property='og:image:alt']"
      assert_select "meta[name='twitter:card'][content=summary_large_image]"
      assert_select "meta[property='og:site_name']", 1
      assert_select "meta[property='og:title']", 1
      assert_select "meta[property='og:description']", 1
      assert_select "meta[property='og:type'][content=website]", 1
      assert_select "meta[property='og:url'][content=?]", "http://www.example.com#{path.split("?").first}"
    end
  end

  test "a page's own title and description lead its preview; others fall back to the site's" do
    get privacy_path
    assert_select "meta[property='og:title'][content=?]", "Privacy · Nuclear Directory"
    assert_select "meta[property='og:description'][content^='Who makes the fuel']"
  end

  test "a company with nothing to summarize still says what its page holds" do
    company("Kairos Power")
    get company_path(slug: "kairos-power")
    assert_select "meta[property='og:title'][content=?]", "Kairos Power"
    assert_select "meta[property='og:description'][content=?]", "Plants and sites, deals and sources."
  end

  test "a category keeps its own preview address; search and filters don't" do
    get companies_path(category: "reactor-developers", state: "CA", q: "x")
    assert_select "meta[property='og:url'][content=?]", "http://www.example.com/companies?category=reactor-developers"

    get companies_path(category: "not-a-category")
    assert_select "meta[property='og:url'][content=?]", "http://www.example.com/companies"

    company("Kairos Power")
    get company_path(slug: "kairos-power", category: "fuel")
    assert_select "meta[property='og:url'][content=?]", "http://www.example.com/companies/kairos-power"
  end

  test "the preview image is served" do
    get ActionController::Base.helpers.image_path("og-default.png")
    assert_response :success
    assert_equal "image/png", response.media_type
  end
end
