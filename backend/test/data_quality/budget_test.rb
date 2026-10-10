require "test_helper"

class DataQuality::BudgetTest < ActiveSupport::TestCase
  def spend(cost, at: Time.current)
    CrawlRun.create!(stage: "extract", source_kind: "dummy", started_at: at, status: "succeeded",
      stats: { "llm" => { "calls" => 4, "total_tokens" => 12_000, "cost" => cost } })
  end

  test "adds up this month's model cost, ignoring last month's and runs without model calls" do
    spend(1.25)
    spend(0.75)
    spend(9.0, at: 1.month.ago)
    CrawlRun.create!(stage: "crawl", source_kind: "dummy")

    assert_in_delta 2.0, DataQuality::Budget.spent_this_month
  end

  test "refuses once the budget is used up, saying why" do
    spend(4.99)
    assert_nothing_raised { DataQuality::Budget.check!(5.0) }

    spend(0.02)
    error = assert_raises(DataQuality::Budget::Exceeded) { DataQuality::Budget.check!(5.0) }
    assert_match "Monthly model budget of $5.00 is used up ($5.0100 spent", error.message
    assert_match "DATA_QUALITY_MONTHLY_BUDGET", error.message
  end

  test "the client makes no call once the budget is used up, and the run fails visibly" do
    spend(5.5)
    config = DataQuality::Config.new(api_key: "test-key", extract_model: "a/x", verify_model: "b/y", monthly_budget: 5.0)
    client = DataQuality::OpenRouter::Client.new(config: config, sleeper: ->(_) { })
    run = CrawlRun.create!(stage: "extract", source_kind: "dummy")

    assert_raises(DataQuality::Budget::Exceeded) do
      client.structured(role: :extract, messages: [ { role: "user", content: "hi" } ], crawl_run: run,
        schema: { "type" => "object", "properties" => {}, "additionalProperties" => false })
    end
    assert_not_requested :post, DataQuality::OpenRouter::Client::ENDPOINT.to_s
  end

  test "the budget comes from DATA_QUALITY_MONTHLY_BUDGET, $5 by default" do
    assert_equal 5.0, DataQuality::Config.from_env({}).monthly_budget
    assert_equal 2.5, DataQuality::Config.from_env("DATA_QUALITY_MONTHLY_BUDGET" => "2.5").monthly_budget
  end
end
