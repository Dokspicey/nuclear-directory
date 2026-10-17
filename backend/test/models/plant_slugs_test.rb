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
    unit.update_column(:parent_id, site.id) # grouped before the guard existed
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

  test "an NRC unit grouped under its new site hands the site its plain slug" do
    unit = cite!(plant("Waterford 3", status: "operating")) # NRC first, no site yet
    site = cite!(plant("Waterford 3", facility_type: "power_reactor"))
    assert_equal "waterford-3-2", site.slug

    unit.update!(parent: site) # grouped, as DirectoryClient#group_unit does

    assert_equal "waterford-3", site.reload.slug
    assert_equal "waterford-3-unit", unit.reload.slug
    get plant_path(slug: "waterford-3-2")
    assert_redirected_to plant_path(slug: "waterford-3")
  end

  test "another plant's unit keeps its slug, and the new site takes the next free one" do
    other = plant("Placeholder Site")
    unit = plant("Waterford 3", parent: other)
    site = plant("Waterford 3")

    assert_equal "waterford-3-2", site.slug
    assert_equal "waterford-3", unit.reload.slug
    assert_empty Facility.give_sites_their_plain_slugs!
  end

  test "checking a new site for errors changes nothing" do
    unit = plant("Callaway")
    site = Facility.new(name: "Callaway", verification_status: "verified", verified_by: "human:test")

    assert site.valid?
    assert_equal "callaway", unit.reload.slug
    assert_equal 0, FormerSlug.count
  end

  test "the unit's row keeps its old anchor too, so old links reach it" do
    clashed("Palisades")
    Facility.give_sites_their_plain_slugs!
    get plant_path(slug: "palisades")

    assert_select "tr#unit-palisades-unit"
    assert_select "tr#unit-palisades-unit #unit-palisades", 1
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
