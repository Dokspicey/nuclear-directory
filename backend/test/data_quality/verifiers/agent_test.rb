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
      @calls << { role:, reasoning_effort:, claims: }
      results = claims.filter_map { |claim| (answer = @decide.call(claim)) && answer.merge("id" => claim["id"]) }
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
    assert_equal "verify-v1", @run.reload.prompt_version
    call = model.calls.sole
    assert_equal [ :verify, "low" ], [ call[:role], call[:reasoning_effort] ]
    assert_equal 'There is an organization named "Acme Nuclear".', call[:claims].sole["claim"]
    assert_includes call[:claims].sole["excerpt"], "Acme Nuclear and NewCo Fission signed"
  end

  test "anything short of a confident yes goes to review, with the model's reason" do
    answers = {
      "Unsure Co" => { "verdict" => "supported", "confidence" => 0.6, "reason" => "Only hinted at." },
      "Wrong Co" => { "verdict" => "contradicted", "confidence" => 0.9, "reason" => "The excerpt names someone else." },
      "Vague Co" => { "verdict" => "not_enough_info", "confidence" => 0.2, "reason" => "Not mentioned." }
    }
    candidates = answers.keys.map { |name| candidate(name) }

    results = verdicts(FakeModel.new { |claim| answers.find { |name, _| claim["claim"].include?(name) }.last }, candidates)

    assert results.values.all? { |verdict| verdict.outcome == :review }, "never published, never rejected"
    assert_match "only 60% sure: Only hinted at.", results[candidates[0].id].reason
    assert_match "contradicts this: The excerpt names someone else.", results[candidates[1].id].reason
    assert_match "couldn't confirm this from the source: Not mentioned.", results[candidates[2].id].reason
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

  test "is the default verifier" do
    assert_instance_of Agent, DataQuality::Stages::Verify.new(plugin: DummyPlugin.new).instance_variable_get(:@verifier)
  end
end
