# The corrections inbox (#86): what visitors reported from the public pages
# (#44). Open reports (new or being looked at) first; each can be closed as
# fixed or dismissed, recorded with who decided. "Open record" leads to the
# company or plant's fact page, where the fix itself is made.
class Admin::CorrectionsController < Admin::BaseController
  TABS = %w[open closed].freeze
  PAGE = 50

  def index
    @tab = params[:tab].presence_in(TABS) || "open"
    scope = @tab == "open" ? CorrectionReport.where(status: %w[open reviewed]) : CorrectionReport.where(status: "closed")
    @reports = scope.order(@tab == "open" ? :created_at : { decided_at: :desc }).limit(PAGE)
    @counts = { "open" => CorrectionReport.where(status: %w[open reviewed]).count, "closed" => CorrectionReport.where(status: "closed").count }
  end

  def start = decide("Marked as in progress.") { |report| report.start!(by: actor) }
  def fix = decide("Closed as fixed.") { |report| report.close!("fixed", by: actor) }
  def dismiss = decide("Report dismissed.") { |report| report.close!("dismissed", by: actor) }
  def reopen = decide("Report reopened.", &:reopen!)

  private
    def decide(notice)
      report = CorrectionReport.find_by(id: params[:id])
      if report
        yield report
        flash[:notice] = notice
      else
        flash[:alert] = "That report no longer exists; refresh the inbox."
      end
      redirect_to admin_corrections_path(tab: params[:tab])
    end
end
