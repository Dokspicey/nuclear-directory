require "test_helper"
require_relative "../support/fake_geo_reader"

# The visitor's country from their IP (#205), for PostHog's map.
class GeoCountryTest < ActiveSupport::TestCase
  include GeoCountryTestHelper

  test "a known IP gives its country and continent, and turns PostHog's own lookup off" do
    assert_equal({ "$geoip_disable" => true, "$geoip_country_code" => "GB", "$geoip_country_name" => "United Kingdom",
      "$geoip_continent_code" => "EU" }, GeoCountry.properties("81.2.69.142"))
  end

  test "an unknown, private or malformed address gives no country, and never the address" do
    [ "10.0.0.1", "127.0.0.1", "not an ip", "", nil ].each do |ip|
      props = GeoCountry.properties(ip)
      assert_equal({ "$geoip_disable" => true }, props, ip.inspect)
      assert_not props.values.include?(ip) if ip.present?
    end
  end

  test "without the database, events just carry no country" do
    GeoCountry.reader = nil

    assert_equal({ "$geoip_disable" => true }, GeoCountry.properties("81.2.69.142"))
  end

  test "INTERNAL_IPS marks addresses and ranges internal; bad entries are ignored" do
    internal_ips!("8.8.8.8, 192.0.2.0/24, not-an-ip")

    assert GeoCountry.properties("8.8.8.8")["internal"]
    assert GeoCountry.properties("192.0.2.77")["internal"]
    assert_nil GeoCountry.properties("81.2.69.142")["internal"]
    assert_equal "US", GeoCountry.properties("8.8.8.8")["$geoip_country_code"], "still gets its country"
  end

  test "no INTERNAL_IPS, nobody is internal" do
    internal_ips!(nil)

    assert_not GeoCountry.internal?("8.8.8.8")
  end
end
