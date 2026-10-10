require "test_helper"

class DataQuality::Plugins::NrcReactorList::ExtractTest < ActiveSupport::TestCase
  Plugin = DataQuality::Plugins::NrcReactorList
  Extractor = Plugin::Extractor

  # Stands in for the extractor model. By default it reads every row
  # correctly; `tamper` lets a test make it get a unit wrong, skip it, or
  # invent one. Its answers are checked against the real schema, so the
  # fake can't return anything the real model couldn't.
  class FakeModel
    Response = Data.define(:data)
    attr_reader :calls

    def initialize(&tamper)
      @tamper = tamper || ->(units) { units }
      @calls = []
    end

    def structured(role:, messages:, schema:, schema_name:, crawl_run:)
      @calls << { role:, schema_name: }
      _header, *rows = messages.last[:content].lines(chomp: true)
      units = @tamper.call(rows.map { |row| read(row) })
      errors = JSONSchemer.schema(schema).validate({ "units" => units }).to_a
      raise "fake answered outside the schema: #{errors.first["error"]}" if errors.any?

      Response.new(data: { "units" => units })
    end

    private
      def read(row)
        name, docket, _license, type, location, operator, _region = row.split(" | ")
        { "name" => name, "nrc_docket" => docket, "reactor_type" => type,
          "state" => location[/([A-Z]{2})\z/, 1], "operator" => operator, "quote" => row }
      end
  end

  setup do
    @source = Source.create!(url: Plugin::LIST_URL, source_kind: "nrc_reactor_list", crawl_status: "ok",
      content_text: file_fixture("nrc/list-power-reactor-units.html").read)
    @source.update!(content_sha256: Digest::SHA256.hexdigest(@source.content_text))
  end

  def extract(model = FakeModel.new)
    plugin = Plugin.new(fetcher: nil, extractor: Extractor.new(llm: model))
    DataQuality::Stages::Extract.call(plugin: plugin)
  end

  def candidates_for(docket)
    @source.candidates.select { |c| c.payload["nrc_docket"] == docket || c.payload.dig("facility", "nrc_docket") == docket }
  end

  test "when the model agrees with the table, every unit becomes candidates" do
    model = FakeModel.new
    run = extract(model)

    assert run.succeeded?
    assert_equal "nrc-extract-v1", run.prompt_version
    assert_equal 4, model.calls.size, "95 rows in batches of 25"
    assert model.calls.all? { |call| call[:role] == :extract }
    assert_equal({ "table_units" => 95, "ai_units" => 95, "agreed" => 95, "disagreed" => 0, "missed" => 0, "made_up" => 0 },
      run.stats["ai_check"])

    by_kind = @source.candidates.group_by(&:kind)
    assert_equal 95, by_kind["facility"].size
    assert_equal 95, by_kind["facility_relationship"].size
    operators = by_kind["organization"].map { |c| c.payload["name"] }
    assert_equal operators.uniq, operators, "one candidate per operator"
    assert_includes operators, "Southern Nuclear Operating Co."
    assert @source.candidates.all?(&:status_new?)
    rows = Plugin::Page.lines(@source.content_text)
    assert @source.candidates.all? { |c| rows.include?(c.quote) }, "every quote is a row of the page"
    assert_equal @source.content_sha256, @source.reload.extracted_sha256
  end

  # Checked by hand against the NRC page (fixture fetched 2026-10-10).
  HAND_CHECKED = {
    "05200025" => [ "Vogtle 3", "PWR", "Southern Nuclear Operating Co." ],
    "05200026" => [ "Vogtle 4", "PWR", "Southern Nuclear Operating Co." ],
    "05000315" => [ "D.C. Cook 1", "PWR", "Indiana/Michigan Power Co." ],
    "05000259" => [ "Browns Ferry 1", "BWR", "Tennessee Valley Authority" ],
    "05000416" => [ "Grand Gulf 1", "BWR", "Entergy Nuclear Operations, Inc." ],
    "05000255" => [ "Palisades", "PWR", "Holtec Palisades, LLC" ]
  }.freeze

  test "matches a hand-checked sample, in the shape match expects" do
    extract

    HAND_CHECKED.each do |docket, (name, type, operator)|
      facility = candidates_for(docket).find(&:kind_facility?)
      link = candidates_for(docket).find(&:kind_facility_relationship?)

      assert_equal({ "name" => name, "nrc_docket" => docket, "facility_type" => "power_reactor", "status" => "operating",
        "reactor_type" => type, "country_code" => "US" }, facility.payload, name)
      assert_equal({ "organization" => { "name" => operator }, "facility" => { "name" => name, "nrc_docket" => docket },
        "relationship_type" => "operates" }, link.payload, name)
      assert_match(/\A#{Regexp.escape(name)} \| #{docket} \|/, facility.quote)
    end
  end

  test "a unit the model gets wrong goes to review with both values; the table's values are kept" do
    run = extract(FakeModel.new { |units| units.map { |u| u["nrc_docket"] == "05200025" ? u.merge("reactor_type" => "BWR") : u } })

    assert_equal 1, run.stats["ai_check"]["disagreed"]
    vogtle3 = candidates_for("05200025")
    assert_equal 2, vogtle3.size
    assert vogtle3.all?(&:status_needs_review?)
    assert_match 'reactor type: model said "BWR", table says "PWR"', vogtle3.first.notes
    assert_equal "PWR", vogtle3.find(&:kind_facility?).payload["reactor_type"]
    assert candidates_for("05200026").all?(&:status_new?), "other units are unaffected"
  end

  test "never publishes NRC's state, which is the nearby city's, not always the plant's" do
    extract

    salem = candidates_for("05000272").find(&:kind_facility?)
    assert_equal "Salem 1", salem.payload["name"]
    assert_match "of Wilmington, DE", salem.quote, "NRC measures from Wilmington, DE; the plant is in NJ"
    assert @source.candidates.select(&:kind_facility?).none? { |c| c.payload.key?("state") }
  end

  test "values are checked exactly, so a tidied copy isn't counted as agreement" do
    tidied = { "05000315" => { "name" => "DC Cook 1" },
               "05000259" => { "operator" => "TENNESSEE VALLEY AUTHORITY" },
               "05200026" => { "quote" => "Vogtle 4 |  05200026 | NPF-92 | PWR | 26 miles SE of Augusta, GA | Southern Nuclear Operating Co. | 2" } }
    run = extract(FakeModel.new { |units| units.map { |u| u.merge(tidied.fetch(u["nrc_docket"], {})) } })

    assert_equal 3, run.stats["ai_check"]["disagreed"]
    assert_match 'name: model said "DC Cook 1", table says "D.C. Cook 1"', candidates_for("05000315").first.notes
    assert_match "operator: model said", candidates_for("05000259").first.notes
    assert_match "quote isn't the table row", candidates_for("05200026").first.notes
  end

  test "an operator is only confirmed through a row the model agreed on" do
    extract(FakeModel.new do |units|
      units.reject { |u| u["name"] == "Palisades" }.map { |u| u["nrc_docket"] == "05200025" ? u.merge("state" => "SC") : u }
    end)
    operator = ->(name) { @source.candidates.find { |c| c.kind_organization? && c.payload["name"] == name } }

    holtec = operator.("Holtec Palisades, LLC")
    assert holtec.status_needs_review?, "its only unit was skipped"
    assert_match "didn't confirm any row for this operator", holtec.notes
    southern = operator.("Southern Nuclear Operating Co.")
    assert southern.status_new?, "Vogtle 3 was wrong, but the model agreed on its other units"
    assert_no_match(/\AVogtle 3 \|/, southern.quote, "quoted from an agreed row, not the wrong one")
    assert_match "| Southern Nuclear Operating Co. |", southern.quote
  end

  test "a quote that isn't the row as written goes to review" do
    extract(FakeModel.new { |units| units.map { |u| u["nrc_docket"] == "05000416" ? u.merge("quote" => "Grand Gulf 1 is a BWR") : u } })

    assert candidates_for("05000416").all?(&:status_needs_review?)
    assert_match "quote isn't the table row", candidates_for("05000416").first.notes
  end

  test "a unit the model skips still gets candidates, sent to review" do
    run = extract(FakeModel.new { |units| units.reject { |u| u["name"] == "Palisades" } })

    assert_equal 1, run.stats["ai_check"]["missed"]
    palisades = candidates_for("05000255")
    assert_equal 2, palisades.size
    assert palisades.all?(&:status_needs_review?)
    assert_match "skipped this unit", palisades.first.notes
  end

  test "a unit the model invents is dropped and counted" do
    invented = { "name" => "Imaginary 1", "nrc_docket" => "09999999", "reactor_type" => "PWR", "state" => "ZZ",
      "operator" => "Nobody", "quote" => "Imaginary 1 | 09999999" }
    once = true
    run = extract(FakeModel.new { |units| once ? (once = false; units + [ invented ]) : units })

    assert_equal 1, run.stats["ai_check"]["made_up"]
    assert_empty candidates_for("09999999")
    assert_not @source.candidates.any? { |c| c.payload["name"] == "Nobody" }
  end

  test "if the model fails, the run fails and the page is extracted again next time" do
    broken = Object.new
    def broken.structured(**) = raise(DataQuality::OpenRouter::Client::RetriesExhausted, "Gave up after 3 attempts")

    assert_raises(DataQuality::OpenRouter::Client::RetriesExhausted) { extract(broken) }

    assert CrawlRun.where(stage: "extract").sole.failed?
    assert_empty @source.candidates
    assert_nil @source.reload.extracted_sha256
  end
end
