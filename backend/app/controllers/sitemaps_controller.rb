# sitemap.xml and robots.txt (#56), built per request so the host is right
# on every deploy (preview URLs and the real domain alike).
class SitemapsController < ApplicationController
  def show
    @companies = Organization.verified.select(:slug, :updated_at).order(:slug)
    @plants = DirectoryListing.new.public_sites.select(:slug, :updated_at).order(:slug)
    expires_in 1.hour, public: true
  end

  def robots
    expires_in 1.day, public: true
    render plain: <<~TXT
      User-agent: *
      Disallow: /admin
      Disallow: /corrections
      Disallow: /search
      Disallow: /design

      Sitemap: #{sitemap_url}
    TXT
  end
end
