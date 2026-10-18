require "test_helper"

# The fixture is isotopes.gov's real "DOE IRP Production Sites" page, fetched
# 2026-10-17 with the plug-in's Fetcher and cut to its main content.
class DataQuality::Plugins::DoeIsotopeSitesTest < ActiveSupport::TestCase
  Plugin = DataQuality::Plugins::DoeIsotopeSites
  LABS = [ "Brookhaven National Laboratory", "Los Alamos National Laboratory", "Oak Ridge National Laboratory",
    "Idaho National Laboratory", "Savannah River National Laboratory", "Argonne National Laboratory",
    "Y-12 National Security Complex", "Pacific Northwest National Laboratory" ].freeze
  SCHOOLS = [ "University of Washington", "University of Missouri Research Reactor Center", "University of Wisconsin",
    "University of Alabama-Birmingham", "Texas A&M University", "Michigan State University" ].freeze

  setup do
    stub_request(:get, "https://www.isotopes.gov/robots.txt").to_return(body: "User-agent: *\nDisallow: /admin/\n")
    @page = stub_request(:get, Plugin::PAGE_URL).to_return(body: html)
  end

  def html = file_fixture("doe/production-network.html").read
  def plugin = Plugin.new(fetcher: DataQuality::Fetcher.new(sleeper: ->(_) { }))
  def crawl = DataQuality::Stages::Crawl.call(plugin:)
  def page_source = Source.find_by!(url: Plugin::PAGE_URL)
  def stored(content = html) = Source.create!(url: Plugin::PAGE_URL, source_kind: "doe_isotope_sites", crawl_status: "ok",
    content_text: content, content_sha256: Digest::SHA256.hexdigest(content))
  def names(candidates, kind, role = nil)
    candidates.select { |c| c[:kind] == kind && (role.nil? || c[:payload]["role"] == role) }
      .map { |c| c[:payload]["name"] || c[:payload].dig("organization", "name") }
  end

  test "is the plug-in for doe_isotope_sites" do
    assert_instance_of Plugin, DataQuality::Plugin.for("doe_isotope_sites")
  end

  test "crawls the page once a day and counts what it names" do
    run = crawl
    second = crawl

    assert_equal({ "page" => "changed", "labs" => 8, "schools" => 6 }, run.stats)
    assert_equal "skipped_recent", second.stats["page"]
    assert_requested @page, times: 1
    assert_equal "doe_isotope_sites", page_source.source_kind
  end

  test "a blocked page stops the crawl" do
    stub_request(:get, Plugin::PAGE_URL).to_return(status: 403, body: "Access Denied")

    assert_equal({ "page" => "blocked", "stopped" => "page blocked" }, crawl.stats)
    assert page_source.crawl_blocked?
  end

  test "a page without its sentences needs a human, and extracts nothing" do
    stub_request(:get, Plugin::PAGE_URL).to_return(body: "<html><body><article><p>We moved things around.</p></article></body></html>")

    assert_equal 0, crawl.stats["labs"]
    assert page_source.crawl_needs_human?
    assert_raises(Plugin::LayoutChanged) { plugin.extract(page_source, nil) }
  end

  test "names only the labs and schools the page's own sentences name" do
    source = stored
    candidates = plugin.extract(source, nil)

    assert_equal LABS + SCHOOLS, names(candidates, "organization")
    assert_equal LABS + SCHOOLS, names(candidates, "organization_role", "isotopes")
    assert_equal LABS - [ "Y-12 National Security Complex" ], names(candidates, "organization_role", "national_lab"),
      "only a name that says National Laboratory"
    assert_equal SCHOOLS, names(candidates, "organization_role", "university")
    assert candidates.all? { |c| plugin.quote_in_source?(source, c[:quote]) }, "every quote is the page's own sentence"
    assert candidates.all? { |c| c[:quote].include?(c[:payload]["name"] || c[:payload].dig("organization", "name")) },
      "every quote names its company"
  end

  test "a lab keeps its abbreviation as an alias, from the page" do
    brookhaven = plugin.extract(stored, nil).find { |c| c[:kind] == "organization" && c[:payload]["name"] == "Brookhaven National Laboratory" }

    assert_equal [ "BNL" ], brookhaven[:payload]["aliases"]
    assert_match "has stewardship over the Brookhaven Linear Isotope Producer", brookhaven[:quote]
  end

  test "a lab's isotopes claim goes on, a university's waits for a person" do
    candidates = plugin.extract(stored, nil).select { |c| c[:payload]["role"] == "isotopes" }
    lab, school = candidates.partition { |c| LABS.include?(c[:payload].dig("organization", "name")) }

    assert lab.none? { |c| c[:status] }
    assert school.all? { |c| c[:status] == "needs_review" && c[:notes] == Plugin::NETWORK_NOTE }
  end

  test "a lab named outside a sentence about producing isotopes isn't proposed" do
    content = html.sub("supports the production of isotopes at", "supports research at")
    candidates = plugin.extract(stored(content), nil)

    assert_not_includes names(candidates, "organization"), "Idaho National Laboratory"
    assert_includes names(candidates, "organization"), "Brookhaven National Laboratory", "the first sentence still says it"
  end

  test "the rows hash covers the page's sentences, not its markup" do
    a = Source.new(url: Plugin::PAGE_URL, content_text: html)
    b = Source.new(url: Plugin::PAGE_URL, content_text: html.sub("<body>", "<body class=\"restyled\">"))
    c = Source.new(url: Plugin::PAGE_URL, content_text: html.sub("six schools", "seven schools"))

    assert_equal plugin.rows_sha256(a), plugin.rows_sha256(b)
    assert_not_equal plugin.rows_sha256(a), plugin.rows_sha256(c)
  end

  test "tells the verifier what the page states" do
    assert_match "isotope production site", plugin.source_facts(Source.new(url: Plugin::PAGE_URL))
  end

  test "end to end: an existing lab is matched, not duplicated" do
    Role.find_or_create_by!(key: "isotopes") { |role| role.name = "Isotopes" }
    Role.find_or_create_by!(key: "national_lab") { |role| role.name = "National lab" }
    Role.find_or_create_by!(key: "university") { |role| role.name = "University" }
    oak_ridge = Organization.create!(name: "Oak Ridge National Laboratory", verification_status: "verified", verified_by: "human:test")
    oak_ridge.aliases.create!(alias: oak_ridge.name) # as FactWriter writes a company's own name

    %w[crawl extract match].each { |stage| DataQuality::Pipeline.run("doe_isotope_sites", plugin:, only: stage) }

    claim = Candidate.find_by!(kind: "organization", payload: { "name" => "Oak Ridge National Laboratory", "aliases" => [ "ORNL" ] })
    assert_equal oak_ridge.id, claim.subject_id
    assert_equal 1, Organization.where(name: "Oak Ridge National Laboratory").count
  end
end
