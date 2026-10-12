require "test_helper"
require_relative "../support/fake_posthog"
require_relative "../support/fake_geo_reader"

# The request-level rules (TracksAnalytics): bots and non-public paths are
# never tracked, and the browser snippet only appears on public pages.
class AnalyticsTrackingTest < ActionDispatch::IntegrationTest
  include AnalyticsTestHelper
  include GeoCountryTestHelper

  class PagesController < ApplicationController
    def show = render(inline: "<p>page</p>", layout: "application")

    def search
      track_search(params[:q], results: params[:n].to_i)
      head :ok
    end

    def company
      track_company_viewed(params[:id])
      head :ok
    end

    def correction
      track_correction_submitted(subject_type: "Organization")
      head :ok
    end
  end

  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"

  def visit(path, user_agent: BROWSER) = get(path, headers: { "User-Agent" => user_agent })

  def with_pages(&)
    with_routing do |routes|
      routes.draw do
        get "companies/:id" => "analytics_tracking_test/pages#show"
        get "search" => "analytics_tracking_test/pages#search"
        get "seen/:id" => "analytics_tracking_test/pages#company"
        get "correct" => "analytics_tracking_test/pages#correction"
        get "design" => "design_system#show"
      end
      yield
    end
  end

  test "a person's search is sent with its result count" do
    with_pages { visit "/search?q=TerraPower&n=0" }

    assert_equal({ "query" => "terrapower", "results" => 0, "zero_results" => true },
      posthog.events.sole[:properties].slice("query", "results", "zero_results"))
  end

  test "bots aren't tracked" do
    with_pages do
      visit "/search?q=x&n=1", user_agent: "Mozilla/5.0 (compatible; Googlebot/2.1)"
      visit "/seen/terrapower", user_agent: "curl/8.7.1"
      visit "/seen/terrapower", user_agent: ""
    end

    assert_empty posthog.events
  end

  test "views and corrections carry only the slug or subject type" do
    with_pages do
      visit "/seen/terrapower"
      visit "/correct"
    end

    assert_equal [ "company_viewed", "correction_submitted" ], posthog.events.map { |e| e[:event] }
    assert_equal "terrapower", posthog.events.first[:properties]["slug"]
    assert_equal %w[$geoip_disable $ip $process_person_profile subject_type], posthog.events.last[:properties].keys.sort
  end

  test "server-side events carry the visitor's country and internal flag, never the IP (#205)" do
    internal_ips!("81.2.69.142")
    with_pages do
      get "/search?q=x&n=1", headers: { "User-Agent" => BROWSER }, env: { "REMOTE_ADDR" => "81.2.69.142" }
      get "/seen/terrapower", headers: { "User-Agent" => BROWSER }, env: { "REMOTE_ADDR" => "81.2.69.142" }
    end

    posthog.events.each do |event|
      props = event[:properties]
      assert_equal [ "GB", true, true ], props.values_at("$geoip_country_code", "internal", "$geoip_disable"), event[:event]
      assert_nil props["$ip"]
      assert_not props.values.include?("81.2.69.142")
    end
    assert_equal 2, posthog.events.size
  end

  test "public pages get the cookieless snippet's settings" do
    with_pages do
      visit "/companies/terrapower"

      assert_select 'meta[name="posthog-key"][content="phc_test_key"]'
      assert_select 'meta[name="posthog-host"][content="/relay"]', 1, "through our relay (#205)"
      assert_empty response.headers["Set-Cookie"].to_s
    end
  end

  CLAUDE_BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) " \
    "Claude/2.31226.1 Chrome/152.0.7977.130 Safari/537.36"

  test "our own agent sessions in the Claude app's browser aren't counted (#68)" do
    with_pages do
      visit "/companies/terrapower", user_agent: CLAUDE_BROWSER
      assert_select 'meta[name="posthog-key"]', count: 0

      visit "/seen/terrapower", user_agent: CLAUDE_BROWSER
    end

    assert_empty posthog.events
  end

  test "no snippet for bots, on /design, or when analytics is off" do
    with_pages do
      visit "/companies/terrapower", user_agent: "Mozilla/5.0 (compatible; bingbot/2.0)"
      assert_select 'meta[name="posthog-key"]', count: 0

      visit "/design"
      assert_select 'meta[name="posthog-key"]', count: 0

      Analytics.client = nil
      visit "/companies/terrapower"
      assert_select 'meta[name="posthog-key"]', count: 0
    end
  end
end
