# Sources and runs: crawl status per source, the last run per stage, and
# model spend against the budget (the admin's view of data_quality:status).
class Admin::StatusController < Admin::BaseController
  def show
    @sources = DataQuality::Status.sources
    @runs = DataQuality::Status.runs
    @spend = DataQuality::Status.spend
    @analytics_url = ENV["POSTHOG_DASHBOARD_URL"].presence
  end
end
