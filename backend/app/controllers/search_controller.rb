# Instant results for the home and header search fields (#41): a Turbo Frame
# with the first few companies and plants and sites, grouped. Pressing Enter
# goes to the full results on the directory page instead, which is also
# where a search is counted (counting every keystroke's prefix would
# inflate the numbers).
class SearchController < ApplicationController
  MINIMUM_LENGTH = 2
  COMPANY_LIMIT = 5
  PLANT_LIMIT = 4

  def index
    listing = DirectoryListing.new(q: params[:q])
    @query = listing.query if listing.query.to_s.length >= MINIMUM_LENGTH

    if @query
      @companies = listing.companies.limit(COMPANY_LIMIT).to_a
      @plants = listing.plants.limit(PLANT_LIMIT).to_a
      @roles = OrganizationRole.verified.where(organization_id: @companies.map(&:id)).includes(:role).group_by(&:organization_id)
    end

    render layout: false
  end
end
