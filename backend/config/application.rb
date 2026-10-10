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
  end
end
