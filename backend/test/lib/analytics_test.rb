require "test_helper"
require_relative "../support/fake_posthog"

class AnalyticsTest < ActiveSupport::TestCase
  include AnalyticsTestHelper

  test "every event is anonymous: one shared id, no person profile, no IP or GeoIP" do
    Analytics.capture("company_viewed", slug: "terrapower")

    event = posthog.events.sole
    assert_equal "anonymous", event[:distinct_id]
    assert_equal "company_viewed", event[:event]
    assert_equal({ "slug" => "terrapower", "$process_person_profile" => false, "$geoip_disable" => true, "$ip" => nil },
      event[:properties])
  end

  test "searches are normalized and zero-result searches are flagged" do
    Analytics.track_search("  TerraPower ", results: 3)
    Analytics.track_search("sodium supplier", results: 0)

    first, second = posthog.events.map { |e| e[:properties].slice("query", "results", "zero_results") }
    assert_equal({ "query" => "terrapower", "results" => 3, "zero_results" => false }, first)
    assert_equal({ "query" => "sodium supplier", "results" => 0, "zero_results" => true }, second)
  end

  test "blank searches aren't sent and long ones are capped" do
    Analytics.track_search("   ", results: 0)
    Analytics.track_search("x" * 500, results: 1)

    assert_equal [ 200 ], posthog.events.map { |e| e[:properties]["query"].length }
  end

  test "only known events can be sent" do
    assert_raises(ArgumentError) { Analytics.capture("clicked_ad") }
  end

  test "a PostHog failure never raises" do
    Analytics.client = FakePostHog.new(fail_with: Errno::ECONNREFUSED.new)
    assert_nil Analytics.capture("search", query: "x")
  end

  test "without a client nothing is sent and no key is exposed" do
    Analytics.client = nil

    assert_not Analytics.enabled?
    assert_nil Analytics.public_key
    assert_nil Analytics.capture("search", query: "x")
  end

  test "the host defaults to PostHog US" do
    previous = ENV.delete("POSTHOG_HOST")
    assert_equal "https://us.i.posthog.com", Analytics.host
  ensure
    ENV["POSTHOG_HOST"] = previous
  end
end
