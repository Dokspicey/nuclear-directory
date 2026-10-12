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
    blueprint = Marshal.load(Marshal.dump(BASE))
    blueprint["databases"].each { |database| database["ipAllowList"] = allow_list }
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
