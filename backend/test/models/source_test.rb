require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "domain comes from the url" do
    source = Source.create!(url: "https://www.Energy.gov/ne/articles/x", source_kind: "web_page")
    assert_equal "energy.gov", source.domain
    assert source.crawl_pending?
  end

  test "url is unique" do
    dup = Source.new(url: sources(:nrc).url, source_kind: "web_page")
    assert_not dup.valid?
  end

  test "a source with evidence can't be deleted" do
    Evidence.create!(subject: organizations(:terrapower), source: sources(:nrc), found_by: "crawler")
    assert_not sources(:nrc).destroy
  end
end
