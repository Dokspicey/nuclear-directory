# Stands in for the DB-IP country database (GeoCountry.reader) in tests:
# answers #get(ip) like MaxMind::DB, from a small table.
class FakeGeoReader
  RECORDS = {
    "81.2.69.142" => { "country" => { "iso_code" => "GB", "names" => { "en" => "United Kingdom" } }, "continent" => { "code" => "EU" } },
    "8.8.8.8" => { "country" => { "iso_code" => "US", "names" => { "en" => "United States" } }, "continent" => { "code" => "NA" } }
  }.freeze

  def get(ip) = RECORDS[ip]
end

# Sets GeoCountry's reader (and INTERNAL_IPS) for one test, then puts them back.
module GeoCountryTestHelper
  extend ActiveSupport::Concern

  included do
    setup do
      @previous_reader = GeoCountry.reader
      @previous_internal = ENV["INTERNAL_IPS"]
      GeoCountry.reader = FakeGeoReader.new
      GeoCountry.reset!
    end

    teardown do
      GeoCountry.reader = @previous_reader
      ENV["INTERNAL_IPS"] = @previous_internal
      GeoCountry.reset!
    end
  end

  def internal_ips!(value)
    ENV["INTERNAL_IPS"] = value
    GeoCountry.reset!
  end
end
