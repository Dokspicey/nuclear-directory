# The corrections inbox (#86): what visitors reported from the public pages
# (#44). Open reports (new or being looked at) first; each can be closed as
# fixed or dismissed, recorded with who decided. "Open record" leads to the
# company or plant's fact page, where the fix itself is made.
class Admin::CorrectionsController < Admin::BaseController
  TABS = %w[open closed].freeze
  PAGE = 50

  def index
    @tab = params[:tab].presence_in(TABS) || "open"
    @page = [ params[:page].to_i, 1 ].max
    scope = @tab == "open" ? CorrectionReport.where(status: %w[open reviewed]) : CorrectionReport.where(status: "closed")
    @reports = scope.order(@tab == "open" ? { created_at: :asc, id: :asc } : { decided_at: :desc, id: :desc })
      .offset((@page - 1) * PAGE).limit(PAGE + 1).to_a
    @more = @reports.size > PAGE
    @reports = @reports.first(PAGE)
    @counts = { "open" => CorrectionReport.where(status: %w[open reviewed]).count, "closed" => CorrectionReport.where(status: "closed").count }
    @record_paths = record_paths(@reports)
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
    rescue CorrectionReport::InvalidTransition => error
      flash[:alert] = "Not changed: #{error.message}. Refresh the inbox."
      redirect_to admin_corrections_path(tab: params[:tab])
    end

    # Admin fact pages for the company or plant pages the reports came from,
    # looked up in one query per kind: { report id => path }.
    def record_paths(reports)
      slugs = reports.to_h { |report| [ report.id, report.page_path.to_s.split(/[?#]/).first.match(%r{\A/(companies|plants)/([^/]+)\z})&.captures ] }.compact
      ids = {
        "companies" => Directory::Lookup.ids_by_slug(type: "Organization", slugs: slugs.values.select { _1.first == "companies" }.map(&:last)),
        "plants" => Directory::Lookup.ids_by_slug(type: "Facility", slugs: slugs.values.select { _1.first == "plants" }.map(&:last))
      }
      slugs.filter_map do |report_id, (kind, slug)|
        id = ids.fetch(kind)[slug] or next
        [ report_id, helpers.admin_fact_path(type: kind == "companies" ? "Organization" : "Facility", id:) ]
      end.to_h
    end
end
