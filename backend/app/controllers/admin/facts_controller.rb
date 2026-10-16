# One directory fact: its status, values and history; take it off or put it
# back. Opened from Checks (from=checks, back=the list as it was), it has a
# breadcrumb back to that list and Previous and Next through it (#269).
class Admin::FactsController < Admin::BaseController
  before_action :check_type

  def show
    @fact = DataQuality::Review.fact(type: params[:type], id: params[:id].to_i) or raise ActiveRecord::RecordNotFound
    @list = list_position if params[:from] == "checks"
  end

  def unpublish
    # Taking a fact off needs a reason (#201): it's kept in the history.
    if params[:reason].blank?
      flash[:alert] = "Say why it's taken off."
      return redirect_after fact_path_here
    end

    result = DataQuality::Review.unpublish(type: params[:type], id: params[:id].to_i, by: actor, reason: params[:reason].strip)
    flash_results([ result ], "Unpublished")
    redirect_after fact_path_here
  end

  def republish
    result = DataQuality::Review.approve_fact(type: params[:type], id: params[:id].to_i, by: actor, reason: params[:reason].presence)
    flash_results([ result ], "Republished")
    redirect_after fact_path_here
  end

  private
    def check_type
      raise ActiveRecord::RecordNotFound unless DataQuality::Review.fact_kinds.map(&:camelize).include?(params[:type])
    end

    # This page again, with where it was opened from.
    def fact_path_here = admin_fact_path(type: params[:type], id: params[:id], **context)
    def context = params.permit(:from, :back).to_h.symbolize_keys.compact_blank
    helper_method :context

    # Where this fact sits in the Checks list it was opened from:
    # { index:, total:, previous:, next: } with paths, or nil when it isn't in it.
    def list_position
      subjects = DataQuality::Review.check_subjects(category: list_filters["category"].presence_in(Admin::ChecksController::CATEGORIES) || "all",
        source_kind: list_filters["source"].presence)
      index = subjects.index([ params[:type], params[:id].to_i ]) or return
      path = ->(subject) { subject && admin_fact_path(type: subject.first, id: subject.last, **context) }
      { index: index + 1, total: subjects.size, previous: path.(index.positive? ? subjects[index - 1] : nil), next: path.(subjects[index + 1]) }
    end
end
