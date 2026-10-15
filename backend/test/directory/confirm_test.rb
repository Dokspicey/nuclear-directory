require "test_helper"

# Directory::FactWriter.confirm: does a source still say what a fact records (#240)?
class Directory::ConfirmTest < ActiveSupport::TestCase
  BY = "human:tosin"

  setup do
    @source = sources(:press_release)
    @unit = Facility.create!(name: "Hope Creek 1", nrc_docket: "05000354", state: "NJ", capacity_mw: "1227.40",
      verification_status: "verified", verified_by: BY)
    @unit.aliases.create!(alias: "Hope Creek Generating Station")
    @evidence = Evidence.create!(subject: @unit, source: @source, quote: "Hope Creek 1", found_by: "crawler")
  end

  def confirm(attributes, kind: :facility, source_id: @source.id, **)
    Directory::FactWriter.confirm(kind, { id: @unit.id }.merge(attributes), source_id:, rows_sha256: "rows-1", **)
  end

  test "the same values, compared as stored, confirm and stamp only the evidence" do
    at = Time.zone.parse("2026-10-14 03:02")
    result = nil
    assert_no_difference [ "VerificationEvent.count", -> { @unit.reload.updated_at } ] do
      result = confirm({ name: "Hope Creek Generating Station", nrc_docket: " 05000354 ", capacity_mw: "1227.4000000000001" }, at:)
    end

    assert result.confirmed?, result.inspect
    assert_equal [ at, "rows-1" ], [ @evidence.reload.last_confirmed_at, @evidence.confirmed_sha256 ]
  end

  test "a different value, or a name the fact isn't known by, is a difference" do
    assert_equal({ "state" => [ "NJ", "DE" ] }, confirm({ state: "DE" }).differences)
    assert_equal({ "aliases" => [ nil, "Hope Creek Unit One" ] }, confirm({ name: "Hope Creek Unit One" }).differences)
    assert_equal({ "capacity_mw" => [ "1227.4", "1230" ] }, confirm({ capacity_mw: "1230" }).differences)
    assert_nil @evidence.reload.last_confirmed_at
  end

  test "a value the fact doesn't have yet is a difference; one the source doesn't state isn't" do
    assert_equal :different, confirm({ city: "Hancocks Bridge" }).outcome
    assert confirm({ city: nil }).confirmed?
  end

  test "the same values with no evidence from this source aren't confirmed: approving would add the source" do
    assert_equal :unsourced, confirm({ state: "NJ" }, source_id: sources(:nrc).id).outcome
  end

  test "a company is known by any of its aliases" do
    company = Organization.create!(name: "PSEG Nuclear", verification_status: "verified", verified_by: BY)
    company.aliases.create!(alias: "PSEG Nuclear LLC")
    Evidence.create!(subject: company, source: @source, quote: "PSEG Nuclear LLC", found_by: "crawler")

    result = Directory::FactWriter.confirm(:organization, { id: company.id, name: "PSEG Nuclear, LLC" }, source_id: @source.id)

    assert result.confirmed?, result.inspect
  end

  test "a missing fact or an unknown attribute isn't confirmed" do
    assert_equal :missing, Directory::FactWriter.confirm(:facility, { id: 0 }, source_id: @source.id).outcome
    assert_match "unknown attributes: favourite", confirm({ favourite: "blue" }).errors.join
  end

  test "reconfirm_source stamps all of a source's evidence" do
    other = Evidence.create!(subject: @unit, source: sources(:nrc), quote: "Hope Creek", found_by: "crawler")
    at = Time.zone.parse("2026-10-14 03:02")

    assert_equal 1, Directory::FactWriter.reconfirm_source(source_id: @source.id, rows_sha256: "rows-2", at:)

    assert_equal [ at, "rows-2" ], [ @evidence.reload.last_confirmed_at, @evidence.confirmed_sha256 ]
    assert_nil other.reload.last_confirmed_at
  end
end
