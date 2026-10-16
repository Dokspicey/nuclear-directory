# The admin's home (#201): today's date, a tile per stage with its count,
# and what each source read, found the same and changed.
class Admin::OverviewController < Admin::BaseController
  def show
    @rows = DataQuality::Status.by_kind
  end
end
