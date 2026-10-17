# A plant or unit that's licensed but producing no power, as NRC's 365-day
# status file shows it (Palisades before its restart): not operating, which
# isn't shut down (permanently) or decommissioning.
class AddNotOperatingToFacilityStatus < ActiveRecord::Migration[8.1]
  BEFORE = %w[operating under_construction planned shut_down decommissioning].freeze
  AFTER = (BEFORE + %w[not_operating]).freeze

  def up
    replace_check AFTER
  end

  def down
    execute "UPDATE facilities SET status = NULL WHERE status = 'not_operating'"
    replace_check BEFORE
  end

  private
    def replace_check(statuses)
      remove_check_constraint :facilities, name: "facilities_status_check"
      add_check_constraint :facilities, "status IN (#{statuses.map { |status| connection.quote(status) }.join(', ')})", name: "facilities_status_check"
    end
end
