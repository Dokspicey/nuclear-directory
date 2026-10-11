# A company's page (#42): only verified facts, each with its sources.
# A company's old address (renamed, or merged into another) moves to its
# current page (#143). Unknown or unverified companies get "Page not found".
class CompaniesController < ApplicationController
  def show
    @profile = CompanyProfile.find(params[:slug])
    return if @profile

    current = Organization.find_by_former_slug(params[:slug]) or raise ActiveRecord::RecordNotFound
    redirect_to company_path(slug: current.slug), status: :moved_permanently
  end
end
