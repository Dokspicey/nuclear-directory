# The directory and search results: one page, one list (#40). Pressing Enter
# in any search field lands here with q set; a category pill sets category.
class DirectoryController < ApplicationController
  def index
    @listing = DirectoryListing.new(**params.permit(:category, :q, :technology, :state, :sort).to_h.symbolize_keys)
    # The filter sheet's "Show N results" (#90) asks for the count only; it isn't a search.
    return render(json: { count: @listing.company_scope.count + @listing.plant_scope.count }) if request.format.json?

    @companies = @listing.companies.to_a
    @plants = @listing.plants.to_a
    @counts = DirectoryListing.category_counts

    track_search(@listing.query, results: @companies.size + @plants.size) if @listing.searching?
  end

  private
    # Anonymous search counts (#66, PostHog, built by Database). Database keeps
    # this interface and will name the final module; until it lands this is a
    # no-op, so only the line below changes then.
    def track_search(query, results:)
      Analytics.track_search(query, results:) if defined?(Analytics)
    end
end
