require "test_helper"
require_relative "../support/dummy_plugin"

# EIA-860M enrichment (#61). The workbook fixture holds real rows from EIA's
# August 2026 file: Vogtle 1-4, Farley 1, Hope Creek 1, Salem 1, Columbia 2,
# Arkansas Nuclear One 1-2, and one coal plant.
class DataQuality::Plugins::EiaGeneratorsTest < ActiveSupport::TestCase
  Plugin = DataQuality::Plugins::EiaGenerators
  Workbook = Plugin::Workbook
  INDEX = Plugin::INDEX_URL
  FILE = "https://www.eia.gov/electricity/data/eia860m/xls/august_generator2026.xlsx"

  setup do
    stub_request(:get, "https://www.eia.gov/robots.txt").to_return(body: "User-agent: *\nDisallow: /private/\n")
    stub_request(:get, INDEX).to_return(body: <<~HTML)
      <a href="xls/july_generator2026.xlsx">July 2026</a>
      <a href="xls/august_generator2026.xlsx">August 2026</a>
      <a href="archive/xls/december_generator2025.xlsx">December 2025</a>
    HTML
    stub_request(:get, FILE).to_return(body: file_fixture("eia/generators_sample.xlsx").binread)
  end

  def plugin = Plugin.new(fetcher: DataQuality::Fetcher.new(sleeper: ->(_) { }))
  def crawl! = plugin.crawl(CrawlRun.create!(stage: "crawl", source_kind: "eia_generators"))
  def source = Source.find_by!(url: FILE)

  def nrc_unit(name, docket, state, **attributes)
    Facility.create!(name: name, nrc_docket: docket, state: state, facility_type: "power_reactor", **attributes)
  end

  def match_and_verify!(verifier: PublishEverything.new)
    DataQuality::Pipeline.run("eia_generators", plugin: plugin, only: %w[extract match verify], verifier: verifier)
  end

  test "reads only the nuclear rows, keeping EIA's values verbatim" do
    generators = Workbook.nuclear_generators(file_fixture("eia/generators_sample.xlsx").binread)

    assert_equal 10, generators.size, "the coal plant is left out"
    vogtle = generators.find { |g| g["plant_name"] == "Vogtle" && g["generator_id"] == "1" }
    assert_equal({ "state" => "GA", "net_summer_capacity_mw" => "1150", "eia_plant_id" => "649" },
      vogtle.slice("state", "net_summer_capacity_mw", "eia_plant_id"))
  end

  test "an unreadable file or a changed layout is reported, not guessed at" do
    assert_raises(Workbook::Unreadable) { Workbook.nuclear_generators("not a zip") }
  end

  test "crawl picks the newest monthly file and stores its nuclear rows" do
    stats = crawl!

    assert_equal FILE, stats["file"]
    assert_equal 10, stats["generators"]
    assert source.crawl_ok?
    assert_equal "EIA-860M generator inventory, August 2026", source.title
    assert_equal 11, source.content_text.lines.size, "header plus one line per generator"
  end

  test "a newer monthly file withdraws the older file's unpublished candidates" do
    july = Source.create!(url: "https://www.eia.gov/electricity/data/eia860m/xls/july_generator2026.xlsx",
      source_kind: "eia_generators", crawl_status: "ok")
    waiting = Candidate.create!(source: july, kind: "facility", quote: "old row", payload: { "identify" => { "name" => "Vogtle" } })
    published = Candidate.create!(source: july, kind: "facility", quote: "older row", status: "merged", payload: {},
      subject_type: "Facility", subject_id: facilities(:vogtle).id)

    assert_equal 1, crawl!["superseded"]

    assert waiting.reload.status_rejected?
    assert_equal "Superseded by the newer EIA-860M generator inventory, August 2026", waiting.notes
    assert published.reload.status_merged?, "what's published stays"
  end

  test "a damaged sheet inside the workbook is reported, not a crash" do
    bytes = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("xl/workbook.xml")
      zip.write("<workbook><sheets><sheet name=\"Operating\" r:id=\"rId1\"")
    end.string

    assert_raises(Workbook::Unreadable) { Workbook.nuclear_generators(bytes) }
  end

  test "EIA's index page is fetched at most once a day, like any source" do
    crawl!
    crawl!

    assert_requested :get, INDEX, times: 1
    assert_equal "eia_860m_index", Source.find_by!(url: INDEX).source_kind, "never extracted"
  end

  test "a unit match writes nothing until it's published" do
    unit = nrc_unit("Vogtle 1", "05000424", "GA")
    crawl!
    DataQuality::Pipeline.run("eia_generators", plugin: plugin, only: %w[extract match])

    assert_nil unit.reload.capacity_mw
    assert_empty unit.evidence
  end

  test "a rejected unit isn't enriched; the generator goes to review" do
    nrc_unit("Vogtle 1", "05000424", "GA").reject!(by: "agent:verifier/x")
    crawl!

    match_and_verify!

    vogtle_1 = Candidate.where(source: source).find { |c| c.payload["identify"].values_at("name", "unit") == %w[Vogtle 1] }
    assert vogtle_1.status_needs_review?
    assert_match "which was rejected", vogtle_1.notes
  end

  test "a workbook that can't be read marks the source for a human" do
    stub_request(:get, FILE).to_return(body: "<html>maintenance</html>")

    assert_equal "needs_human", crawl!["snapshot"]
    assert source.crawl_needs_human?
    assert_match "Couldn't read the EIA workbook", source.status_reason

    assert source.fetched_at, "a file that can't be read still counts as today's fetch"
    crawl!
    assert_requested :get, FILE, times: 1
  end

  test "a number column holding something else is reported, not read as zero" do
    row = { "plant_name" => "Vogtle", "generator_id" => "1", "net_summer_capacity_mw" => "1150", "latitude" => "N/A" }

    error = assert_raises(Workbook::Unreadable) { Workbook.allocate.send(:check_numbers!, row) }
    assert_equal 'Latitude is "N/A" for Vogtle 1, not a number', error.message
    assert_nothing_raised { Workbook.allocate.send(:check_numbers!, row.merge("latitude" => "-81.76", "longitude" => nil)) }
  end

  test "a nuclear row missing its plant, state or generator is reported, not skipped" do
    row = { "eia_plant_id" => "649", "plant_name" => "Vogtle", "state" => nil, "generator_id" => nil }

    error = assert_raises(Workbook::Unreadable) { Workbook.allocate.send(:check_identity!, row) }
    assert_equal "A nuclear row has no Plant State, Generator ID (plant 649)", error.message
    assert Workbook.allocate.send(:check_identity!, row.merge("state" => "GA", "generator_id" => "1"))
  end

  test "extract quotes each generator's row verbatim and rounds the values" do
    crawl!
    candidates = plugin.extract(source, nil)

    farley = candidates.find { |c| c[:payload]["identify"]["name"] == "Joseph M Farley" }
    assert_equal({ "name" => "Joseph M Farley", "state" => "AL", "unit" => "1", "eia_plant_id" => "6001" },
      farley[:payload]["identify"])
    assert_match(/\A\d+(\.\d)?\z/, farley[:payload]["capacity_mw"])
    assert_includes source.content_text, farley[:quote]
  end

  test "values land on the matching NRC unit, by state, name and unit number" do
    vogtle_1 = nrc_unit("Vogtle 1", "05000424", "GA")
    vogtle_3 = nrc_unit("Vogtle 3", "05200025", "GA")
    farley = nrc_unit("Farley 1", "05000348", "AL")
    hope_creek = nrc_unit("Hope Creek 1", "05000354", "NJ")
    salem = nrc_unit("Salem 1", "05000272", "NJ")
    crawl!

    match_and_verify!

    assert_equal 1150, vogtle_1.reload.capacity_mw
    assert vogtle_3.reload.capacity_mw.positive?
    assert farley.reload.latitude.present?
    assert hope_creek.reload.capacity_mw.positive?, "PSEG Hope Creek Generating Station → Hope Creek 1"
    assert_not_equal hope_creek.capacity_mw, salem.reload.capacity_mw, "two NJ plants kept apart"
    assert_equal [ "Vogtle 1" ], [ vogtle_1.name ], "EIA never renames"
  end

  test "a single-unit plant takes EIA's generator whatever its number" do
    columbia = nrc_unit("Columbia Generating Station", "05000397", "WA")
    crawl!

    match_and_verify!

    assert columbia.reload.capacity_mw.positive?, "EIA lists Columbia as generator 2"
  end

  test "EIA never creates facilities and doesn't change a unit's verification" do
    unit = nrc_unit("Vogtle 1", "05000424", "GA")
    crawl!

    assert_no_difference "Facility.count" do
      match_and_verify!
    end

    assert unit.reload.pending?, "EIA values don't verify the NRC unit"
    assert_equal [ "crawler" ], unit.evidence.distinct.pluck(:found_by)
  end

  test "generators without an NRC unit yet wait and are retried" do
    crawl!
    runs = match_and_verify!

    waiting = Candidate.where(source: source)
    assert waiting.all?(&:status_new?)
    assert_equal 10, runs[1].stats["waiting"]
    assert_equal 0, runs[2].stats["candidates"], "verify skips them"

    nrc_unit("Vogtle 2", "05000425", "GA")
    DataQuality::Pipeline.run("eia_generators", plugin: plugin, only: "match")
    assert_equal 1, Candidate.where(source: source).status_matched.count
  end

  test "a border plant NRC lists under a nearby city's state still matches, by the stricter rule" do
    # NRC's list gives Salem and Hope Creek the state of Wilmington, DE.
    salem = nrc_unit("Salem 1", "05000272", "DE")
    hope_creek = nrc_unit("Hope Creek 1", "05000354", "DE")
    crawl!

    match_and_verify!

    assert salem.reload.capacity_mw.positive?
    assert hope_creek.reload.capacity_mw.positive?
    assert_not_equal salem.capacity_mw, hope_creek.capacity_mw
  end

  test "a unit whose NRC record doesn't exist yet waits, even if its siblings do" do
    nrc_unit("Vogtle 3", "05200025", "GA")
    nrc_unit("Vogtle 4", "05200026", "GA")
    crawl!

    match_and_verify!

    vogtle_1 = Candidate.where(source: source).find { |c| c.payload["identify"].values_at("name", "unit") == %w[Vogtle 1] }
    assert vogtle_1.status_new?
    assert_match "retried on the next match run", vogtle_1.notes
  end

  test "two units that fit equally well go to review" do
    nrc_unit("Arkansas Nuclear 1", "05000313", "AR")
    nrc_unit("Arkansas River 1", "05000999", "AR")
    crawl!

    match_and_verify!(verifier: DataQuality::Verifiers::ReviewEverything.new)

    ano = Candidate.where(source: source).find { |c| c.payload["identify"].values_at("name", "unit") == [ "Arkansas Nuclear One", "1" ] }
    assert ano.status_needs_review?
    assert_match "could be Arkansas Nuclear 1 or Arkansas River 1", ano.notes
  end

  test "the closest name wins over a looser one" do
    exact = nrc_unit("Arkansas Nuclear One 1", "05000313", "AR")
    nrc_unit("Arkansas Nuclear 1", "05000999", "AR")
    crawl!

    match_and_verify!

    assert exact.reload.capacity_mw.positive?, "shares 'arkansas' and 'one' with EIA's name, not just 'arkansas'"
  end

  test "units without a state still match, and take EIA's state" do
    salem = nrc_unit("Salem 1", "05000272", nil)
    hope_creek = nrc_unit("Hope Creek 1", "05000354", nil)
    crawl!

    match_and_verify!

    assert_equal [ "NJ", "NJ" ], [ salem.reload.state, hope_creek.reload.state ]
    assert salem.capacity_mw.positive?
  end

  test "a verified unit's coordinates fill its site's blank ones" do
    facilities(:vogtle).destroy!
    site = Facility.create!(name: "Plant Vogtle Units 3 & 4")
    nrc_unit("Vogtle 3", "05200025", "GA", parent: site).verify!(by: "agent:verifier/nrc") # only a verified unit speaks for its site
    crawl!

    match_and_verify!

    assert site.reload.latitude.present?
    assert_nil site.capacity_mw, "capacity stays per unit"
  end
end
