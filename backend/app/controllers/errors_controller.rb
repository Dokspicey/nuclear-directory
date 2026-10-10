# Renders "Page not found" in the site's own layout (#110), with close
# matches for the address and a search prefilled from it. Wired up as the
# exceptions app for 404s in config/application.rb; other errors use the
# static pages in public/.
class ErrorsController < ApplicationController
  def not_found
    @path = (preview_path || request.env["action_dispatch.original_path"] || request.path).to_s.first(200)
    @suggestions = PageSuggestions.new(@path)

    respond_to do |format|
      format.html { render status: :not_found }
      format.any { head :not_found }
    end
  end

  private
    # /design/not-found/<path> (development only) previews the page for <path>.
    def preview_path = ("/#{params[:path]}" if Rails.env.local? && request.path.start_with?("/design/not-found/"))
end
