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

  PUBLISHED = { verification_status: "verified", verified_by: "human:tosin" }.freeze

  def company(name) = Organization.create!(name:, **PUBLISHED)
  def plant(name, **attributes) = Facility.create!(name:, **PUBLISHED, **attributes)

  test "published operates links only EIA backs are listed, and unpublished on APPLY where NRC names another operator (#227)" do
    eia = Source.create!(url: "https://www.eia.gov/electricity/data/eia860m/xls/july_generator2026.xlsx", source_kind: "eia_generators")
    nrc = Source.create!(url: "https://www.nrc.gov/test/operators", source_kind: "nrc_reactor_list")
    hatch = plant("Edwin I Hatch", eia_plant_id: "6051")
    wrong = operates(company("Georgia Power"), hatch, eia)
    operates(company("Southern Nuclear"), plant("Hatch 1", parent: hatch, nrc_docket: "05000321"), nrc)
    columbia = plant("Columbia", eia_plant_id: "371")
    alone = operates(company("Energy Northwest"), columbia, eia)
    operates(company("Bonneville Power"), columbia, eia) # another EIA-only operator isn't NRC's word
    both = operates(company("Entergy"), plant("Arkansas Nuclear One", eia_plant_id: "8055"), eia, nrc)
    salem = plant("Salem", eia_plant_id: "2410")
    current = operates(company("PSEG Nuclear"), salem, eia)
    operates(company("Public Service Electric & Gas"), salem, nrc).update_columns(ended_on: Date.new(2000, 1, 1))
    # Hidden: its company was taken down, so the task leaves it be.
    hidden = operates(gone = company("Gone Co"), hatch, eia)
    gone.unpublish!(by: "human:tosin", reason: "Not a real company")

    assert_output(/Georgia Power operates Edwin I Hatch -> would unpublish \(Southern Nuclear\)\n/) { retire_eia_operators }
    assert_output(/Energy Northwest operates Columbia \(no published NRC operator; check by hand\)/) { retire_eia_operators(APPLY: "0") }
    assert wrong.reload.verified?, "a dry run, and APPLY=0, change nothing"
    assert_raises(SystemExit) { capture_io { retire_eia_operators(APPLY: "1") } }
    assert_raises(SystemExit) { capture_io { retire_eia_operators(APPLY: "1", BY: "human:") } }

    assert_output(/Georgia Power operates Edwin I Hatch -> unpublished/) { retire_eia_operators(APPLY: "1", BY: "human:tosin") }
    assert wrong.reload.unpublished?
    assert_equal "human:tosin", wrong.verified_by
    assert alone.reload.verified?, "no NRC operator to go by"
    assert both.reload.verified?, "NRC backs it too"
    assert hidden.reload.verified?, "not published, so not this task's"
    assert current.reload.verified?, "NRC's only operator there ended in 2000"
  end

  test "a link named in SKIP is listed but kept, even with APPLY (Perry, #237)" do
    eia = Source.create!(url: "https://www.eia.gov/electricity/data/eia860m/xls/july_generator2026.xlsx", source_kind: "eia_generators")
    nrc = Source.create!(url: "https://www.nrc.gov/test/operators", source_kind: "nrc_reactor_list")
    perry = plant("Perry", eia_plant_id: "6020")
    kept = operates(company("Energy Harbor Nuclear Corp."), perry, eia)
    operates(company("FirstEnergy Nuclear Operating Co."), plant("Perry 1", parent: perry, nrc_docket: "05000440"), nrc)

    assert_output(/Energy Harbor Nuclear Corp. operates Perry -> kept \(SKIP; FirstEnergy Nuclear Operating Co.\)/) do
      retire_eia_operators(APPLY: "1", BY: "human:tosin", SKIP: " #{kept.id} ")
    end
    assert kept.reload.verified?
    assert_raises(SystemExit) { capture_io { retire_eia_operators(SKIP: "Perry") } }
  end
end
