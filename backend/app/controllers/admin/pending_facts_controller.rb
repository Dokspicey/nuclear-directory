# Directory facts waiting for a decision with no claim in the queue, e.g.
# seed data loaded as pending.
class Admin::PendingFactsController < Admin::BaseController
  def index
    @kinds = DataQuality::Review.fact_kinds
    @kind = params[:kind].presence_in(@kinds) || @kinds.first
    @facts = DataQuality::Review.pending_facts(kind: @kind, after_id: params[:after].presence&.to_i)
  end

  def approve
    flash_results([ DataQuality::Review.approve_fact(type: fact_type, id: fact_id, by: actor) ], "Approved")
    redirect_to admin_pending_facts_path(kind: params[:kind])
  end

  def reject
    result = DataQuality::Review.reject_fact(type: fact_type, id: fact_id, by: actor,
      reason: params.dig(:reasons, fact_id.to_s).presence)
    flash_results([ result ], "Rejected")
    redirect_to admin_pending_facts_path(kind: params[:kind])
  end

  private
    def fact_type = params.require(:type).to_s.camelize.presence_in(DataQuality::Review.fact_kinds.map(&:camelize)) || raise(ActionController::BadRequest)
    def fact_id = params.require(:id).to_i
end
