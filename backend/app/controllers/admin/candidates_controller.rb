# The review queue: claims the pipeline found, waiting for a human.
class Admin::CandidatesController < Admin::BaseController
  QUEUES = %w[recommended needs_review].freeze
  PAGE = 50

  def index
    @queue = params[:queue].presence_in(QUEUES) || "recommended"
    @reason = params[:reason].presence
    @run_id = params[:run_id].presence&.to_i
    @items = DataQuality::Review.candidates(queue: @queue, reason: @reason, run_id: @run_id,
      after_id: params[:after].presence&.to_i, limit: PAGE)
    @counts = DataQuality::Review.counts
    @reasons = DataQuality::Review.reasons(queue: @queue, run_id: @run_id)
  end

  # One claim (candidate_id), or the selected ones (candidate_ids[]): bulk
  # approval covers recommended claims only.
  def approve
    single = params[:candidate_id].present?
    ids = single ? [ params[:candidate_id] ] : Array(params[:candidate_ids])
    if ids.empty?
      flash[:alert] = "Select at least one claim to approve."
    else
      flash_results(DataQuality::Review.approve(ids.map(&:to_i), by: actor, only_recommended: !single), "Approved")
    end
    redirect_to queue_path
  end

  def reject
    id = params.require(:candidate_id).to_i
    flash_results(DataQuality::Review.reject([ id ], by: actor, reason: params.dig(:reasons, id.to_s).presence), "Rejected")
    redirect_to queue_path
  end

  def edit
    @item = DataQuality::Review.candidate(params[:id].to_i) or raise ActiveRecord::RecordNotFound
    @fields = editable_fields(@item)
  end

  def update
    item = DataQuality::Review.candidate(params[:id].to_i) or raise ActiveRecord::RecordNotFound
    # Only single values come from the form; lists (aliases) and nested ends are read-only.
    scalars = editable_fields(item).reject { |name| item.payload[name].is_a?(Array) || item.payload[name].is_a?(Hash) }
    values = params.fetch(:values, {}).permit(*scalars).to_h.transform_values(&:presence)
    result = DataQuality::Review.edit_and_approve(item.candidate_id, attributes: values, by: actor,
      reason: params[:note].presence)
    if result.ok?
      flash_results([ result ], "Approved")
      redirect_to queue_path
    else
      @item = item
      @fields = editable_fields(item)
      flash.now[:alert] = result.errors.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  private
    # Back to the queue, with the filters it had.
    def queue_path
      admin_candidates_path(params.permit(:queue, :reason, :run_id).to_h.compact_blank)
    end

    # The claim's own values; link ends were matched and can't be edited here.
    def editable_fields(item)
      item.payload.keys - DataQuality::Review::NOT_EDITABLE
    end
end
