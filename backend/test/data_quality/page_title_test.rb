require "test_helper"

class DataQuality::PageTitleTest < ActiveSupport::TestCase
  def title(body, content_type: "text/html; charset=utf-8") = DataQuality::PageTitle.from(body, content_type:)

  test "reads <title>, tidying whitespace and decoding entities" do
    html = "<html><head><title>\n  Kairos Power &amp; TVA   sign\n deal | Kairos Power </title></head></html>"

    assert_equal "Kairos Power & TVA sign deal | Kairos Power", title(html)
  end

  test "falls back to og:title" do
    html = '<html><head><meta property="og:title" content="X-energy picks Texas site"></head></html>'

    assert_equal "X-energy picks Texas site", title(html)
  end

  test "no title, no HTML, no answer" do
    assert_nil title("<html><head><title>  </title></head><body>Hi</body></html>")
    assert_nil title("%PDF-1.7 …", content_type: "application/pdf")
    assert_nil title("ReportDt|Unit|Power", content_type: "text/plain")
  end

  test "recognises HTML without a content type" do
    assert_equal "Untyped", title("<!DOCTYPE html><html><title>Untyped</title></html>", content_type: nil)
  end

  test "cuts very long titles at a word" do
    long = title("<title>#{'word ' * 200}</title>")

    assert long.length <= DataQuality::PageTitle::MAX_LENGTH
    assert long.end_with?("...")
  end
end
