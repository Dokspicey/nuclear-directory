# A company's or plant's Record (#201 part 2): the public page as visitors
# see it, with its status, Edit, Take off or Put back, its related items,
# its sources and its history. Opened from Live, it has a breadcrumb back to
# that list and Previous and Next through it; opened from another Record's
# related items, Previous and Next through that section. Writes go through
# DataQuality::Review. Edit serves a unit or a link too (page: "fact"), from
# a related row's menu, and returns to that row (next).
class Admin::RecordsController < Admin::BaseController
  EDITABLE_TYPES = %w[Organization Facility Relationship FacilityRelationship].freeze

  before_action :load_fact
  # Saving an edit approves the record, which would put a removed one back:
  # that's Put back's job, so a removed or rejected record isn't edited here.
  before_action :editable!, only: %i[edit update]

  def show
    @record = params[:type].constantize.find(@fact.id)
    @profile = @record.is_a?(Organization) ? CompanyProfile.new(@record) : PlantProfile.new(@record)
    @sources = Directory::Lookup.evidence_sources(type: @fact.type, id: @fact.id)
    @waiting = DataQuality::Review.waiting_for(type: @fact.type, id: @fact.id)
    @related = RelatedItems.new(@record)
    @list = related_context ? related_context[:list] : live_position(@fact.type, @fact.id)
  end

  def edit
    @fields = editable_fields
  end

  # Saved as an approval with the edited values, recorded in its history.
  def update
    values = params.fetch(:values, {}).permit(*editable_fields).to_h.transform_values(&:presence)
      .reject { |name, value| @fact.values[name].to_s == value.to_s }
    # A new website would otherwise set the domain from it; keep the one in
    # the form, blank included (companies sharing a website have none).
    values["domain"] = params.dig(:values, :domain).presence if values.key?("website") && !values.key?("domain") && editable_fields.include?("domain")
    # A pending record is approved as it is ("Save and approve"); a live one with nothing changed stays as it was.
    if values.empty? && @fact.verification_status != "pending"
      flash[:notice] = "Nothing changed."
      return redirect_after next_or(record_path_here)
    end

    result = nil
    # Checked again under the record's lock, with the write: a record taken
    # off or rejected meanwhile isn't put back by an edit (that's Put back's job).
    params[:type].constantize.transaction do
      status = params[:type].constantize.lock.find(@fact.id).verification_status
      if %w[verified pending].include?(status)
        result = DataQuality::Review.approve_fact(type: @fact.type, id: @fact.id, by: actor, attributes: values, reason: params[:note].presence)
      else
        @fact = @fact.with(verification_status: status)
      end
    end
    return editable! unless result

    if result.ok?
      flash[:notice] = "Saved."
      redirect_after next_or(record_path_here)
    else
      @fields = editable_fields
      @errors = result.errors
      render :edit, status: :unprocessable_content
    end
  end

  private
    def load_fact
      raise ActiveRecord::RecordNotFound unless EDITABLE_TYPES.include?(params[:type])

      @fact = DataQuality::Review.fact(type: params[:type], id: params[:id].to_i) or raise ActiveRecord::RecordNotFound
      return if fact_page?
      raise ActiveRecord::RecordNotFound unless %w[Organization Facility].include?(@fact.type)
      raise ActiveRecord::RecordNotFound if @fact.type == "Facility" && @fact.values["parent_id"].present? # a unit has its fact page
    end

    # Editing a unit or a link: its page is the fact page.
    def fact_page? = params[:page] == "fact"
    helper_method :fact_page?, :next_or

    def editable!
      return if %w[verified pending].include?(@fact.verification_status)

      flash[:alert] = @fact.verification_status == "unpublished" ? "It's taken off. Put it back first, then edit it." : "It was rejected, so it can't be edited."
      redirect_after next_or(record_path_here)
    end

    def record_path_here
      context = params.permit(:from, :section, :row, :back).to_h.symbolize_keys.compact_blank
      fact_page? ? admin_fact_path(type: @fact.type, id: @fact.id, **context) : admin_record_path(type: @fact.type, id: @fact.id, **context)
    end
    helper_method :record_path_here

    # Single values a person may change here; ids, slugs and lists aren't.
    # Display-only names the lookup adds (parent_name, …) aren't stored values either.
    NOT_EDITED = %w[id slug parent_id parent_name technology aliases created_at updated_at verification_status verified_by verified_at confidence
      organization_name facility_name from_organization_name to_organization_name].freeze

    # A site's capacity is the sum of its units, never stored (DATA.md), so a
    # site with units has none to edit; a standalone reactor keeps its own.
    def editable_fields
      # A link's ends and kind identify it, so they aren't edited (as in Checks).
      fields = @fact.values.reject do |name, value|
        NOT_EDITED.include?(name) || DataQuality::Review::NOT_EDITABLE.include?(name) || name.end_with?("_id") || value.is_a?(Array) || value.is_a?(Hash)
      end.keys
      @fact.type == "Facility" && Facility.exists?(parent_id: @fact.id) ? fields - %w[capacity_mw] : fields
    end
end
