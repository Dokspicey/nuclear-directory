# Deciding on claims the pipeline found: approve, edit then approve,
# reject, approve all. They're listed on Checks (#201), where every action
# goes back to.
class Admin::CandidatesController < Admin::BaseController
  # The old queue's address leads to Checks.
  def index
    redirect_to admin_checks_path
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

  # Every recommended claim matching the queue's filters, in the background
  # (DataQuality::ApproveAllJob). Only the recommended queue: claims that
  # need review each get a look on their own.
  def approve_all
    ids = DataQuality::Review.candidate_ids(queue: :recommended, reason: params[:reason].presence,
      run_id: params[:run_id].presence&.to_i)
    if ids.empty?
      flash[:alert] = "Nothing to approve: no recommended claims match these filters."
    elsif params[:shown] != self.class.fingerprint(ids)
      # Only what the person saw and confirmed: if claims were recommended,
      # decided or dropped since the page loaded, nothing is approved.
      flash[:alert] = "The queue changed since you opened it, so nothing was approved. Check the count and try again."
    else
      DataQuality::ApproveAllJob.perform_later(ids, by: actor)
      flash[:notice] = "Approving #{helpers.pluralize(ids.size, 'recommended claim')}. Refresh in a minute to see Checks " \
        "clear. Any claim that's changed since it was recommended stays here."
    end
    redirect_to queue_path
  end

  # Which claims "Approve all" covered when the page was shown, compared on
  # the click so exactly those are approved.
  def self.fingerprint(ids) = Digest::SHA256.hexdigest(ids.join(","))

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
      @errors = result.errors
      render :edit, status: :unprocessable_content
    end
  end

  private
    # Checks' filter chip and source, carried through edit and back.
    # reason and run_id narrow Approve all, as before.
    def filters = params.permit(:category, :source, :reason, :run_id).to_h.compact_blank
    helper_method :filters

    def queue_path = admin_checks_path(filters.slice("category", "source"))

    # The claim's own values; link ends were matched and can't be edited here.
    def editable_fields(item)
      item.payload.keys - DataQuality::Review::NOT_EDITABLE
    end
end
