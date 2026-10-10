require "test_helper"
require_relative "../support/dummy_plugin"

# Match against the real directory with NRC-style names, since what matters
# is how real names and dockets resolve.
class DataQuality::Stages::MatchTest < ActiveSupport::TestCase
  include ReviewHelpers

  setup do
    @source = Source.create!(url: "https://www.nrc.gov/test/match-stage-sample.html",
      source_kind: "dummy", crawl_status: "ok")
  end

  def candidate(kind, payload, quote: "row from the NRC list")
    Candidate.create!(source: @source, kind: kind, payload: payload, quote: quote)
  end

  def match! = DataQuality::Stages::Match.call(plugin: DummyPlugin.new)

  def facility_payload(name, docket) = { "name" => name, "nrc_docket" => docket, "facility_type" => "power_reactor" }

  # The seed's Vogtle record, in place of the fixture's (two Vogtle sites would be ambiguous).
  def vogtle_site!
    facilities(:vogtle).destroy!
    Facility.create!(name: "Plant Vogtle Units 3 & 4")
  end

  test "a facility matched by NRC docket is attached; its quote is added only on approval" do
    site = Facility.create!(name: "Braidwood Station", nrc_docket: "05000456")
    c = candidate("facility", facility_payload("Braidwood 1", "05000456"), quote: "Braidwood 1 05000456")

    run = match!

    c.reload
    assert c.status_matched?
    assert_equal [ "Facility", site.id ], [ c.subject_type, c.subject_id ]
    assert_match "by NRC docket", c.notes
    assert_equal "Braidwood Station", site.reload.name, "matching doesn't overwrite the record"
    assert_empty site.evidence, "nothing is written to an existing record before verification"
    assert_equal 1, run.stats["matched"]

    verify = DataQuality::Stages::Verify.call(plugin: DummyPlugin.new, verifier: PublishEverything.new)
    assert_empty site.reload.evidence, "verify only recommends"
    approve_recommended
    evidence = site.evidence.sole
    assert_equal [ "crawler", "Braidwood 1 05000456", verify.id ], [ evidence.found_by, evidence.quote, evidence.crawl_run_id ]
  end

  test "an unknown facility is proposed as a new pending record" do
    c = candidate("facility", facility_payload("Arkansas Nuclear 1", "05000313"))

    run = match!

    facility = Facility.find(c.reload.subject_id)
    assert c.status_matched?
    assert_equal [ "Arkansas Nuclear 1", "05000313" ], [ facility.name, facility.nrc_docket ]
    assert facility.pending?
    assert_match "proposed a new pending one", c.notes
    assert_equal 1, run.stats["proposed"]
  end

  test "units with different dockets aren't mistaken for duplicates" do
    first = candidate("facility", facility_payload("Braidwood 1", "05000456"))
    second = candidate("facility", facility_payload("Braidwood 2", "05000457"))

    match!

    assert [ first, second ].all? { |c| c.reload.status_matched? }
    assert_not_equal first.subject_id, second.subject_id
  end

  test "an NRC unit is added under the seed site it clearly belongs to" do
    site = vogtle_site!
    c = candidate("facility", facility_payload("Vogtle 3", "05200025"))

    run = match!

    unit = Facility.find(c.reload.subject_id)
    assert c.status_matched?
    assert_equal [ "Vogtle 3", "05200025", site.id ], [ unit.name, unit.nrc_docket, unit.parent_id ]
    assert unit.pending?
    assert_match "under the existing site Plant Vogtle Units 3 & 4", c.notes
    assert_equal 1, run.stats["proposed"]
  end

  test "a site whose name lists no units takes any of its units" do
    site = Facility.create!(name: "Clinton Clean Energy Center")
    single = candidate("facility", facility_payload("Clinton", "05000461"))
    lasalle = Facility.create!(name: "La Salle County Station")
    numbered = candidate("facility", facility_payload("LaSalle 1", "05000373"))

    match!

    assert_equal site.id, Facility.find(single.reload.subject_id).parent_id
    assert_equal lasalle.id, Facility.find(numbered.reload.subject_id).parent_id, "spacing differences still match"
  end

  test "a unit is never placed under a rejected site" do
    vogtle_site!.reject!(by: "human:tosin")
    c = candidate("facility", facility_payload("Vogtle 3", "05200025"))

    assert_no_difference "Facility.count" do
      match!
    end

    assert c.reload.status_needs_review?
    assert_match "which was rejected", c.notes
  end

  test "a unit the site record doesn't cover goes to review, never merged" do
    vogtle_site!
    Facility.create!(name: "Palisades Pioneer Units 1 & 2 (SMR-300)")
    older = candidate("facility", facility_payload("Vogtle 1", "05000424"))
    unnumbered = candidate("facility", facility_payload("Palisades", "05000255"))

    assert_no_difference "Facility.count" do
      match!
    end

    assert older.reload.status_needs_review?
    assert_match "only covers unit 3 & 4", older.notes
    assert unnumbered.reload.status_needs_review?
    assert_match "only covers unit 1 & 2", unnumbered.notes
  end

  test "sibling units all go under the same site" do
    site = vogtle_site!
    units = [ facility_payload("Vogtle 3", "05200025"), facility_payload("Vogtle 4", "05200026") ]
      .map { |payload| candidate("facility", payload) }

    match!

    assert_equal [ site.id, site.id ], units.map { |c| Facility.find(c.reload.subject_id).parent_id }
  end

  test "more than one possible site goes to review" do
    Facility.create!(name: "Susquehanna Steam Electric Station")
    Facility.create!(name: "Susquehanna Riverlands")
    c = candidate("facility", facility_payload("Susquehanna 1", "05000387"))

    match!

    assert c.reload.status_needs_review?
    assert_match "Susquehanna Steam Electric Station; Susquehanna Riverlands", c.notes
  end

  test "a facility without a docket isn't treated as a unit" do
    c = candidate("facility", { "name" => "Vogtle Visitor Center" })

    match!

    assert c.reload.status_needs_review?
    assert_match "Vogtle Electric Generating Plant", c.notes
  end

  test "docket and name pointing at different facilities goes to review" do
    Facility.create!(name: "Unit A", nrc_docket: "05000001")
    Facility.create!(name: "Unit B", nrc_docket: "05000002")
    c = candidate("facility", facility_payload("Unit B", "05000001"))

    match!

    assert c.reload.status_needs_review?
    assert_match "docket matches Unit A but name matches Unit B", c.notes
  end

  test "an organization matched by name keeps its record and status" do
    terrapower = organizations(:terrapower)
    terrapower.verify!(by: "human:tosin")
    c = candidate("organization", { "name" => "TerraPower, Inc." })

    match!

    assert c.reload.status_matched?
    assert_equal terrapower.id, c.subject_id
    terrapower.reload
    assert terrapower.verified?
    assert_equal "human:tosin", terrapower.verified_by
    assert_equal "TerraPower", terrapower.name
  end

  test "the name a match was found under becomes an alias only once it's approved" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "domain" => "terrapower.com" })

    match!

    assert_equal organizations(:terrapower).id, c.reload.subject_id
    assert_match "by domain", c.notes
    assert_nil Directory::Lookup.organization(name: "TP Nuclear Holdings"), "not yet: the match might be rejected"

    DataQuality::Stages::Verify.call(plugin: DummyPlugin.new, verifier: PublishEverything.new)
    approve_recommended
    assert_equal organizations(:terrapower).id, Directory::Lookup.organization(name: "TP Nuclear Holdings").id
  end

  test "an unpublished record is a human decision: never attached to, and the note says who and when" do
    organizations(:terrapower).unpublish!(by: "human:tosin")
    c = candidate("organization", { "name" => "TerraPower, Inc." })

    match!

    assert c.reload.status_needs_review?
    assert_match(/which was unpublished by human:tosin on \d{4}-\d{2}-\d{2}/, c.notes)
  end

  test "a record that was rejected is never attached to" do
    rejected = Directory::FactWriter.write(:organization, { name: "Imaginary Fission Co" }).id
    Organization.find(rejected).reject!(by: "agent:verifier/x")
    c = candidate("organization", { "name" => "Imaginary Fission Co" })

    match!

    assert c.reload.status_needs_review?
    assert_match "which was rejected", c.notes
  end

  test "name and domain pointing at different organizations goes to review" do
    c = candidate("organization", { "name" => "TerraPower", "domain" => "westinghousenuclear.com" })

    match!

    assert c.reload.status_needs_review?
    assert_match "name matches TerraPower but domain matches Westinghouse", c.notes
  end

  test "an operator similar to an existing parent goes to review" do
    Directory::FactWriter.write(:organization, { name: "Southern Company" })
    c = candidate("organization", { "name" => "Southern Nuclear Operating Co." })

    assert_no_difference "Organization.count" do
      match!
    end

    assert c.reload.status_needs_review?
    assert_match "Southern Company", c.notes
  end

  test "an organization listed on many rows is proposed once, then matched" do
    rows = 2.times.map { candidate("organization", { "name" => "Entergy Nuclear Operations, Inc." }) }

    run = match!

    assert_equal 1, Organization.where(name: "Entergy Nuclear Operations, Inc.").count
    assert_equal rows.map { |c| c.reload.subject_id }.uniq.size, 1
    assert_equal [ 1, 1 ], run.stats.values_at("proposed", "matched")
  end

  test "a new link and its quote are written together, or not at all" do
    # The quote write fails after the link was created: nothing may be left behind.
    directory = DataQuality::DirectoryClient.new
    directory.define_singleton_method(:write_pending) do |kind, attributes, **options|
      return DataQuality::DirectoryClient::WriteResult.new(ref: nil, errors: [ "disk full" ]) if attributes.keys == [ :id ]

      super(kind, attributes, **options)
    end
    link = candidate("facility_relationship", {
      "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => "Vogtle Electric Generating Plant" },
      "relationship_type" => "operates"
    })

    DataQuality::Stages::Match.call(plugin: DummyPlugin.new, directory:)

    assert link.reload.status_needs_review?
    assert_match "disk full", link.notes
    assert_not FacilityRelationship.exists?(relationship_type: "operates"), "the link was rolled back"
  end

  test "an operates link finds records proposed earlier in the same run" do
    candidate("organization", { "name" => "Entergy Nuclear Operations, Inc." })
    candidate("facility", facility_payload("Arkansas Nuclear 1", "05000313"))
    link = candidate("facility_relationship", {
      "organization" => { "name" => "Entergy Nuclear Operations, Inc." },
      "facility" => { "name" => "Arkansas Nuclear 1", "nrc_docket" => "05000313" },
      "relationship_type" => "operates"
    })

    run = match!

    link.reload
    assert link.status_matched?, link.notes
    record = FacilityRelationship.find(link.subject_id)
    assert record.operates?
    assert record.pending?
    assert_equal "Arkansas Nuclear 1", record.facility.name
    assert_equal [ link.quote ], record.evidence.pluck(:quote), "a new link is a proposal and carries its quote"
    assert_equal 3, run.stats["proposed"]
  end

  test "matching an existing link leaves its curated attributes and verification alone" do
    link = FacilityRelationship.create!(organization: organizations(:terrapower), facility: facilities(:vogtle),
      relationship_type: "owns", description: "Curated description", ownership_pct: 40)
    link.verify!(by: "human:tosin")
    c = candidate("facility_relationship", {
      "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => "Vogtle Electric Generating Plant" },
      "relationship_type" => "owns",
      "description" => "Candidate description",
      "ownership_pct" => 75
    })

    match!

    assert c.reload.status_matched?
    assert_equal link.id, c.subject_id
    link.reload
    assert_equal [ "Curated description", 40 ], link.slice(:description, :ownership_pct).values
    assert_equal "human:tosin", link.verified_by
    assert link.verified?
    assert_empty link.evidence, "an existing link gets the quote only when it's published"
  end

  test "matching an existing pending link defers candidate attributes until publication" do
    link = FacilityRelationship.create!(organization: organizations(:terrapower), facility: facilities(:vogtle),
      relationship_type: "owns", description: "Curated description", ownership_pct: 40)
    c = candidate("facility_relationship", {
      "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => "Vogtle Electric Generating Plant" },
      "relationship_type" => "owns",
      "description" => "Candidate description",
      "ownership_pct" => 75
    })

    match!

    assert c.reload.status_matched?
    assert_equal link.id, c.subject_id
    assert_equal [ "Curated description", 40 ], link.reload.slice(:description, :ownership_pct).values
  end

  test "a link to a record that needs review waits in review too" do
    vogtle_site!
    candidate("facility", facility_payload("Vogtle 1", "05000424"))
    link = candidate("facility_relationship", {
      "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => "Vogtle 1", "nrc_docket" => "05000424" },
      "relationship_type" => "operates"
    })

    match!

    assert link.reload.status_needs_review?
    assert_match "looks like a unit of Plant Vogtle", link.notes
  end

  test "an operator becomes an operates link on the unit under its site" do
    site = vogtle_site!
    candidate("organization", { "name" => "Example Nuclear Operating Co." })
    candidate("facility", facility_payload("Vogtle 3", "05200025"))
    link = candidate("facility_relationship", {
      "organization" => { "name" => "Example Nuclear Operating Co." },
      "facility" => { "name" => "Vogtle 3", "nrc_docket" => "05200025" },
      "relationship_type" => "operates"
    })

    match!

    record = FacilityRelationship.find(link.reload.subject_id)
    assert record.operates?
    assert_equal [ "Example Nuclear Operating Co.", site.id ], [ record.organization.name, record.facility.parent_id ]
    assert record.organization.pending?
  end

  test "a link with a missing end goes to review" do
    link = candidate("facility_relationship", { "organization" => { "name" => "TerraPower" }, "relationship_type" => "operates" })

    match!

    assert link.reload.status_needs_review?
    assert_equal "payload has no facility", link.notes
  end

  test "a payload the directory rejects goes to review with the reason" do
    c = candidate("organization", { "name" => "Brand New Co", "favourite_colour" => "blue" })

    run = match!

    assert c.reload.status_needs_review?
    assert_match "unknown attributes: favourite_colour", c.notes
    assert_equal 1, run.stats["write_errors"]
  end

  test "a company given only by website matches by that website's domain" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "website" => "https://www.terrapower.com/about" })

    run = match!

    assert_equal organizations(:terrapower).id, c.reload.subject_id
    assert_match "by domain", c.notes
    assert_equal 1, run.stats["matched"]
  end

  test "a match run refuses to overlap another match run" do
    # A separate Postgres session plays the other run (tests share one pooled connection).
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password],
      dbname: config[:database])
    other.exec("SELECT pg_advisory_lock(#{Zlib.crc32('data_quality:match')})")

    error = assert_raises(RuntimeError) { match! }
    assert_equal "Another match run is already in progress", error.message
  ensure
    other&.close
  end

  test "an explicit nil domain prevents website matching" do
    c = candidate("organization", { "name" => "Lumen Fission", "domain" => nil,
      "website" => "https://www.terrapower.com" })

    match!

    record = Organization.find(c.reload.subject_id)
    assert_not_equal organizations(:terrapower).id, record.id
    assert_nil record.domain
    assert_equal "https://www.terrapower.com", record.website
  end

  test "rerunning leaves candidates that already moved on alone" do
    candidate("facility", facility_payload("Arkansas Nuclear 1", "05000313"))
    match!

    assert_no_difference [ "Facility.count", "Evidence.count" ] do
      assert_equal 0, match!.stats["candidates"]
    end
  end
end
