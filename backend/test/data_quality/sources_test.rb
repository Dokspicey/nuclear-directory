require "test_helper"

class DataQuality::SourcesTest < ActiveSupport::TestCase
  test "creates a source and returns a plain ref" do
    ref = DataQuality::Sources.find_or_create(url: " https://example.com/new ", published_on: Date.new(2026, 1, 2))

    assert_kind_of DataQuality::Sources::SourceRef, ref
    assert_equal [ "https://example.com/new", "web_page" ], [ ref.url, ref.source_kind ]
    assert_equal Date.new(2026, 1, 2), Source.find(ref.id).published_on
  end

  test "reuses an existing source, keeping its kind and filling only a missing date" do
    nrc = sources(:nrc)

    ref = DataQuality::Sources.find_or_create(url: nrc.url, source_kind: "web_page", published_on: Date.new(2026, 5, 1))

    assert_equal nrc.id, ref.id
    assert_equal "nrc_reactor_list", ref.source_kind
    assert_equal Date.new(2026, 5, 1), nrc.reload.published_on
  end
end
