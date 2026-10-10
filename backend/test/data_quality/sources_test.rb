require "test_helper"

class DataQuality::SourcesTest < ActiveSupport::TestCase
  test "creates a source and returns a plain ref" do
    result = DataQuality::Sources.find_or_create(url: " https://example.com/new ", published_on: Date.new(2026, 1, 2))

    assert result.ok?
    assert_kind_of DataQuality::Sources::SourceRef, result.ref
    assert_equal [ "https://example.com/new", "web_page" ], [ result.ref.url, result.ref.source_kind ]
    assert_equal Date.new(2026, 1, 2), Source.find(result.ref.id).published_on
  end

  test "reuses an existing source, keeping its kind and filling only a missing date" do
    nrc = sources(:nrc)

    result = DataQuality::Sources.find_or_create(url: nrc.url, source_kind: "web_page", published_on: Date.new(2026, 5, 1))

    assert_equal nrc.id, result.ref.id
    assert_equal "nrc_reactor_list", result.ref.source_kind
    assert_equal Date.new(2026, 5, 1), nrc.reload.published_on
  end

  test "refuses anything but an absolute http or https address, and saves nothing" do
    [
      "javascript:alert(1)",
      "JavaScript:alert(document.cookie)",
      "data:text/html,<script>alert(1)</script>",
      "/news/relative-path",
      "example.com/no-scheme",
      "ftp://example.com/file.txt",
      "https://",
      "http://exa mple.com/space",
      "https://example.com/has space",
      "ht!tp://bad scheme"
    ].each do |url|
      assert_no_difference -> { Source.count }, url do
        result = DataQuality::Sources.find_or_create(url: url)

        assert_not result.ok?, url
        assert_nil result.ref
        assert_match "absolute http or https address", result.errors.join, url
      end
    end
  end

  test "accepts ordinary web addresses, including encoded characters and ports" do
    %w[
      http://example.com
      https://www.energy.gov/sites/default/files/2024-02/HALEU%20DEIS%20Volume%201_March%202024.pdf
      https://example.com:8443/path?q=1#section
    ].each { |url| assert DataQuality::Sources.find_or_create(url: url).ok?, url }
  end
end
