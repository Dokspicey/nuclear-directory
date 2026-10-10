# A source plug-in that "crawls" one fixed page and extracts two facts:
# an organization the directory already has, and a new one.
class DummyPlugin < DataQuality::Plugin
  URL = "https://example.com/dummy-source"
  TEXT = "Acme Nuclear and NewCo Fission signed a fuel supply agreement."

  def source_kind = "dummy"

  def crawl(_run)
    source = Source.find_or_initialize_by(url: URL)
    source.update!(source_kind: source_kind, crawl_status: "ok", content_text: TEXT,
      content_sha256: Digest::SHA256.hexdigest(TEXT), fetched_at: Time.current, http_status: 200)
    { "fetched" => 1 }
  end

  def extract(source, _run)
    [
      { kind: "organization", payload: { "name" => "Acme Nuclear" }, quote: "Acme Nuclear" },
      { kind: "organization", payload: { "name" => "NewCo Fission" }, quote: "NewCo Fission" }
    ]
  end
end

# Verifier that publishes everything, for exercising the publish path.
class PublishEverything
  def call(_candidate)
    DataQuality::Verdict.new(outcome: :publish, confidence: 0.9)
  end
end
