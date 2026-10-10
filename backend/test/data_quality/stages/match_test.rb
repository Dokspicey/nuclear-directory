require "test_helper"
require_relative "../support/dummy_plugin"

# Match against the real directory with NRC-style names, since what matters
# is how real names and dockets resolve.
class DataQuality::Stages::MatchTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(url: "https://www.nrc.gov/test/match-stage-sample.html",
      source_kind: "dummy", crawl_status: "ok")
  end

  def candidate(kind, payload, quote: "row from the NRC list")
    Candidate.create!(source: @source, kind: kind, payload: payload, quote: quote)
  end

  def match! = DataQuality::Stages::Match.call(plugin: DummyPlugin.new)

  def facility_payload(name, docket) = { "name" => name, "nrc_docket" => docket, "facility_type" => "power_reactor" }

  test "a facility matched by NRC docket is attached, with the quote as evidence" do
    site = Facility.create!(name: "Braidwood Station", nrc_docket: "05000456")
    c = candidate("facility", facility_payload("Braidwood 1", "05000456"), quote: "Braidwood 1 05000456")

    run = match!

    c.reload
    assert c.status_matched?
    assert_equal [ "Facility", site.id ], [ c.subject_type, c.subject_id ]
    assert_match "by NRC docket", c.notes
    assert_equal "Braidwood Station", site.reload.name, "matching doesn't overwrite the record"
    evidence = site.evidence.sole
    assert_equal [ "crawler", "Braidwood 1 05000456", run.id ], [ evidence.found_by, evidence.quote, evidence.crawl_run_id ]
    assert_equal 1, run.stats["matched"]
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

  test "a unit similar to a site without a docket goes to review, never merged" do
    c = candidate("facility", facility_payload("Vogtle 3", "05200025"))

    assert_no_difference "Facility.count" do
      match!
    end

    assert c.reload.status_needs_review?
    assert_nil c.subject_id
    assert_match "Vogtle Electric Generating Plant", c.notes
  end

  test "spacing differences still count as similar" do
    Facility.create!(name: "La Salle County Station")
    c = candidate("facility", facility_payload("LaSalle 1", "05000373"))

    match!

    assert c.reload.status_needs_review?
    assert_match "La Salle County Station", c.notes
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

  test "an organization matched by domain under another name gains that name as an alias" do
    c = candidate("organization", { "name" => "TP Nuclear Holdings", "domain" => "terrapower.com" })

    match!

    assert_equal organizations(:terrapower).id, c.reload.subject_id
    assert_match "by domain", c.notes
    assert_equal organizations(:terrapower).id, Directory::Lookup.organization(name: "TP Nuclear Holdings").id
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
    assert_equal 3, run.stats["proposed"]
  end

  test "a link to a record that needs review waits in review too" do
    candidate("facility", facility_payload("Vogtle 3", "05200025"))
    link = candidate("facility_relationship", {
      "organization" => { "name" => "TerraPower" },
      "facility" => { "name" => "Vogtle 3", "nrc_docket" => "05200025" },
      "relationship_type" => "operates"
    })

    match!

    assert link.reload.status_needs_review?
    assert_match "facility: no exact match", link.notes
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

  test "rerunning leaves candidates that already moved on alone" do
    candidate("facility", facility_payload("Arkansas Nuclear 1", "05000313"))
    match!

    assert_no_difference [ "Facility.count", "Evidence.count" ] do
      assert_equal 0, match!.stats["candidates"]
    end
  end
end
