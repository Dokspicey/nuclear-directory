# Sources (#201): one row per kind of source (last read, read, same,
# changed, approved, rejected, live) and visitors' correction requests;
# below, folded, what needs attention, the last run per stage and model
# spend (the admin's view of data_quality:status).
class Admin::StatusController < Admin::BaseController
  def show
    @rows = DataQuality::Status.by_kind
    @corrections = { last: CorrectionReport.maximum(:created_at), total: CorrectionReport.count,
      open: CorrectionReport.where(status: %w[open reviewed]).count }
    @sources = DataQuality::Status.sources
    @runs = DataQuality::Status.runs
    @spend = DataQuality::Status.spend
    @analytics_url = ENV["POSTHOG_DASHBOARD_URL"].presence
  end
end
