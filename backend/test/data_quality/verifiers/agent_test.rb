require "test_helper"
require_relative "../support/dummy_plugin"

class DataQuality::Verifiers::AgentTest < ActiveSupport::TestCase
  Agent = DataQuality::Verifiers::Agent

  # Stands in for the verifier model: answers each claim with whatever
  # `decide` returns for it, and checks its answer against the real schema.
  class FakeModel
    Response = Data.define(:data)
    attr_reader :calls

    def initialize(&decide)
      @decide = decide || ->(_claim) { { "verdict" => "supported", "confidence" => 0.95, "reason" => "The excerpt says so." } }
      @calls = []
    end

    def structured(role:, messages:, schema:, schema_name:, crawl_run:, reasoning_effort: nil)
      claims = JSON.parse(messages.last[:content].split("Claims:\n", 2).last)
      @calls << { role:, reasoning_effort:, claims:, content: messages.last[:content] }
      results = claims.filter_map { |claim| (answer = @decide.call(claim)) && { "source_value" => "" }.merge(answer, "id" => claim["id"]) }
      errors = JSONSchemer.schema(schema).validate({ "results" => results }).to_a
      raise "fake answered outside the schema: #{errors.first["error"]}" if errors.any?

      Response.new(data: { "results" => results })
    end
  end

  setup do
    @source = Source.create!(url: DummyPlugin::URL, source_kind: "dummy", crawl_status: "ok", title: "Dummy press release",
      content_text: DummyPlugin::TEXT)
    @run = CrawlRun.create!(stage: "verify", source_kind: "dummy")
  end

  def candidate(name) = Candidate.create!(source: @source, kind: "organization", payload: { "name" => name }, quote: name)
  def verdicts(model, candidates) = Agent.new(llm: model).verdicts(candidates, run: @run, plugin: DummyPlugin.new)

  test "publishes what the model confirms with enough confidence" do
    acme = candidate("Acme Nuclear")
    model = FakeModel.new

    verdict = verdicts(model, [ acme ]).fetch(acme.id)

    assert_equal [ :publish, 0.95 ], [ verdict.outcome, verdict.confidence ]
    assert_equal "verify-v3", @run.reload.prompt_version
    call = model.calls.sole
    assert_equal [ :verify, "low" ], [ call[:role], call[:reasoning_effort] ]
    assert_equal "There is a company named “Acme Nuclear”.", call[:claims].sole["claim"]
    assert_includes call[:claims].sole["excerpt"], "Acme Nuclear and NewCo Fission signed"
  end

  test "anything short of a confident yes goes to review, with the model's reason" do
    answers = {
      "Unsure Co" => { "verdict" => "supported", "confidence" => 0.6, "reason" => "Only hinted at." },
      "Wrong Co" => { "verdict" => "contradicted", "confidence" => 0.9, "reason" => "The excerpt names someone else.",
                     "source_value" => "Other Co" },
      "Vague Co" => { "verdict" => "not_enough_info", "confidence" => 0.2, "reason" => "Not mentioned." }
    }
    candidates = answers.keys.map { |name| candidate(name) }

    results = verdicts(FakeModel.new { |claim| answers.find { |name, _| claim["claim"].include?(name) }.last }, candidates)

    assert results.values.all? { |verdict| verdict.outcome == :review }, "never published, never rejected"
    assert_match "only 60% sure: Only hinted at.", results[candidates[0].id].reason
    assert_match "contradicts this (the source gives Other Co): The excerpt names someone else.", results[candidates[1].id].reason
    assert_match "couldn't confirm this from the source: Not mentioned.", results[candidates[2].id].reason
  end

  test "contradicted counts only when the model names a value the claim doesn't have" do
    acme = Candidate.create!(source: @source, kind: "facility", quote: "Acme Nuclear",
      payload: { "name" => "Acme 1", "latitude" => "37.1661", "longitude" => "-76.6986", "capacity_mw" => "838.0" })
    said = ->(value) do
      model = FakeModel.new { { "verdict" => "contradicted", "confidence" => 0.9, "reason" => "Looks off.", "source_value" => value } }
      verdicts(model, [ acme ]).fetch(acme.id)
    end

    [ "", "  ", "-76.6986", "-76.698599999999999", "838", "Acme 1" ].each do |value|
      verdict = said.call(value)
      assert_equal :review, verdict.outcome
      assert_match "couldn't confirm this from the source (it named no different value): Looks off.", verdict.reason, value.inspect
    end

    [ "-76.70", "850", "Acme 2" ].each do |value|
      assert_match "contradicts this (the source gives #{value}): Looks off.", said.call(value).reason, value.inspect
    end
  end

  test "what the whole source states is sent with its claims, only when the plug-in says something" do
    plugin = Class.new(DummyPlugin) { def source_facts(_source) = "Every row is a reactor." }.new
    model = FakeModel.new

    Agent.new(llm: model).verdicts([ candidate("Acme Nuclear") ], run: @run, plugin: plugin)
    verdicts(model, [ candidate("NewCo Fission") ])

    with, without = model.calls.map { |call| call[:content] }
    assert_includes with, "What the whole source states: Every row is a reactor.\n\nClaims:"
    assert_not_includes without, "What the whole source states"
  end

  test "a claim the model doesn't answer goes to review" do
    acme = candidate("Acme Nuclear")

    verdict = verdicts(FakeModel.new { |_claim| nil }, [ acme ]).fetch(acme.id)

    assert_equal :review, verdict.outcome
    assert_match "gave no answer", verdict.reason
  end

  test "asks in batches" do
    candidates = 32.times.map { |i| candidate("Company #{i}") }
    model = FakeModel.new

    results = verdicts(model, candidates)

    assert_equal [ 15, 15, 2 ], model.calls.map { |call| call[:claims].size }
    assert_equal candidates.map(&:id).sort, results.keys.sort
  end

  test "the threshold is checked before rounding: 79.5% sure is under 80%" do
    c = candidate("Acme Nuclear")

    verdict = verdicts(FakeModel.new { { "verdict" => "supported", "confidence" => 0.795, "reason" => "Close." } }, [ c ]).fetch(c.id)

    assert_equal :review, verdict.outcome
    assert_match "only 79% sure", verdict.reason
    assert_equal 0.79, verdict.confidence, "stored rounded down, so it never reads as 80%"
  end

  test "a confidence outside 0 to 1 is a malformed answer, sent to review rather than clamped" do
    c = candidate("Acme Nuclear")
    # Past the fake's schema check, as a provider that ignores the range might answer.
    answer = { "id" => c.id.to_s, "verdict" => "supported", "confidence" => 2, "reason" => "Sure." }
    model = Struct.new(:answer) do
      def structured(**) = FakeModel::Response.new(data: { "results" => [ answer ] })
    end.new(answer)

    verdict = verdicts(model, [ c ]).fetch(c.id)

    assert_equal [ :review, nil ], [ verdict.outcome, verdict.confidence ]
    assert_match "invalid confidence (2)", verdict.reason
  end

  test "a source with nothing stored goes to review without asking the model" do
    @source.update!(content_text: nil)
    c = candidate("Acme Nuclear")
    model = FakeModel.new

    verdict = verdicts(model, [ c ]).fetch(c.id)

    assert_empty model.calls
    assert_equal :review, verdict.outcome
    assert_match "no stored content", verdict.reason
  end

  test "is the default verifier" do
    assert_instance_of Agent, DataQuality::Stages::Verify.new(plugin: DummyPlugin.new).instance_variable_get(:@verifier)
  end
end
