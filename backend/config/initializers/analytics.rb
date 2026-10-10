# PostHog sends events from a background thread; flush what's queued when the
# process exits so the last few events aren't lost. See lib/analytics.rb.
at_exit { Analytics.client&.shutdown } unless Rails.env.test?
