# A power plant's page (#43): a public site with its verified units and the
# companies linked to them. A unit's address goes to its site's page, at the
# unit's row. Unknown or hidden plants get "Page not found".
class PlantsController < ApplicationController
  def show
    unit = Facility.verified.where.not(parent_id: nil).find_by(slug: params[:slug])
    if unit && (site = PlantProfile.find(unit.parent.slug))
      return redirect_to plant_path(slug: site.slug, anchor: "unit-#{unit.slug}"), status: :moved_permanently
    end

    @profile = PlantProfile.find(params[:slug]) or raise ActiveRecord::RecordNotFound
  end
end
