require "test_helper"
require "rake"

class DirectoryRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("directory:backfill_former_slugs")
  end

  def backfill = Rake::Task["directory:backfill_former_slugs"].execute

  test "the backfill keeps slugs renamed or merged before #143, and is safe to rerun" do
    atr = Facility.create!(name: "Advanced Test Reactor", slug: "advanced-test-reactor")
    VerificationEvent.create!(subject: atr, from_status: "verified", to_status: "verified", by: "human:tosin",
      changed_values: { "slug" => [ "advanced-test-reactor-atr", "advanced-test-reactor" ] })
    urenco = Organization.create!(name: "Urenco")
    usa = Organization.create!(name: "Urenco USA")
    usa.unpublish!(by: "human:tosin", reason: "One company per brand. Merged into Urenco (##{urenco.id}). Moved: 3 aliases")
    FormerSlug.delete_all

    assert_output(/Facility advanced-test-reactor-atr -> advanced-test-reactor\nOrganization urenco-usa -> urenco/) { backfill }
    assert_equal atr, Facility.find_by_former_slug("advanced-test-reactor-atr")
    assert_equal urenco, Organization.find_by_former_slug("urenco-usa")

    assert_output("Nothing to backfill.\n") { backfill }
  end

  def retire_eia_operators(**env)
    env.each { |key, value| ENV[key.to_s] = value }
    Rake::Task["directory:retire_eia_operators"].execute
  ensure
    env.each_key { |key| ENV.delete(key.to_s) }
  end

  def operates(company, plant, *sources)
    FacilityRelationship.create!(organization: company, facility: plant, relationship_type: "operates").tap do |link|
      sources.each { |source| link.evidence.create!(source:, found_by: "crawler", quote: "row") }
      link.verify!(by: "human:tosin")
    end
  end

  test "published operates links only EIA backs are listed, and unpublished on APPLY where NRC names another operator (#227)" do
    eia = Source.create!(url: "https://www.eia.gov/electricity/data/eia860m/xls/july_generator2026.xlsx", source_kind: "eia_generators")
    nrc = Source.create!(url: "https://www.nrc.gov/test/operators", source_kind: "nrc_reactors")
    hatch = Facility.create!(name: "Edwin I Hatch", eia_plant_id: "6051")
    hatch_1 = Facility.create!(name: "Hatch 1", parent: hatch, nrc_docket: "05000321")
    georgia = Organization.create!(name: "Georgia Power")
    wrong = operates(georgia, hatch, eia)
    operates(Organization.create!(name: "Southern Nuclear"), hatch_1, nrc)
    alone = operates(Organization.create!(name: "Energy Northwest"), Facility.create!(name: "Columbia", eia_plant_id: "371"), eia)
    both = operates(Organization.create!(name: "Entergy"), Facility.create!(name: "Arkansas Nuclear One", eia_plant_id: "8055"), eia, nrc)

    assert_output(/Georgia Power operates Edwin I Hatch -> would unpublish \(Southern Nuclear\)\n.*Energy Northwest operates Columbia \(no other operator; check by hand\)\n\z/) do
      retire_eia_operators
    end
    assert wrong.reload.verified?, "a dry run changes nothing"
    assert_raises(SystemExit) { capture_io { retire_eia_operators(APPLY: "1") } }

    assert_output(/Georgia Power operates Edwin I Hatch -> unpublished/) { retire_eia_operators(APPLY: "1", BY: "human:tosin") }
    assert wrong.reload.unpublished?
    assert_equal "human:tosin", wrong.verified_by
    assert alone.reload.verified?, "no other operator to go by"
    assert both.reload.verified?, "NRC backs it too"
  end
end
