# The home page (#41): one job, search. The wordmark, the search field with
# instant results, a few suggested searches and the eight category boxes.
class HomeController < ApplicationController
  EXAMPLES_PER_CATEGORY = 3

  def show
    @examples = Category.all.to_h { |category| [ category.key, examples_for(category) ] }
  end

  private
    # The most connected verified names in a category, so the boxes show
    # names visitors are likely to recognize.
    def examples_for(category)
      listing = DirectoryListing.new(category: category.key, sort: "connections")
      (category.plants ? listing.plants : listing.companies).limit(EXAMPLES_PER_CATEGORY).map(&:name)
    end
end
