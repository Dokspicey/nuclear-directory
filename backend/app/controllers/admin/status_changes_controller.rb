# Change status (#316): a plant's or a unit's status as a person's decision,
# with its source, without a console. A published status always has one
# (docs/DATA.md): NRC's status line, or a link and a quote. A note is only
# the reason, kept in the admin's history. The same code as
# `directory:set_status` (Directory::StatusChange, through
# DataQuality::Review). The form previews with a GET, which reads and writes
# nothing; Change status confirms it.
class Admin::StatusChangesController < Admin::BaseController
  STATUSES = DirectoryHelper::FACILITY_STATUS_LABELS.keys.freeze
  NOTE_ALONE = "Add NRC's status line or a link and quote. A note alone can't be published.".freeze

  before_action :load_facility

  def edit
    @status = params[:status].presence_in(STATUSES)
    return unless @status

    @errors = evidence_errors
    result = DataQuality::Review.status_change_plan(ids: chosen_ids, status: @status)
    result.ok? ? @plan = result.plan : @errors << result.error
  end

  def update
    @status = params[:status].presence_in(STATUSES)
    @errors = @status ? evidence_errors : [ "Choose a status" ]
    return render_form if @errors.any?

    source_id, quote = @nrc if @evidence == "nrc"
    result = DataQuality::Review.set_status(ids: chosen_ids, status: @status, by: actor, reason:,
      source_url: (params[:url] if @evidence == "link"), source_id:, quote: (@evidence == "link" ? params[:quote] : quote))
    return render_form(result.error) unless result.ok?

    flash[:notice] = notice_for(result.plan)
    redirect_after back_here
  end

  private
    def load_facility
      @facility = Facility.find(params[:id])
      @units = @facility.parent_id ? [] : Facility.where(parent_id: @facility.id).order(:name, :id).to_a
      @nrc = DataQuality::Review.nrc_status_quote(@facility.name)
      # Anything else asked for (an old form's "note") is refused in evidence_errors.
      @evidence = params[:evidence].presence ? params[:evidence].to_s : (@nrc ? "nrc" : "link")
    end

    # The site and the units ticked, or the unit alone.
    def chosen_ids
      ticked = Array(params[:unit_ids]).map(&:to_i) & @units.map(&:id)
      [ @facility.id, *ticked ]
    end
    helper_method :chosen_ids

    def evidence_errors
      case @evidence
      when "nrc" then @nrc ? [] : [ "NRC's status file doesn't name #{@facility.name}. Give a link and a quote." ]
      when "link"
        [ ("Enter a link to a public source, starting with https://" if params[:url].blank?),
          ("Copy the sentence from the source that states the status" if params[:quote].blank?) ].compact
      else [ NOTE_ALONE ]
      end
    end

    def reason
      note = params[:note].to_s.strip.presence
      base = case @evidence
      when "nrc" then "NRC's 365-day power status file: #{@nrc.last}"
      else "Source: #{params[:url].to_s.strip}"
      end
      [ base, note ].compact.join(". ")
    end

    def render_form(error = nil)
      @errors = [ *@errors, *error ]
      render :edit, status: :unprocessable_content
    end

    def notice_for(plan)
      return "Nothing changed: it's already #{helpers.facility_status_label(@status).downcase}." if plan.changes.empty?

      "Status changed to #{helpers.facility_status_label(@status).downcase} for #{helpers.pluralize(plan.changes.size, 'record')}."
    end

    # The site's Record, or the unit's fact page.
    def back_here
      @facility.parent_id ? admin_fact_path(type: "Facility", id: @facility.id) : admin_record_path(type: "Facility", id: @facility.id)
    end
    helper_method :back_here
end
