require "test_helper"

# What the admin's lifecycle overview reads (#166): what's public, and what
# was taken out (rejected, unpublished, merged away).
class Directory::ExitsTest < ActiveSupport::TestCase
  BY = "human:tosin"
  VERIFIED = { verification_status: "verified", verified_by: BY }.freeze

  test "a merge records where the record went, for companies and plants" do
    urenco = Organization.create!(name: "Urenco", **VERIFIED)
    usa = Organization.create!(name: "Urenco USA", **VERIFIED)
    plant = Facility.create!(name: "Plant Vogtle", **VERIFIED)
    eia = Facility.create!(name: "Vogtle", **VERIFIED)

    assert Directory::FactWriter.merge_organization(from_id: usa.id, into_id: urenco.id, by: BY).ok?
    assert Directory::FactWriter.merge_facility(from_id: eia.id, into_id: plant.id, by: BY).ok?

    assert_equal({ "type" => "Organization", "id" => urenco.id }, usa.verification_events.order(:id).last.context["merged_into"])
    assert_equal({ "type" => "Facility", "id" => plant.id }, eia.verification_events.order(:id).last.context["merged_into"])
  end

  test "exits lists what was rejected or unpublished since a time, newest first, with merges' targets" do
    urenco = Organization.create!(name: "Urenco", **VERIFIED)
    usa = Organization.create!(name: "Urenco USA", **VERIFIED)
    gone = Organization.create!(name: "Gone Co", **VERIFIED)
    travel_to(2.days.ago) { Organization.create!(name: "Old Exit", **VERIFIED).reject!(by: BY, reason: "too old to list") }
    gone.reject!(by: BY, reason: "Not a real company")
    Directory::FactWriter.merge_organization(from_id: usa.id, into_id: urenco.id, by: BY)

    exits = Directory::Lookup.exits(since: 1.day.ago)

    assert_equal [ [ "Urenco USA", "unpublished", { "type" => "Organization", "id" => urenco.id } ], [ "Gone Co", "rejected", nil ] ],
      exits.map { |exit| [ exit.name, exit.to_status, exit.merged_into ] }
    assert_equal [ BY, "Not a real company" ], [ exits.last.by, exits.last.reason ]
    assert_equal 1, Directory::Lookup.exits(since: 1.day.ago, limit: 1).size
  end

  test "published_counts counts what public pages show, per type" do
    before = Directory::Lookup.published_counts
    Organization.create!(name: "Shown Co", **VERIFIED)
    Organization.create!(name: "Pending Co")

    counts = Directory::Lookup.published_counts

    assert_equal Directory::Lookup::FACT_TYPES, counts.keys
    assert_equal before["Organization"] + 1, counts["Organization"]
  end
end
