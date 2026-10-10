require "test_helper"

class CrawlRunTest < ActiveSupport::TestCase
  test "starts running and records when it finishes" do
    run = CrawlRun.create!(stage: "extract", source_kind: "web_page", model: "anthropic/claude-sonnet-5.5")
    assert run.running?
    assert run.started_at

    run.finish!(stats: { "in" => 10, "out" => 7 })
    assert run.succeeded?
    assert_equal 7, run.reload.stats["out"]
    assert run.finished_at
  end

  test "failure keeps the error" do
    run = CrawlRun.create!(stage: "crawl")
    run.fail!("HTTP 403")
    assert run.failed?
    assert_equal "HTTP 403", run.error
  end

  test "stage must be a known value" do
    assert_not CrawlRun.new(stage: "dream").valid?
  end
end
