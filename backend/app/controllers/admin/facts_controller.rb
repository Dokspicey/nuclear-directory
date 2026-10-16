# One directory fact: its status, values and history; take it off or put it
# back. Opened from Checks (from=checks, back=the list as it was), it has a
# breadcrumb back to that list and Previous and Next through it (#269).
class Admin::FactsController < Admin::BaseController
  before_action :check_type

  def show
    @fact = DataQuality::Review.fact(type: params[:type], id: params[:id].to_i) or raise ActiveRecord::RecordNotFound
    @list = list_position if params[:from] == "checks"
    # Decide here (#269): the claim this page was opened for (a Checks row is
    # one claim), else the oldest waiting on it, or the fact itself when it's
    # pending with none.
    waiting = DataQuality::Review.waiting_for(type: @fact.type, id: @fact.id)
    # A named claim that's no longer waiting shows its own result, never another claim's buttons.
    asked = params[:claim].presence&.to_i
    @claim = asked ? waiting.find { |item| item.candidate_id == asked } : waiting.first
    if asked && @claim.nil?
      @decided = DataQuality::Review.decision_of(asked)
      @following = @list&.dig(:next)
      return
    end
    # The fact's own buttons only when no claim on it is open at all (a lapsed
    # recommendation is still open, and is decided through its claim).
    @pending = @fact.verification_status == "pending" && @claim.nil? && !DataQuality::Review.open_claims?(type: @fact.type, id: @fact.id)
    @sourced = DataQuality::Review.sourced?(type: @fact.type, id: @fact.id) if @pending
    # After deciding: the next item in the list it was opened from.
    @following = @list&.dig(:next)
    # Nothing to decide: the last decision on it, so Back after one shows the result.
    @decided = DataQuality::Review.last_decision_for(type: @fact.type, id: @fact.id) unless @claim || @pending
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
    def fact_path_here = admin_fact_path(type: params[:type], id: params[:id], **context, claim: params[:claim].presence)
    def context = params.permit(:from, :back).to_h.symbolize_keys.compact_blank
    helper_method :context

    # Where this item (the fact, or one claim on it) sits in the Checks list
    # it was opened from: { index:, total:, previous:, next: } with paths, or
    # nil when it isn't in it.
    def list_position
      rows = DataQuality::Review.check_subjects(category: list_filters["category"].presence_in(Admin::ChecksController::CATEGORIES) || "all",
        source_kind: list_filters["source"].presence)
      here = [ params[:type], params[:id].to_i ]
      index = (params[:claim].present? && rows.index([ *here, params[:claim].to_i ])) || rows.index { |row| row.first(2) == here } or return
      path = ->(row) { row && admin_fact_path(type: row[0], id: row[1], **context, claim: row[2]) }
      { index: index + 1, total: rows.size, previous: path.(index.positive? ? rows[index - 1] : nil), next: path.(rows[index + 1]) }
    end
end
