require "csv"

# Reads the nuclear generators from EIA's monthly generator inventory
# (Form EIA-860M, an .xlsx). Only the "Operating" sheet, only rows whose
# Technology is "Nuclear". The sheet has ~28,000 rows, so it's streamed
# rather than loaded whole.
#
# The rows that matter are stored as CSV (to_csv), so each candidate can quote
# its row verbatim from the source's content_text.
class DataQuality::Plugins::EiaGenerators::Workbook
  class Unreadable < StandardError; end

  SHEET = "Operating"
  # Our name => EIA's column header.
  COLUMNS = {
    "eia_plant_id" => "Plant ID",
    "plant_name" => "Plant Name",
    "generator_id" => "Generator ID",
    "state" => "Plant State",
    "county" => "County",
    "net_summer_capacity_mw" => "Net Summer Capacity (MW)",
    "nameplate_capacity_mw" => "Nameplate Capacity (MW)",
    "status" => "Status",
    "latitude" => "Latitude",
    "longitude" => "Longitude",
    "entity_name" => "Entity Name"
  }.freeze
  TECHNOLOGY = "Technology"
  NUCLEAR = "Nuclear"
  # Columns that must be a plain number when present. Anything else (say
  # "N/A") means the layout changed, and is reported rather than read as 0.
  NUMERIC = %w[net_summer_capacity_mw nameplate_capacity_mw latitude longitude].freeze
  NUMBER = /\A-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?\z/
  # What identifies a generator. A nuclear row without one of these can't be
  # matched to its unit, so it means the data changed: reported, not skipped.
  IDENTITY = %w[eia_plant_id plant_name state generator_id].freeze

  # Returns an array of hashes keyed by COLUMNS' names. Raises Unreadable
  # when the file isn't a workbook, the sheet or a column is missing, a
  # number column holds something that isn't a number, or no nuclear rows
  # are found (EIA may have changed the layout).
  def self.nuclear_generators(bytes)
    new(bytes).nuclear_generators
  rescue Nokogiri::XML::SyntaxError, Zip::Error, Zlib::Error => error
    # A damaged sheet or archive is reported like any other unreadable file.
    raise Unreadable, "The workbook is damaged: #{error.class}: #{error.message}"
  end

  def self.to_csv(generators)
    CSV.generate { |csv| csv << COLUMNS.keys; generators.each { |g| csv << g.values_at(*COLUMNS.keys) } }
  end

  def initialize(bytes)
    @zip = Zip::File.open_buffer(StringIO.new(bytes))
  rescue Zip::Error => error
    raise Unreadable, "Not a readable .xlsx: #{error.message}"
  end

  def nuclear_generators
    header = nil
    generators = []

    each_row(sheet_path) do |cells|
      if header.nil?
        # Title rows come first; the header is the row naming "Plant ID".
        header = cells.invert if cells.value?(COLUMNS["eia_plant_id"])
        next
      end
      next unless cells[header[TECHNOLOGY]].to_s.strip == NUCLEAR

      generators << COLUMNS.transform_values { |title| cells[header[title]]&.strip.presence }
        .tap { |row| check_identity!(row) && check_numbers!(row) }
    end

    raise Unreadable, "No header row with #{COLUMNS['eia_plant_id'].inspect} on the #{SHEET} sheet" unless header
    missing = (COLUMNS.values + [ TECHNOLOGY ]) - header.keys
    raise Unreadable, "Columns missing from the #{SHEET} sheet: #{missing.join(', ')}" if missing.any?
    raise Unreadable, "No nuclear generators on the #{SHEET} sheet" if generators.empty?

    generators
  end

  # Namespaces are dropped throughout: a row read from the stream on its
  # own doesn't carry the sheet's namespace declarations.
  private
    def check_identity!(row)
      missing = IDENTITY.select { |column| row[column].nil? }
      return true if missing.empty?

      raise Unreadable, "A nuclear row has no #{missing.map { |column| COLUMNS[column] }.join(', ')} " \
        "(plant #{row['eia_plant_id'] || row['plant_name'] || 'unknown'})"
    end

    def check_numbers!(row)
      NUMERIC.each do |column|
        value = row[column]
        next if value.nil? || value.match?(NUMBER)

        raise Unreadable, "#{COLUMNS[column]} is #{value.inspect} for #{row['plant_name']} #{row['generator_id']}, not a number"
      end
    end

    def sheet_path
      sheet = xml("xl/workbook.xml").at_xpath("//sheet[@name='#{SHEET}']") or raise Unreadable, "No #{SHEET.inspect} sheet"
      target = xml("xl/_rels/workbook.xml.rels").at_xpath("//Relationship[@Id='#{sheet['id']}']")&.[]("Target")
      raise Unreadable, "Can't find the #{SHEET} sheet's file" unless target

      target.start_with?("/") ? target.delete_prefix("/") : "xl/#{target}"
    end

    # Yields each row as { "A" => "Plant ID", "B" => … }. The sheet is read
    # from the zip as a stream, never held whole in memory.
    def each_row(path)
      entry = @zip.find_entry(path) or raise Unreadable, "Missing #{path}"
      # Loaded before the sheet is streamed: entries of one in-memory zip share
      # its buffer, so reading another entry mid-stream would corrupt the sheet.
      shared_strings
      Nokogiri::XML::Reader(entry.get_input_stream).each do |node|
        next unless node.name == "row" && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

        row = Nokogiri::XML(node.outer_xml).remove_namespaces!
        yield row.xpath("//c").to_h { |cell| [ cell["r"][/\A[A-Z]+/], value(cell) ] }
      end
    end

    def value(cell)
      case cell["t"]
      when "s" then shared_strings[cell.at_xpath("v")&.text.to_i]
      when "inlineStr" then cell.xpath(".//t").map(&:text).join
      else cell.at_xpath("v")&.text
      end
    end

    def shared_strings
      @shared_strings ||= @zip.find_entry("xl/sharedStrings.xml") ?
        xml("xl/sharedStrings.xml").xpath("//si").map { |si| si.xpath(".//t").map(&:text).join } : []
    end

    def xml(path) = Nokogiri::XML(read(path)).remove_namespaces!

    def read(path)
      entry = @zip.find_entry(path) or raise Unreadable, "Missing #{path}"
      entry.get_input_stream.read
    end
end
