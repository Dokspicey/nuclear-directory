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

  def merge(task, from, into, **env)
    env.each { |key, value| ENV[key.to_s] = value }
    Rake::Task["directory:#{task}"].execute(Rake::TaskArguments.new(%i[from into], [ from.to_s, into.to_s ]))
  ensure
    env.each_key { |key| ENV.delete(key.to_s) }
  end

  test "merging a duplicate site is a dry run until APPLY=1, then audited as the named person (#229)" do
    vogtle = Facility.create!(name: "Plant Vogtle", verification_status: "verified", verified_by: "human:tosin")
    eia = Facility.create!(name: "Vogtle", eia_plant_id: "649", verification_status: "verified", verified_by: "human:tosin")

    assert_output(/Would merge Vogtle \(##{eia.id}\) into Plant Vogtle \(##{vogtle.id}\): .*Moved: 1 aliases, eia_plant_id\nDry run/) do
      merge(:merge_facility, eia.id, vogtle.id, BY: "human:tosin")
    end
    assert_equal [ "verified", nil ], [ eia.reload.verification_status, vogtle.reload.eia_plant_id ]

    assert_output(/\AMerged Vogtle/) { merge(:merge_facility, eia.id, vogtle.id, BY: "human:tosin", APPLY: "1") }
    assert eia.reload.unpublished?
    assert_equal [ "649", "human:tosin" ], [ vogtle.reload.eia_plant_id, eia.verified_by ]

    assert_raises(SystemExit) { capture_io { merge(:merge_facility, eia.id, vogtle.id, BY: "human:tosin", APPLY: "1") } }
    assert_raises(SystemExit) { capture_io { merge(:merge_facility, eia.id, vogtle.id, BY: "human:") } }
  end

  test "merging a duplicate company works the same way" do
    talen = Organization.create!(name: "Talen Energy", verification_status: "verified", verified_by: "human:tosin")
    eia = Organization.create!(name: "TalenEnergy", verification_status: "verified", verified_by: "human:tosin")

    assert_output(/Would merge TalenEnergy/) { merge(:merge_organization, eia.id, talen.id, BY: "human:tosin") }
    assert eia.reload.verified?
    assert_output(/\AMerged TalenEnergy/) { merge(:merge_organization, eia.id, talen.id, BY: "human:tosin", APPLY: "1") }
    assert eia.reload.unpublished?
  end
end
