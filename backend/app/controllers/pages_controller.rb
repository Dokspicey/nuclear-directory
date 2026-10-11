# The short fixed pages linked from the footer (#56): about, privacy,
# disclaimer and the crawler's page, which NuclearDirectoryBot's user agent
# points to.
class PagesController < ApplicationController
  # The closing line counts what the directory lists today, the same way the
  # directory does, and the date of the newest published fact.
  def about
    @companies_count = DirectoryListing.new.company_scope.count
    @plants_count = DirectoryListing.new(category: "plants").plant_scope.count
    @updated_on = [ Organization, Facility, Relationship, FacilityRelationship ]
      .filter_map { |model| model.published.maximum(:verified_at) }.max
  end

  def privacy; end
  def disclaimer; end
  def bot; end
end
