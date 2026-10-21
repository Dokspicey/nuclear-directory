require "test_helper"
require "app_hosts"

# #147: production restricts to the hosts named in APP_HOSTS (set per
# service in render.yaml). Unset means no restriction, which is what CI's
# Lighthouse audit and a local production run need. Render's health check
# and the Sentry uptime monitor hit /up without our Host, so it has to
# stay 200 even when a list is set — production.rb's host_authorization
# exclude handles that; Rails tests the ActionDispatch::HostAuthorization
# middleware itself, so this file only tests the parsing production.rb
# depends on.
class AppHostsTest < ActiveSupport::TestCase
  test "parses a comma-separated list, trimming whitespace and blanks" do
    assert_equal %w[a.example b.example], AppHosts.from_env("APP_HOSTS" => "a.example, b.example,  ")
  end

  test "no APP_HOSTS means no restriction, which CI's Lighthouse and a local production run need" do
    assert_empty AppHosts.from_env({})
    assert_empty AppHosts.from_env("APP_HOSTS" => "")
    assert_empty AppHosts.from_env("APP_HOSTS" => "   ,  , ")
  end

  test "the production hostnames are what render.yaml sets for the web service" do
    assert_equal %w[nuclear-directory.org www.nuclear-directory.org],
      AppHosts.from_env("APP_HOSTS" => "nuclear-directory.org,www.nuclear-directory.org")
  end
end
