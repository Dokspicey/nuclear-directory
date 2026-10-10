# One directory fact: its status, values and history; unpublish or republish.
class Admin::FactsController < Admin::BaseController
  before_action :check_type

  def show
    @fact = DataQuality::Review.fact(type: params[:type], id: params[:id].to_i) or raise ActiveRecord::RecordNotFound
  end

  def unpublish
    result = DataQuality::Review.unpublish(type: params[:type], id: params[:id].to_i, by: actor, reason: params[:reason].presence)
    flash_results([ result ], "Unpublished")
    redirect_to admin_fact_path(type: params[:type], id: params[:id])
  end

  def republish
    result = DataQuality::Review.approve_fact(type: params[:type], id: params[:id].to_i, by: actor, reason: params[:reason].presence)
    flash_results([ result ], "Republished")
    redirect_to admin_fact_path(type: params[:type], id: params[:id])
  end

  private
    def check_type
      raise ActiveRecord::RecordNotFound unless DataQuality::Review.fact_kinds.map(&:camelize).include?(params[:type])
    end
end
