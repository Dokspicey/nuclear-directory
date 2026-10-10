# A company's page (#42): only verified facts, each with its sources.
# Unknown or unverified companies get "Page not found".
class CompaniesController < ApplicationController
  def show
    @profile = CompanyProfile.find(params[:slug]) or raise ActiveRecord::RecordNotFound
  end
end
