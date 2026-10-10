require "test_helper"

# How verify checks NRC candidates: quotes are table rows, and the verifier
# reads the header plus the row.
class DataQuality::Plugins::NrcReactorList::VerifyTest < ActiveSupport::TestCase
  Plugin = DataQuality::Plugins::NrcReactorList
  ROW = "Vogtle 3 | 05200025 | NPF-91 | PWR | 26 miles SE of Augusta, GA | Southern Nuclear Operating Co. | 2"

  setup do
    html = file_fixture("nrc/list-power-reactor-units.html").read
    @source = Source.create!(url: Plugin::LIST_URL, source_kind: "nrc_reactor_list", crawl_status: "ok",
      content_text: html, content_sha256: Digest::SHA256.hexdigest(html))
    @plugin = Plugin.new(fetcher: nil)
  end

  test "a quote must be a whole row of the table" do
    assert @plugin.quote_in_source?(@source, ROW)
    assert_not @plugin.quote_in_source?(@source, ROW.sub("PWR", "BWR"))
    assert_not @plugin.quote_in_source?(@source, "Vogtle 3 | 05200025"), "a fragment isn't a row"
  end

  test "the verifier reads the header and the row" do
    assert_equal "Plant Name | Docket Number | License Number | Reactor Type | Location | Owner/Operator | NRC Region\n#{ROW}",
      @plugin.verification_context(@source, ROW)
  end

  test "verify sends a candidate with an altered row to review without asking the model" do
    Candidate.create!(source: @source, kind: "facility", quote: ROW.sub("PWR", "BWR"),
      payload: { "name" => "Vogtle 3", "nrc_docket" => "05200025" })
    asked = []
    verifier = Object.new
    verifier.define_singleton_method(:call) { |c| asked << c; DataQuality::Verdict.new(outcome: :publish, confidence: 1) }

    run = DataQuality::Stages::Verify.call(plugin: @plugin, verifier:)

    assert_empty asked
    assert_equal 1, run.stats["quote_missing"]
  end
end
