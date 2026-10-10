require "test_helper"

class Seed::OrganizationLoaderTest < ActiveSupport::TestCase
  setup do
    Role.create!(key: "fuel", name: "Fuel")
    Role.create!(key: "enrichment", name: "Enrichment", parent: Role.find_by!(key: "fuel"))
    @dir = Dir.mktmpdir
  end

  teardown { FileUtils.remove_entry(@dir) }

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

  test "fails as a whole when any fact can't be written" do
    write_file("acme-fuel", org("Acme Fuel", website: "https://acmefuel.com",
      relationships: [ item(type: "supplies", to: "Nobody At All", description: "x") ]))

    error = assert_raises(Seed::OrganizationLoader::Error) { Seed::OrganizationLoader.new(@dir).load! }
    assert_match "unknown organization \"Nobody At All\"", error.message
    assert_nil Organization.find_by(slug: "acme-fuel"), "nothing is written"
    assert_equal 0, Source.where(url: "https://example.com/news").count
  end
end
