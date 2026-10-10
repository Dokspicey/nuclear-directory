require "test_helper"
require_relative "../support/dummy_plugin"

# Verify's code-first step: a candidate whose quote isn't in its source
# goes to review without any model being asked.
class DataQuality::Stages::VerifyQuoteTest < ActiveSupport::TestCase
  # Records what it was asked; answers in a batch like the agent does.
  class BatchVerifier
    attr_reader :asked

    def initialize(outcome: :review, fail: false)
      @outcome = outcome
      @fail = fail
    end

    def verdicts(candidates, run:, plugin:)
      raise DataQuality::OpenRouter::Client::RetriesExhausted, "Gave up after 3 attempts" if @fail

      @asked = candidates.map(&:quote)
      candidates.to_h { |c| [ c.id, DataQuality::Verdict.new(outcome: @outcome, confidence: 0.9, reason: "checked") ] }
    end
  end

  setup do
    @source = Source.create!(url: "https://example.com/quote-test", source_kind: "dummy", crawl_status: "ok",
      content_text: "<html><body><p>Acme <b>Nuclear</b>   signed with\nNewCo Fission.</p></body></html>")
  end

  def candidate(quote) = Candidate.create!(source: @source, kind: "organization", payload: { "name" => quote }, quote: quote)
  def verify(verifier) = DataQuality::Stages::Verify.call(plugin: DummyPlugin.new, verifier: verifier)

  test "a made-up quote goes to review and the verifier isn't asked about it" do
    real = candidate("Acme Nuclear signed with NewCo Fission")
    made_up = candidate("Acme Nuclear bought NewCo Fission")
    verifier = BatchVerifier.new

    run = verify(verifier)

    assert_equal [ real.quote ], verifier.asked, "quotes are matched against the page's visible text"
    assert made_up.reload.status_needs_review?
    assert_match "cited quote isn't in the source", made_up.notes
    assert_equal 1, run.stats["quote_missing"]
    assert_equal "checked", real.reload.notes
  end

  test "if the verifier fails, nothing is changed, not even the made-up quotes" do
    real = candidate("Acme Nuclear")
    made_up = candidate("Imaginary quote")

    assert_raises(DataQuality::OpenRouter::Client::RetriesExhausted) { verify(BatchVerifier.new(fail: true)) }

    assert [ real, made_up ].all? { |c| c.reload.status_new? }
    assert CrawlRun.where(stage: "verify").sole.failed?
  end

  test "table cells don't run together in a page's visible text" do
    @source.update!(content_text: "<html><body><table><tr><td><a>Vogtle 3</a><br>05200025</td><td>PWR</td></tr></table></body></html>")
    row = candidate("Vogtle 3 05200025 PWR")
    verifier = BatchVerifier.new

    verify(verifier)

    assert_equal [ row.quote ], verifier.asked
  end

  test "a candidate whose source has no stored content goes straight to the verifier" do
    @source.update!(content_text: nil)
    hand_made = candidate("Anything at all")
    verifier = BatchVerifier.new

    verify(verifier)

    assert_equal [ hand_made.quote ], verifier.asked
  end
end
