# Reads NRC's PowerReactorStatusForLast365Days.txt: pipe-delimited
# "ReportDt|Unit|Power" lines, one per unit per day. Used only to
# cross-check the reactor list page.
class DataQuality::Plugins::NrcReactorList::StatusFile
  # The unit names on the most recent report date, or [] if none parse.
  def self.latest_units(text)
    rows = text.to_s.each_line.filter_map do |line|
      date, unit, _power = line.chomp.split("|", 3)
      date = parse_date(date)
      [ date, unit.squish ] if date && unit.present?
    end
    return [] if rows.empty?

    latest = rows.map(&:first).max
    rows.select { |date, _| date == latest }.map(&:last).uniq
  end

  # "10/9/2026 12:00:00 AM" (the documented format) or an ISO date.
  def self.parse_date(value)
    value = value.to_s.strip.split(" ").first.to_s
    Date.strptime(value, "%m/%d/%Y")
  rescue Date::Error
    Date.iso8601(value) rescue nil
  end
  private_class_method :parse_date
end
