# Analytics for controllers and views (#66): server-side events that skip
# bots, and whether a page gets the browser snippet. Bot filtering and path
# exclusions carried over from the usage counts in #62. See lib/analytics.rb.
#
#   track_search(params[:q], results: @results.size)
#   track_company_viewed(@company.slug)
module TracksAnalytics
  extend ActiveSupport::Concern

  BOT_USER_AGENT = /bot|crawl|spider|slurp|scrap|fetch|preview|monitor|uptime|headless|lighthouse|
    curl|wget|python|ruby|java|go-http|okhttp|axios|node-fetch|httpclient|libwww|facebookexternalhit/ix
  # Not public pages: the admin, the design reference, the health check, Rails internals.
  UNTRACKED_PATHS = %r{\A/(admin|design|up|rails|assets|cable)(/|\z)}

  included do
    helper_method :analytics_snippet?
  end

  private
    def track_search(query, results:)
      Analytics.track_search(query, results:) if trackable_request?
    end

    def track_company_viewed(slug) = track("company_viewed", slug:)
    def track_power_plant_viewed(slug) = track("power_plant_viewed", slug:)

    # Only what the correction is about, never the message or contact details.
    def track_correction_submitted(subject_type: nil)
      track("correction_submitted", subject_type:)
    end

    def track(event, properties)
      Analytics.capture(event, properties.compact) if trackable_request?
    end

    # Whether to load the browser snippet (page views) on this page.
    def analytics_snippet?
      Analytics.public_key.present? && request.get? && trackable_request?
    end

    def trackable_request?
      !bot? && !request.path.match?(UNTRACKED_PATHS)
    end

    def bot?
      user_agent = request.user_agent.to_s
      user_agent.blank? || user_agent.match?(BOT_USER_AGENT)
    end
end
