require "test_helper"
require_relative "../support/dummy_plugin"

# Link claims that waited for a company the directory didn't have are
# matched again once it has an exact one (Data Quality, 18 Oct); and a
# claim never replaces what another page of its source says on a link.
class DataQuality::Stages::RematchTest < ActiveSupport::TestCase
  FUNDER = "U.S. Department of Energy"

  setup do
    @source = Source.create!(url: "https://api.usaspending.gov/test/recipient/nog", source_kind: "dummy", crawl_status: "ok",
      title: "USAspending.gov: awards to BWXT NOG TECHNOLOGIES, INC.")
    @doe = organization(FUNDER)
  end

  def organization(name, aliases: [])
    result = Directory::FactWriter.write(:organization, { name:, aliases: })
    assert result.ok?, result.errors.to_sentence
    Organization.find(result.id)
  end

  def award(to, description: "1 award from the U.S. Department of Energy totaling $2.6 million, 2023: 89243220CNE000017.", source: @source)
    Candidate.create!(source:, kind: "relationship", quote: "award row #{Candidate.count}", payload: {
      "relationship_type" => "funds", "from_organization" => { "name" => FUNDER }, "to_organization" => { "name" => to },
      "description" => description
    })
  end

  def match! = DataQuality::Stages::Match.call(plugin: DummyPlugin.new)

  test "a claim that waited for its company is matched once the company exists, and nothing is approved" do
    claim = award("GENERAL ATOMICS")
    match!
    assert claim.reload.status_needs_review?
    assert_match(/\Ato_organization[: ]/, claim.notes)

    organization("General Atomics")
    run = match!

    claim.reload
    assert claim.status_matched?, claim.notes
    assert_equal 1, run.stats["rematched"]
    link = Relationship.find(claim.subject_id)
    assert link.pending?, "a new link waits for verify and a person"
  end

  test "a claim with two ends in question stays as it is while one is still unanswered" do
    claim = Candidate.create!(source: @source, kind: "relationship", quote: "award row", payload: {
      "relationship_type" => "funds", "from_organization" => { "name" => "Office of Imaginary Science" },
      "to_organization" => { "name" => "GENERAL ATOMICS" }
    })
    match!
    notes = claim.reload.notes
    assert claim.status_needs_review?

    organization("General Atomics")
    run = match!

    assert claim.reload.status_needs_review?
    assert_equal notes, claim.notes
    assert_nil run.stats["rematched"]
  end

  test "only an exact name or alias settles it, never a similar name; review items of other kinds aren't re-tried" do
    claim = award("GENERAL ATOMICS AERONAUTICAL SYSTEMS")
    match!
    organization("General Atomics")
    match!
    assert claim.reload.status_needs_review?, "a similar name is still a question"

    dropped = award("GENERAL ATOMICS")
    dropped.update_columns(status: "needs_review", review_origin: "dropped", notes: "to_organization: no exact match")
    match!
    assert dropped.reload.status_needs_review?
  end

  # BWXT NOG's single award, found on its own recipient page, mustn't
  # replace the two awards another recipient's page put on BWXT's link.
  test "BWXT NOG can't replace a link that cites another page of the same source" do
    bwxt = organization("BWX Technologies")
    other = Source.create!(url: "https://api.usaspending.gov/test/recipient/bwxt", source_kind: "dummy", crawl_status: "ok",
      title: "USAspending.gov: awards to BWXT")
    two = "2 awards from the U.S. Department of Energy totaling $102.6 million (2021–2023): 89233123FNA400535 and DENE0008744."
    written = Directory::FactWriter.write(:relationship, { from_organization_id: @doe.id, to_organization_id: bwxt.id, relationship_type: "funds",
      description: two }, evidence: [ { source_id: other.id, quote: "BWXT rows", found_by: "crawler" } ],
      verification: { status: "verified", by: "human:tosin" })
    assert written.ok?, written.errors.to_sentence
    claim = award("BWXT NOG TECHNOLOGIES, INC.")
    match!
    assert claim.reload.status_needs_review?

    bwxt.aliases.create!(alias: "BWXT NOG Technologies, Inc.")
    match!

    claim.reload
    assert claim.status_needs_review?
    assert_nil claim.subject_id, "not attached to the link, so it can't be recommended or approved onto it"
    assert_match "already cites USAspending.gov: awards to BWXT, another page of this source", claim.notes
    assert_match "(#390)", claim.notes
    assert_equal two, Relationship.find(written.id).description

    run = match!
    assert_nil run.stats["rematched"], "not re-tried every night"
  end

  test "a page that restates a link it already cites isn't held" do
    company = organization("General Atomics")
    text = "1 award from the U.S. Department of Energy totaling $2.6 million, 2023: 89243220CNE000017."
    written = Directory::FactWriter.write(:relationship, { from_organization_id: @doe.id, to_organization_id: company.id, relationship_type: "funds",
      description: text }, evidence: [ { source_id: @source.id, quote: "rows", found_by: "crawler" } ])
    other = Source.create!(url: "https://api.usaspending.gov/test/recipient/ga2", source_kind: "dummy", crawl_status: "ok")
    Evidence.create!(subject: Relationship.find(written.id), source: other, quote: "the same rows", found_by: "crawler")

    claim = award("General Atomics", description: text)
    match!

    assert claim.reload.status_matched?, "another page cites it too, but this claim changes nothing"
  end
end
