require "test_helper"

# request.remote_ip behind Cloudflare and Render. The edge and proxy addresses
# are the kind the preview logged (#211): visitor, Cloudflare edge, Render's proxy.
class RemoteIpTest < ActionDispatch::IntegrationTest
  class EchoController < ActionController::Base
    def show = render(plain: request.remote_ip)
  end

  VISITOR = "203.0.113.7" # a documentation address (RFC 5737)
  RENDER_PROXY = "10.24.135.5"

  def remote_ip(forwarded_for)
    with_routing do |routes|
      routes.draw { get "echo" => "remote_ip_test/echo#show" }
      get "/echo", headers: { "X-Forwarded-For" => forwarded_for }, env: { "REMOTE_ADDR" => RENDER_PROXY }
      response.body
    end
  end

  test "through Cloudflare (IPv4 and IPv6 edges) and Render, it's the visitor" do
    assert_equal VISITOR, remote_ip("#{VISITOR}, 104.22.17.59")
    assert_equal VISITOR, remote_ip("#{VISITOR}, 172.69.134.44")
    assert_equal VISITOR, remote_ip("#{VISITOR}, 2606:4700:10::6816:113b")
  end

  test "an address a client adds itself is ignored" do
    assert_equal VISITOR, remote_ip("1.2.3.4, #{VISITOR}, 104.22.17.59")
  end

  test "a hop that isn't Cloudflare isn't trusted" do
    assert_equal "8.8.8.8", remote_ip("#{VISITOR}, 8.8.8.8")
  end

  test "Cloudflare's ranges are trusted, on top of the private defaults" do
    proxies = Rails.application.config.action_dispatch.trusted_proxies

    assert proxies.any? { |range| range.include?(IPAddr.new("104.22.17.59")) }
    assert proxies.any? { |range| range.include?(IPAddr.new("10.24.135.5")) }, "Render's private proxy still trusted"
    assert_not proxies.any? { |range| range.include?(IPAddr.new("8.8.8.8")) }
  end
end
