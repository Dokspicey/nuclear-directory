# sitemap.xml and robots.txt (#56), built per request so the host is right
# on every deploy (preview URLs and the real domain alike).
class SitemapsController < ApplicationController
  def show
    @companies = Organization.published.select(:slug).order(:slug)
    @plants = Facility.published.where(parent_id: nil).select(:slug).order(:slug)
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
