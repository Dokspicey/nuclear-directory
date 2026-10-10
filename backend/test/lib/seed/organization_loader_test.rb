require "test_helper"

class Seed::OrganizationLoaderTest < ActiveSupport::TestCase
  setup do
    Role.create!(key: "fuel", name: "Fuel")
    Role.create!(key: "enrichment", name: "Enrichment", parent: Role.find_by!(key: "fuel"))
    @dir = Dir.mktmpdir
  end

  teardown { FileUtils.remove_entry(@dir) }

  # Kept out of @dir, which holds only organization files.
  def facilities_file = @facilities_file ||= File.join(Dir.mktmpdir, "facilities.yml")

  def write_file(slug, doc)
    File.write(File.join(@dir, "#{slug}.yml"), doc.deep_stringify_keys.to_yaml)
  end

  def org(name, website:, **extra)
    { name: name, aliases: [], website: website, hq: nil, country_code: "US", status: "active",
      roles: [], technologies: [], relationships: [], facilities: [], notes: "" }.merge(extra)
  end

  def item(**extra)
    { source_url: "https://example.com/news", quote: "A quote.", confidence: 0.8, published: "2026-01-02" }.merge(extra)
  end

  test "tags a role and its sub-role, and records the source" do
    write_file("acme-fuel", org("Acme Fuel, Inc.", website: "https://acmefuel.com",
      roles: [ item(key: "fuel", subtype: "enrichment") ]))

    loader = Seed::OrganizationLoader.new(@dir).load!

    acme = Organization.find_by!(slug: "acme-fuel")
    assert_equal %w[enrichment fuel], acme.roles.pluck(:key).sort
    assert_equal({ created: 2, updated: 0 }, loader.results[:organization_role])
    assert_equal Date.new(2026, 1, 2), Source.find_by!(url: "https://example.com/news").published_on
  end

  test "organizations sharing a website get no matching domain" do
    write_file("parent", org("Parent Co", website: "https://shared.com"))
    write_file("child", org("Child Co", website: "https://www.shared.com/child"))
    write_file("solo", org("Solo Co", website: "https://solo.com"))

    Seed::OrganizationLoader.new(@dir).load!

    assert_equal [ nil, nil ], Organization.where(slug: %w[parent child]).pluck(:domain)
    assert_equal "https://shared.com", Organization.find_by!(slug: "parent").website
    assert_equal "solo.com", Organization.find_by!(slug: "solo").domain
  end

  test "a later facility entry with blank details doesn't erase ones already stored" do
    write_file("a-owner", org("A Owner", website: "https://a-owner.com",
      facilities: [ item(name: "Plant Vogtle", type: "owns", city: "Waynesboro", state: "GA") ]))
    write_file("b-operator", org("B Operator", website: "https://b-operator.com",
      facilities: [ item(name: "Plant Vogtle", type: "operates", city: "", state: "  ") ]))

    Seed::OrganizationLoader.new(@dir).load!

    vogtle = Facility.find_by!(name: "Plant Vogtle")
    assert_equal [ "Waynesboro", "GA" ], [ vogtle.city, vogtle.state ]
    assert_equal 2, vogtle.facility_relationships.count
  end

  test "loads brand names, descriptions, an HQ in two entries, and ownership stakes" do
    write_file("acme-fuel", org("Acme Fuel, Inc.", website: "https://acmefuel.com",
      legal_name: "Acme Fuel, Inc.",
      description: { "text" => "Makes fuel.", "source_url" => "https://example.com/about", "quote" => "We make fuel." },
      hq: [ { "state" => "TN" }, item(city: "Oak Ridge", source_url: "https://example.com/hq", quote: "Based in Oak Ridge.") ],
      facilities: [ item(name: "Acme Plant", type: "owns", ownership_pct: 40.0) ]))

    Seed::OrganizationLoader.new(@dir).load!

    acme = Organization.find_by!(slug: "acme-fuel")
    assert_equal [ "Acme Fuel, Inc.", "Makes fuel.", "Oak Ridge", "TN" ], [ acme.legal_name, acme.description, acme.hq_city, acme.hq_state ]
    assert_equal 2, acme.evidence.count, "the description and the sourced HQ entry"
    assert_equal 40, acme.facility_relationships.sole.ownership_pct
  end

  test "facilities.yml details are written field by field, each with its own quote" do
    write_file("acme-fuel", org("Acme Fuel", website: "https://acmefuel.com", facilities: [ item(name: "Acme Plant", type: "owns") ]))
    File.write(facilities_file, { "facilities" => [ {
      "name" => "Acme Plant",
      "status" => { "value" => "operating", "source_url" => "https://example.com/status", "quote" => "Running since 2020." },
      "city" => { "value" => nil, "source_url" => "https://example.com/where", "quote" => "Near Sometown." }
    } ] }.to_yaml)

    Seed::OrganizationLoader.new(@dir, facilities: facilities_file).load!

    plant = Facility.find_by!(name: "Acme Plant")
    assert plant.operating?
    assert_nil plant.city, "a blank value isn't written"
    assert_includes plant.evidence.pluck(:quote), "Running since 2020."
  end

  test "a facilities.yml plant must be in an organization file" do
    write_file("acme-fuel", org("Acme Fuel", website: "https://acmefuel.com"))
    File.write(facilities_file, { "facilities" => [ { "name" => "Nowhere Plant" } ] }.to_yaml)

    error = assert_raises(Seed::OrganizationLoader::Error) do
      Seed::OrganizationLoader.new(@dir, facilities: facilities_file).load!
    end
    assert_match "Nowhere Plant", error.message
  end

  test "a seed file citing a non-web URL fails the load and names it" do
    write_file("acme-fuel", org("Acme Fuel", website: "https://acmefuel.com",
      roles: [ item(key: "fuel", source_url: "javascript:alert(1)") ]))

    error = assert_raises(Seed::OrganizationLoader::Error) { Seed::OrganizationLoader.new(@dir).load! }
    assert_match 'source "javascript:alert(1)": Url must be an absolute http or https address', error.message
    assert_nil Organization.find_by(slug: "acme-fuel"), "nothing is written"
  end

  test "fails as a whole when any fact can't be written" do
    write_file("acme-fuel", org("Acme Fuel", website: "https://acmefuel.com",
      relationships: [ item(type: "supplies", to: "Nobody At All", description: "x") ]))

    error = assert_raises(Seed::OrganizationLoader::Error) { Seed::OrganizationLoader.new(@dir).load! }
    assert_match "unknown organization \"Nobody At All\"", error.message
    assert_nil Organization.find_by(slug: "acme-fuel"), "nothing is written"
    assert_equal 0, Source.where(url: "https://example.com/news").count
  end
end
