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

    # A list path at the row after the one just decided on (anchor), so the
    # place on the page isn't lost.
    def with_anchor(path)
      anchor = params[:anchor].to_s
      anchor.match?(/\A(?:claim|fact)-[\w-]+\z/) ? "#{path.split('#').first}##{anchor}" : path
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
