# Tests for check_blueprint.rb: runs it against variations of render.yaml.
# Run by CI (blueprint job): ruby .github/scripts/check_blueprint_test.rb
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

class CheckBlueprintTest < Minitest::Test
  SCRIPT = File.expand_path("check_blueprint.rb", __dir__)
  BASE = YAML.load_file(File.expand_path("../../render.yaml", __dir__))

  def check(allow_list)
    check_blueprint { |blueprint| blueprint["databases"].each { |database| database["ipAllowList"] = allow_list } }
  end

  # Runs the check on a copy of render.yaml changed by the block.
  def check_blueprint
    blueprint = Marshal.load(Marshal.dump(BASE))
    yield blueprint
    Dir.mktmpdir do |dir|
      path = File.join(dir, "render.yaml")
      File.write(path, blueprint.to_yaml)
      output, status = Open3.capture2e({ "RENDER_YAML" => path }, "ruby", SCRIPT)
      [ status.success?, output ]
    end
  end

  def host(source, description = "Tosin home (Metabase)")
    { "source" => source, "description" => description }
  end

  def check_preview
    check_blueprint { |blueprint| yield blueprint["services"].find { |service| service["name"] == "nuclear-directory-preview" }["envVars"] }
  end

  def test_the_preview_never_gets_the_production_database
    ok, output = check_preview do |vars|
      vars.find { |var| var["key"] == "DATABASE_URL" }.replace(
        "key" => "DATABASE_URL", "fromDatabase" => { "name" => "nuclear-directory-db", "property" => "connectionString" })
    end
    refute ok
    assert_includes output, "the preview's DATABASE_URL must be sync: false"
  end

  def test_the_preview_gets_no_production_secrets_and_stays_noindex
    ok, output = check_preview do |vars|
      vars << { "key" => "SENTRY_DSN", "sync" => false }
      vars.reject! { |var| var["key"] == "NOINDEX" }
    end
    refute ok
    assert_includes output, "the preview must not set SENTRY_DSN"
    assert_includes output, "the preview must set NOINDEX"
  end

  def test_the_real_render_yaml_passes
    output, status = Open3.capture2e("ruby", SCRIPT)
    assert status.success?, output
  end

  def test_no_internet_access_passes
    assert check([]).first
  end

  def test_one_described_host_passes
    assert check([ host("99.110.208.39/32") ]).first
  end

  def test_open_to_the_world_fails
    ok, output = check([ host("0.0.0.0/0") ])
    refute ok
    assert_includes output, "may only allow one IPv4 host"
  end

  def test_wider_ranges_fail
    [ "99.110.208.0/24", "10.0.0.0/8", "99.110.208.39/31", "99.110.208.39" ].each do |source|
      refute check([ host(source) ]).first, source
    end
  end

  def test_odd_entries_fail
    refute check([ host("99.110.208.39/32", "") ]).first, "no description"
    refute check([ host("0.0.0.0/32") ]).first, "0.0.0.0"
    refute check([ host("300.1.1.1/32") ]).first, "bad octet"
    refute check([ host("2001:db8::1/128") ]).first, "IPv6"
    refute check(nil).first, "missing ipAllowList"
  end

  def test_one_bad_entry_among_good_ones_fails
    refute check([ host("99.110.208.39/32"), host("0.0.0.0/0") ]).first
  end

  def test_a_second_host_fails
    refute check([ host("99.110.208.39/32"), host("99.110.208.40/32", "Someone else") ]).first
  end
end
