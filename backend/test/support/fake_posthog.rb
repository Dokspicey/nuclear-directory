# Stands in for PostHog::Client in tests: records events instead of sending them.
class FakePostHog
  attr_reader :events

  def initialize(fail_with: nil)
    @fail_with = fail_with
    @events = []
  end

  def capture(attrs)
    raise @fail_with if @fail_with

    @events << attrs
    true
  end

  def shutdown = true
end

# Turns analytics on with a FakePostHog for one test: include, then use `posthog`.
module AnalyticsTestHelper
  extend ActiveSupport::Concern

  included do
    setup do
      @previous_key = ENV["POSTHOG_API_KEY"]
      ENV["POSTHOG_API_KEY"] = "phc_test_key"
      Analytics.client = (@posthog = FakePostHog.new)
    end

    teardown do
      ENV["POSTHOG_API_KEY"] = @previous_key
      Analytics.remove_instance_variable(:@client) if Analytics.instance_variable_defined?(:@client)
    end
  end

  def posthog = @posthog
end
