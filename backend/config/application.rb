require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NuclearDirectory
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # "Page not found" uses the site's layout (ErrorsController). Every other
    # error keeps the static pages in public/, which work even when the app
    # itself is broken.
    config.exceptions_app = lambda do |env|
      status = env["PATH_INFO"].delete_prefix("/").to_i
      if status == 404
        ErrorsController.action(:not_found).call(env)
      else
        ActionDispatch::PublicExceptions.new(Rails.public_path).call(env)
      end
    end

    # Production traffic comes through Cloudflare, then Render's proxy. Rails
    # trusts only private addresses as proxies, so request.remote_ip was a
    # Cloudflare edge address, and every per-IP rate limit (corrections,
    # sign-in, the snapshot API, the relay) lumped unrelated visitors together.
    # Trusting Cloudflare's published ranges as well makes remote_ip the
    # visitor's own address, while an address a client adds to
    # X-Forwarded-For itself is still ignored. Ranges from
    # https://www.cloudflare.com/ips-v4 and /ips-v6, checked 2026-10-12;
    # they rarely change.
    CLOUDFLARE_RANGES = %w[
      173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18
      190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
      104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
      2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
    ].map { |range| IPAddr.new(range) }.freeze
    config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + CLOUDFLARE_RANGES
  end
end
