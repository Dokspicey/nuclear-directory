# Reads the reactor table on NRC's "List of Power Reactor Units" page, two ways:
# - units: an exact parse, one Unit per row (the ground truth extract checks against)
# - lines: the table as plain text, one line per row, which the extractor
#   model reads and quotes from
class DataQuality::Plugins::NrcReactorList::Page
  Unit = Data.define(:name, :nrc_docket, :license_number, :reactor_type, :location, :state,
    :owner_operator, :nrc_region, :nrc_path)

  # Returns [] when the table isn't there, e.g. after a site redesign.
  def self.units(html)
    table = table_in(html) or return []
    table.css("tr").filter_map { |row| unit_from(row.css("td")) }
  end

  # The header and every row, cells separated by " | ". The first cell
  # holds two values (name<br>docket), so it becomes two columns; every
  # other cell is one column, its lines joined ("Reactor<br>Type" =>
  # "Reactor Type"). Header and rows line up at 7 columns:
  #   "Vogtle 3 | 05200025 | NPF-91 | PWR | 26 miles SE of Augusta, GA | Southern Nuclear Operating Co. | 2"
  def self.lines(html)
    table = table_in(html) or return []
    table.css("tr").map do |row|
      first, *rest = row.css("th, td").map { |cell| cell.xpath(".//text()").map { |node| node.text.squish }.compact_blank }
      [ *first, *rest.map { |pieces| pieces.join(" ") } ].join(" | ")
    end
  end

  def self.table_in(html)
    doc = Nokogiri::HTML(html.to_s)
    doc.at_css('table[summary="List of Power Reactor Units"]') ||
      doc.css("table").find { |t| t.at_css("th")&.text.to_s.include?("Docket") }
  end
  private_class_method :table_in

  def self.unit_from(cells)
    return if cells.size < 6

    # "Name<br>Docket": read the text pieces separately, since the cell's
    # joined text runs the unit number into the docket ("…205000368").
    first = cells[0]
    pieces = first.xpath(".//text()").map { |node| node.text.squish }.compact_blank
    name = first.at_css("a")&.text&.squish || pieces.first
    docket = pieces.find { |piece| piece.match?(/\A\d{8}\z/) }
    return if name.blank? || docket.nil?

    location = cells[3].text.squish
    Unit.new(
      name: name,
      nrc_docket: docket,
      license_number: cells[1].text.squish,
      reactor_type: cells[2].text.squish,
      location: location,
      state: location[/,\s*([A-Z]{2})\z/, 1],
      owner_operator: cells[4].text.squish,
      nrc_region: cells[5].text.squish,
      nrc_path: first.at_css("a")&.[]("href")
    )
  end
  private_class_method :unit_from
end
