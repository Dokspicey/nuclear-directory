# Every admin page: signed in, not indexed, not tracked (TracksAnalytics
# skips /admin). Decisions go through DataQuality::Review only, recorded as
# the signed-in person (human:<handle>).
class Admin::BaseController < ApplicationController
  include Authentication
  layout "admin"

  private
    def actor = Current.user.actor

    # Where a page's breadcrumb and its decisions lead back to (#269): the
    # list it was opened from, with its filters and page, passed as `back`.
    # Only a path inside the admin counts; anything else is the fallback.
    def back_path(fallback)
      back = params[:back].to_s
      back.match?(%r{\A/admin(?:[/?#]|\z)}) ? back : fallback
    end
    helper_method :back_path

    # The Checks filters in `back` ({ "category" =>, "source" => }), for
    # Previous and Next in the same order as that list.
    def list_filters
      query = URI.parse(back_path("/admin/checks")).query.to_s
      Rack::Utils.parse_query(query).slice("category", "source")
    rescue URI::InvalidURIError
      {}
    end

    # A decision's flash. Made on an item page and on to the next one, it's
    # short ("Approved."), and that page adds where it is ("4 of 6.").
    def flash_decision(results, verb)
      flash_results(results, verb)
      return unless next_or(nil) && results.all?(&:ok?)

      flash[:notice] = "#{verb}."
      flash[:decided] = true
    end

    # Where a decision goes: on to the next item only when it went through;
    # when it was refused, back to the list, with the error in the flash.
    def after_decision(results, fallback) = results.all?(&:ok?) ? next_or(fallback) : fallback

    # After a decision on an item page: the next item in its list (next),
    # else the fallback (the list). Only a path inside the admin counts.
    def next_or(fallback)
      following = params[:next].to_s
      following.match?(%r{\A/admin(?:[/?#]|\z)}) ? following : fallback
    end

    # A list path at the row after the one just decided on (anchor), so the
    # place on the page isn't lost.
    def with_anchor(path)
      anchor = params[:anchor].to_s
      anchor.match?(/\A(?:claim|fact)-[\w-]+\z/) ? "#{path.split('#').first}##{anchor}" : path
    end

    # Where a record sits in the Live list it was opened from (back), with
    # paths for Previous and Next, or nil when it wasn't opened from Live.
    def live_position(type, id)
      back = back_path(nil) or return
      return unless back.start_with?("/admin/live")

      query = Rack::Utils.parse_query(URI.parse(back).query.to_s)
      position = Admin::LiveController.list_for(ActionController::Parameters.new(query)).neighbours(type, id) or return
      path = ->(key) { key && live_item_path(key, back) }
      position.merge(previous: path.(position[:previous]), next: path.(position[:next]))
    rescue URI::InvalidURIError
      nil
    end

    # A Live list item's page: a company's or site's Record, else its fact page.
    def live_item_path(key, back)
      type, id = key
      if type == "Organization" || (type == "Facility" && Facility.where(id:, parent_id: nil).exists?)
        admin_record_path(type:, id:, back:)
      else
        admin_fact_path(type:, id:, from: "live", back:)
      end
    end

    # Every decision redirects with 303, so Back never resubmits it.
    def redirect_after(path) = redirect_to(path, status: :see_other)

    # Flash messages for a batch of Review results. verb: "Approved", "Rejected".
    def flash_results(results, verb)
      done, failed = results.partition(&:ok?)
      flash[:notice] = "#{verb} #{helpers.pluralize(done.size, 'item')}." if done.any?
      flash[:alert] = failed.map { |result| "#{result_label(result)}: #{result.errors.to_sentence}" }.join(" ") if failed.any?
    end

    def result_label(result) = result.candidate_id ? "Claim #{result.candidate_id}" : "This fact"
end
