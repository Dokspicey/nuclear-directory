require "test_helper"
require_relative "../support/directory_builders"
require_relative "../support/fake_posthog"

# The filter sheet's count (#90) asks /companies.json; that isn't a search,
# so it must never reach analytics.
class DirectoryCountTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders
  include AnalyticsTestHelper

  BROWSER = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  setup { company("Kairos Power", roles: [ role("reactor_vendor") ]) }

  test "a count request returns the count and records no search" do
    get companies_path(q: "kairos", format: :json), headers: { "User-Agent" => BROWSER }

    assert_equal({ "count" => 1 }, response.parsed_body)
    assert_empty posthog.events
  end

  test "the same search as a page is recorded, so the check above means something" do
    get companies_path(q: "kairos"), headers: { "User-Agent" => BROWSER }

    assert_equal [ "search" ], posthog.events.map { |event| event[:event] }
  end
end
