# Keeps preview deploys out of search engines. When NOINDEX is set, every
# response, assets and /up included, carries X-Robots-Tag and robots.txt
# disallows everything. Set it on preview deploys only, never on the live site.
class Noindex
  HEADER = "noindex, nofollow".freeze

  def self.enabled? = ENV["NOINDEX"].present?

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers["x-robots-tag"] = HEADER if self.class.enabled?
    [ status, headers, body ]
  end
end

Rails.application.config.middleware.insert_before 0, Noindex
