require "test_helper"

# How the admin's Sources groups documents (#201 part 2b): Data Quality's
# domain list, and the fallbacks for a domain that isn't on it.
class SourceCatalogTest < ActiveSupport::TestCase
  test "publisher groups come from Data Quality's list, with Company sites and Government as fallbacks" do
    assert_equal "nrc-pages", SourceCatalog.group_of("nrc.gov")
    assert_equal "sec-filings", SourceCatalog.group_of("www.sec.gov")
    assert_equal "news", SourceCatalog.group_of("world-nuclear-news.org")
    assert_equal "government", SourceCatalog.group_of("content.govdelivery.com")
    assert_equal "government", SourceCatalog.group_of("ornl.gov"), "an unknown .gov"
    assert_equal "company-sites", SourceCatalog.group_of("cfs.energy"), "anything else"
  end

  test "groups are sorted by size, and a group's facts count each fact once" do
    before = SourceCatalog.research.to_h { |entry| [ entry.key, entry ] }
    a = Source.create!(url: "https://cfs.energy/a", source_kind: "web_page", domain: "cfs.energy")
    b = Source.create!(url: "https://cfs.energy/b", source_kind: "web_page", domain: "cfs.energy")
    Source.create!(url: "https://www.energy.gov/x", source_kind: "web_page", domain: "energy.gov")
    company = Organization.create!(name: "Twice Cited", verification_status: "verified", verified_by: "human:tosin")
    Evidence.create!(subject: company, source: a, quote: "x", found_by: "human")
    Evidence.create!(subject: company, source: b, quote: "y", found_by: "human")

    research = SourceCatalog.research
    after = research.to_h { |entry| [ entry.key, entry ] }
    added = ->(key, field) { after[key].public_send(field) - (before[key]&.public_send(field) || 0) }
    assert_equal [ 2, 1 ], [ added.("company-sites", :documents), added.("government", :documents) ]
    assert_equal 1, added.("company-sites", :facts), "cited on two of its pages, counted once"
    assert_equal research.map(&:documents).sort.reverse, research.map(&:documents), "largest group first"
  end

  test "a document reads as its title, else its path, else '/ (home page)'" do
    document = ->(url, title = nil) { SourceCatalog::Document.new(id: 1, kind: "web_page", url:, title:, domain: nil, group: nil, facts: 0, last_read_at: nil, status: "pending", status_reason: nil) }

    assert_equal "CFS raises", document.("https://cfs.energy/x", "CFS raises").text
    assert_equal "/technology/arc", document.("https://cfs.energy/technology/arc").text
    assert_equal "/ (home page)", document.("https://cfs.energy").text
  end
end
