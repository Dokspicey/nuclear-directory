require "test_helper"
require_relative "../support/fake_posthog"

# The request-level rules (TracksAnalytics): bots and non-public paths are
# never tracked, and the browser snippet only appears on public pages.
class AnalyticsTrackingTest < ActionDispatch::IntegrationTest
  include AnalyticsTestHelper

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

  test "public pages get the cookieless snippet's settings" do
    with_pages do
      visit "/companies/terrapower"

      assert_select 'meta[name="posthog-key"][content="phc_test_key"]'
      assert_select 'meta[name="posthog-host"][content="https://us.i.posthog.com"]'
      assert_empty response.headers["Set-Cookie"].to_s
    end
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
