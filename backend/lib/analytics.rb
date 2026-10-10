# Anonymous product analytics through PostHog (#66, Tosin's decision).
#
# Privacy rules, all enforced here:
# - nobody is ever identified: every event uses one shared distinct id, never
#   identify(), and no person profiles are created
# - no personal data in properties; no IP or GeoIP (PostHog's project also
#   discards client IPs and runs cookieless)
# - nothing runs without POSTHOG_API_KEY, and nothing is sent in tests
#
# Server-side events (controllers call these through TracksAnalytics, which
# also skips bots):
#   Analytics.track_search(params[:q], results: results.size)
#   Analytics.capture("company_viewed", slug: company.slug)
#
# Page views come from the browser snippet (app/javascript/analytics.js),
# configured in the same cookieless way.
module Analytics
  EVENTS = %w[search company_viewed power_plant_viewed correction_submitted].freeze
  # One id for everyone: events are counted, never tied to a visitor.
  DISTINCT_ID = "anonymous"
  ANONYMOUS = { "$process_person_profile" => false, "$geoip_disable" => true, "$ip" => nil }.freeze
  DEFAULT_HOST = "https://us.i.posthog.com"
  MAX_QUERY_LENGTH = 200

  class << self
    # A PostHog::Client, or nil when analytics is off. Tests assign a fake.
    attr_writer :client

    def client
      return @client if defined?(@client)

      @client = build_client
    end

    def enabled? = !client.nil?

    # The browser snippet's project key and host, or nil when analytics is off.
    def public_key = (api_key if enabled?)
    def host = ENV["POSTHOG_HOST"].presence || DEFAULT_HOST

    # Sends one anonymous event. Never raises: analytics must not break a page.
    def capture(event, properties = {})
      raise ArgumentError, "unknown analytics event #{event.inspect}" unless EVENTS.include?(event.to_s)
      return unless enabled?

      client.capture(distinct_id: DISTINCT_ID, event: event.to_s, properties: properties.stringify_keys.merge(ANONYMOUS))
    rescue ArgumentError
      raise
    rescue => error
      Rails.logger.warn("[analytics] #{event} not sent: #{error.class}: #{error.message}")
      nil
    end

    # The search interface Design calls (same as #62's). Queries are
    # normalized so "TerraPower " and "terrapower" count together, and
    # zero-result searches are flagged so they're easy to find.
    def track_search(query, results:)
      normalized = normalize_query(query) or return

      capture("search", query: normalized, results: results.to_i, zero_results: results.to_i.zero?)
    end

    def normalize_query(query)
      query.to_s.unicode_normalize(:nfkc).downcase.squish.first(MAX_QUERY_LENGTH).presence
    end

    private
      def api_key = ENV["POSTHOG_API_KEY"].presence

      def build_client
        return if Rails.env.test? || api_key.nil?

        PostHog::Client.new(api_key: api_key, host: host,
          on_error: proc { |status, error| Rails.logger.warn("[analytics] PostHog error #{status}: #{error}") })
      end
  end
end
