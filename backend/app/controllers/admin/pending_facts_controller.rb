# Directory facts waiting for a decision with no claim in the queue, e.g.
# seed data loaded as pending. They're listed on Checks under Facts (#201).
class Admin::PendingFactsController < Admin::BaseController
  # The old page's address leads to Checks.
  def index
    redirect_to admin_checks_path(category: "facts")
  end

  def approve
    flash_decision([ DataQuality::Review.approve_fact(type: fact_type, id: fact_id, by: actor) ], "Approved")
    redirect_after next_or(list_path)
  end

  def reject
    result = DataQuality::Review.reject_fact(type: fact_type, id: fact_id, by: actor,
      reason: params.dig(:reasons, fact_id.to_s).presence)
    flash_decision([ result ], "Rejected")
    redirect_after next_or(list_path)
  end

  private
    def fact_type = params.require(:type).to_s.camelize.presence_in(DataQuality::Review.fact_kinds.map(&:camelize)) || raise(ActionController::BadRequest)
    def fact_id = params.require(:id).to_i

    # Checks, with the chip it was on.
    def list_path = with_anchor(back_path(admin_checks_path(params.permit(:category).to_h.compact_blank)))
end
