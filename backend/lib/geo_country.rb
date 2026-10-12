require "maxmind/db"

# The visitor's country, looked up on our server from the request's IP (#205),
# so PostHog's map works while analytics stays cookieless: PostHog's
# cookieless mode drops the IP before its own lookup runs (PostHog #48660).
# Only the country goes into events; the IP itself is never added to one.
#
#   GeoCountry.properties("81.2.69.142")
#   # => { "$geoip_country_code" => "GB", "$geoip_country_name" => "United Kingdom",
#   #      "$geoip_continent_code" => "EU", "$geoip_disable" => true }
#
# The data is DB-IP's "IP to Country Lite" (CC BY 4.0, credited on /privacy),
# downloaded when the image is built (Dockerfile) into vendor/geo. Without the
# file, lookups return nothing and events simply carry no country.
#
# INTERNAL_IPS (comma-separated addresses or ranges, e.g. Tosin's home) marks
# events internal: true, for PostHog's "Filter out internal and test users".
module GeoCountry
  DEFAULT_PATH = Rails.root.join("vendor/geo/dbip-country-lite.mmdb").to_s

  class << self
    # Tests assign a fake that answers #get(ip) like MaxMind::DB.
    attr_writer :reader

    def reader
      return @reader if defined?(@reader)

      @reader = load_reader
    end

    # PostHog event properties for this IP: the country (when known), and
    # $geoip_disable so PostHog's own lookup doesn't blank it. internal: true
    # for an INTERNAL_IPS address, or when the caller knows it's us (admin:,
    # a browser signed in to the admin; AdminVisitor).
    def properties(ip, admin: false)
      props = { "$geoip_disable" => true }
      if (record = lookup(ip))
        props["$geoip_country_code"] = record.dig("country", "iso_code")
        props["$geoip_country_name"] = record.dig("country", "names", "en")
        props["$geoip_continent_code"] = record.dig("continent", "code")
      end
      props["internal"] = true if admin || internal?(ip)
      props.compact
    end

    def internal?(ip)
      address = parse(ip) or return false
      internal_ranges.any? { |range| range.include?(address) }
    rescue IPAddr::InvalidAddressError
      false
    end

    # Re-read INTERNAL_IPS (tests change it).
    def reset! = @internal_ranges = nil

    private
      def lookup(ip)
        return unless reader && parse(ip)

        reader.get(ip.to_s)
      rescue ArgumentError, MaxMind::DB::InvalidDatabaseError
        nil
      end

      def parse(ip)
        IPAddr.new(ip.to_s)
      rescue IPAddr::InvalidAddressError
        nil
      end

      def internal_ranges
        @internal_ranges ||= ENV["INTERNAL_IPS"].to_s.split(",").map(&:strip).reject(&:empty?).filter_map do |range|
          IPAddr.new(range)
        rescue IPAddr::InvalidAddressError
          Rails.logger.warn("[analytics] INTERNAL_IPS: #{range.inspect} isn't an IP address or range; ignored")
          nil
        end
      end

      def load_reader
        path = ENV["GEO_COUNTRY_DB"].presence || DEFAULT_PATH
        return nil if Rails.env.test? || !File.exist?(path)

        MaxMind::DB.new(path, mode: MaxMind::DB::MODE_MEMORY)
      rescue MaxMind::DB::InvalidDatabaseError, SystemCallError => error
        Rails.logger.warn("[analytics] No IP-to-country data (#{error.class}): events carry no country")
        nil
      end
  end
end
