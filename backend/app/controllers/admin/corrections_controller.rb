# The corrections inbox (#86): what visitors reported from the public pages
# (#44). Open reports (new or being looked at) first; each can be closed as
# fixed or dismissed, recorded with who decided. "Open record" leads to the
# company or plant's fact page, where the fix itself is made.
class Admin::CorrectionsController < Admin::BaseController
  TABS = %w[open closed].freeze
  PAGE = 50

  def index
    return locate(params[:report]) if params[:report].present?

    @tab = params[:tab].presence_in(TABS) || "open"
    @page = [ params[:page].to_i, 1 ].max
    @reports = listed(@tab).offset((@page - 1) * PAGE).limit(PAGE + 1).to_a
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
    # A tab's reports in the order it lists them.
    def listed(tab)
      tab == "open" ? CorrectionReport.where(status: %w[open reviewed]).order(created_at: :asc, id: :asc) :
        CorrectionReport.where(status: "closed").order(decided_at: :desc, id: :desc)
    end

    # A link to one report (the correction email, #317): its tab and page as
    # they are now, at its row, wherever it has moved since.
    def locate(id)
      report = CorrectionReport.find_by(id:) or return redirect_to(admin_corrections_path)
      tab = report.status == "closed" ? "closed" : "open"
      page = listed(tab).pluck(:id).index(report.id).to_i / PAGE + 1
      redirect_to admin_corrections_path(tab: (tab unless tab == "open"), page: (page if page > 1), anchor: "report-#{report.id}")
    end

    def decide(notice)
      report = CorrectionReport.find_by(id: params[:id])
      if report
        yield report
        flash[:notice] = notice
      else
        flash[:alert] = "That report no longer exists; refresh the inbox."
      end
      redirect_after admin_corrections_path(tab: params[:tab])
    rescue CorrectionReport::InvalidTransition => error
      flash[:alert] = "Not changed: #{error.message}. Refresh the inbox."
      redirect_after admin_corrections_path(tab: params[:tab])
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
