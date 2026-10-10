# Every admin page: signed in, not indexed, not tracked (TracksAnalytics
# skips /admin). Decisions go through DataQuality::Review only, recorded as
# the signed-in person (human:<handle>).
class Admin::BaseController < ApplicationController
  include Authentication
  layout "admin"

  private
    def actor = Current.user.actor

    # Flash messages for a batch of Review results. verb: "Approved", "Rejected".
    def flash_results(results, verb)
      done, failed = results.partition(&:ok?)
      flash[:notice] = "#{verb} #{helpers.pluralize(done.size, 'item')}." if done.any?
      flash[:alert] = failed.map { |result| "#{result_label(result)}: #{result.errors.to_sentence}" }.join(" ") if failed.any?
    end

    def result_label(result) = result.candidate_id ? "Claim #{result.candidate_id}" : "This fact"
end
