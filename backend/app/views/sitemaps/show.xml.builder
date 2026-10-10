xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  [ root_url, companies_url, *Category.all.map { |category| companies_url(category: category.to_param) },
    privacy_url, disclaimer_url, bot_url ].each do |url|
    xml.url { xml.loc url }
  end
  @companies.each do |company|
    xml.url do
      xml.loc company_url(slug: company.slug)
      xml.lastmod company.updated_at.to_date.iso8601
    end
  end
  @plants.each do |plant|
    xml.url do
      xml.loc plant_url(slug: plant.slug)
      xml.lastmod plant.updated_at.to_date.iso8601
    end
  end
end
