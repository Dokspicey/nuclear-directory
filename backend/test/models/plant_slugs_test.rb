require "test_helper"
require_relative "../support/directory_builders"

# A site owns the plain slug of its name, never its own unit (#333).
class PlantSlugsTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  # As on production before the fix: the NRC unit came first and took the
  # plain slug, so the EIA site got "-2".
  def clashed(name)
    unit = Facility.create!(name:, verification_status: "verified", verified_by: "human:test", status: "operating")
    site = cite!(Facility.create!(name:, slug: "#{name.parameterize}-2", verification_status: "verified", verified_by: "human:test",
      facility_type: "power_reactor", status: "operating"))
    unit.update!(parent: site)
    cite!(unit)
    [ site, unit ]
  end

  test "a site at -2 because of its own unit takes its plain slug, and every old address 301s" do
    site, unit = clashed("Palisades")
    other = cite!(plant("Kemmerer Unit 1")) # numbered by its own name: left alone
    other_site, = clashed("Callaway")

    moved = Facility.give_sites_their_plain_slugs!

    assert_equal [ [ "palisades-2", "palisades", "palisades", "palisades-unit" ], [ "callaway-2", "callaway", "callaway", "callaway-unit" ] ],
      moved.map { |s, old, u, unit_old| [ old, s.slug, unit_old, u.slug ] }
    assert_equal "palisades", site.reload.slug
    assert_equal "palisades-unit", unit.reload.slug
    assert_equal "callaway", other_site.reload.slug
    assert_equal "kemmerer-unit-1", other.reload.slug

    get plant_path(slug: "palisades")
    assert_response :success
    assert_select "h1", "Palisades"

    get plant_path(slug: "palisades-2")
    assert_redirected_to plant_path(slug: "palisades")
    assert_response :moved_permanently

    get plant_path(slug: "palisades-unit")
    assert_redirected_to plant_path(slug: "palisades", anchor: "unit-palisades-unit")
  end

  test "running it again changes nothing" do
    clashed("Davis-Besse")
    Facility.give_sites_their_plain_slugs!

    assert_empty Facility.give_sites_their_plain_slugs!
    assert_equal "davis-besse", Facility.find_by!(parent_id: nil, name: "Davis-Besse").slug
  end

  test "a -2 site whose plain slug isn't held by its own unit is left alone" do
    plant("Hermes", verified: false) # another record holds the plain slug
    hermes = plant("Hermes")
    assert_equal "hermes-2", hermes.slug

    assert_empty Facility.give_sites_their_plain_slugs!
    assert_equal "hermes-2", hermes.reload.slug
  end

  test "a new site takes its plain slug from a unit that holds it" do
    unit = plant("Waterford 3", parent: plant("Placeholder Site"))
    site = plant("Waterford 3")

    assert_equal "waterford-3", site.slug
    assert_equal "waterford-3-unit", unit.reload.slug
    assert_equal "waterford-3-2", plant("Waterford 3").slug, "another site's slug is never taken"
  end

  # The deploy step's migration for production's four pairs (db/data).
  def run_migration
    migrations = DeployData::Migrations.new
    pending = migrations.pending.find { |migration| migration.name == "sites_take_their_plain_slugs" }
    migrations.run(pending, reason: "test", commit: "abc1234")
  end

  test "the data migration moves the four production pairs once, then has nothing to do" do
    %w[Callaway Davis-Besse Palisades].each { |name| clashed(name) }
    clashed("Waterford 3")

    ran = nil
    assert_output(/Palisades: \/plants\/palisades-2 -> \/plants\/palisades/) { ran = run_migration }
    assert_equal 4, ran.output.size
    assert_equal %w[callaway davis-besse palisades waterford-3],
      Facility.where(parent_id: nil, name: [ "Callaway", "Davis-Besse", "Palisades", "Waterford 3" ]).order(:slug).pluck(:slug)
    assert DataMigration.exists?(name: "sites_take_their_plain_slugs", by: "human:tosin")
    assert_empty DeployData::Migrations.new.pending.select { |migration| migration.name == "sites_take_their_plain_slugs" }, "runs once"
  end

  test "the data migration stops, changing nothing, if another site would move" do
    clashed("Palisades")
    clashed("Surprise Station")

    assert_raises(RuntimeError) { capture_io { run_migration } }
    assert_equal "palisades-2", Facility.find_by!(parent_id: nil, name: "Palisades").slug
  end
end
