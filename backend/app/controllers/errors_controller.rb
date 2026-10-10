# Renders "Page not found" in the site's own layout. Wired up as the
# exceptions app for 404s in config/application.rb; other errors use the
# static pages in public/.
class ErrorsController < ApplicationController
  def not_found
    respond_to do |format|
      format.html { render status: :not_found }
      format.any { head :not_found }
    end
  end
end
