require "test_helper"
require_relative "../support/directory_builders"

class CompanyPageTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  setup do
    @press = Source.create!(url: "https://kairospower.com/news/google", title: "Google and Kairos Power partner",
      source_kind: "web_page", published_on: Date.new(2024, 10, 14))
    @doe_page = Source.create!(url: "https://www.energy.gov/haleu", source_kind: "web_page")

    @kairos = company("Kairos Power", city: "Alameda", state: "CA", roles: [ role("reactor_vendor") ],
      techs: [ technology("smr", "Small modular reactor") ], aliases: [ "Kairos Power, LLC", "Kairos" ],
      website: "https://kairospower.com", description: "Develops salt-cooled reactors.", verified_at: Time.zone.parse("2026-10-09"))
    @google = company("Google", roles: [ role("data_center_offtaker") ])
    @doe = company("US Department of Energy")
    @ghost = company("Ghost Partner", verified: false)

    deal = link(@google, "offtake_with", @kairos)
    deal.update!(description: "500 MW by 2035.", verified_at: Time.zone.parse("2026-10-09"))
    deal.evidence.create!(source: @press, quote: "Kairos Power and Google have signed", found_by: "human", confidence: 1)
    link(@doe, "supplies", @kairos).evidence.create!(source: @doe_page, found_by: "human", confidence: 0.8)
    link(@ghost, "invests_in", @kairos)
    link(@kairos, "funds", @google, verified: false)

    @hermes = plant("Hermes", facility_type: "research_reactor", status: "under_construction", city: "Oak Ridge", state: "TN")
    link(@kairos, "owns", @hermes).evidence.create!(source: @press, found_by: "human", confidence: 1)
    hidden = plant("Hidden Site", verified: false)
    link(@kairos, "owns", hidden)
  end

  test "a verified company's page shows its facts" do
    get company_path(slug: "kairos-power")

    assert_response :success
    assert_select "title", "Kairos Power · Nuclear Directory"
    assert_select "main", 1
    assert_select "h1#profile-name", "Kairos Power"
    assert_select ".nd-profile__desc", /Develops salt-cooled reactors./
    assert_select ".nd-tag", "Reactor developer"
    assert_select ".nd-tag", "Small modular reactor"
    assert_select ".nd-crumbs a[href=?]", "/companies?category=reactor-developers", text: "Reactor developers"
  end

  test "deals read left to right, link the other company, and carry sources" do
    get company_path(slug: "kairos-power")

    assert_select "#deals-heading small", "2"
    assert_select ".nd-factrow", text: /Google\s+offtakes from\s+Kairos Power/ do
      assert_select "a[href='/companies/google']", "Google"
      assert_select ".nd-factrow__detail", "500 MW by 2035."
      assert_select ".nd-quote", "“Kairos Power and Google have signed”"
      assert_select "a.nd-src[href='#source-1']", /kairospower.com · checked 2026-10-09/
      assert_select ".nd-conf", /High/
    end
    assert_select ".nd-factrow", text: /US Department of Energy\s+supplies\s+Kairos Power/
  end

  test "unverified partners, deals and plants never appear" do
    get company_path(slug: "kairos-power")

    assert_select "body", text: /Ghost Partner/, count: 0
    assert_select ".nd-factrow", text: /funds/, count: 0
    assert_select "body", text: /Hidden Site/, count: 0
  end

  test "plants and sites link to the plant page" do
    get company_path(slug: "kairos-power")

    assert_select ".nd-factrow", text: /Kairos Power\s+owns\s+Hermes/ do
      assert_select "a[href='/plants/hermes']", "Hermes"
      assert_select ".nd-factrow__detail", "Test reactor · Under construction · Oak Ridge, TN"
    end
  end

  test "sources are numbered once, in reading order" do
    get company_path(slug: "kairos-power")

    assert_select "#sources-heading small", "2"
    assert_select "li#source-1 a[href='https://kairospower.com/news/google']", "Google and Kairos Power partner"
    assert_select "li#source-2 small", "energy.gov"
  end

  test "key facts" do
    get company_path(slug: "kairos-power")

    assert_select ".nd-overview dt", text: "Website"
    assert_select ".nd-overview dd a[href='https://kairospower.com']", "kairospower.com"
    assert_select ".nd-overview dd", text: "Kairos"
    assert_select ".nd-overview dd", text: "Alameda, CA"
    assert_select ".nd-overview dt", text: "Founded", count: 0
    assert_select ".nd-overview__foot", /checked 2026-10-09/
  end

  test "a parent company shows in the key facts, not as a deal" do
    parent = company("Southern Company")
    link(@kairos, "subsidiary_of", parent)
    get company_path(slug: "kairos-power")

    assert_select ".nd-overview dt", "Parent company"
    assert_select ".nd-overview dd a[href='/companies/southern-company']", "Southern Company"
    assert_select ".nd-factrow", text: /subsidiary/, count: 0
  end

  test "a general role is left out when a more specific one under it is there" do
    coolant = role("coolant")
    [ coolant, role("molten_salt", parent: coolant) ].each do |r|
      OrganizationRole.create!(organization: @kairos, role: r, verification_status: "verified")
    end
    get company_path(slug: "kairos-power")

    assert_select ".nd-tag", text: "Molten salt coolant"
    assert_select ".nd-tag", text: "Coolant", count: 0
  end

  test "missing must-have fields are listed, not guessed" do
    get company_path(slug: "google")

    assert_select ".nd-gaps li", text: "One-line description"
    assert_select ".nd-gaps li", text: "Headquarters"
    assert_select ".nd-profile__desc", count: 0
  end

  test "long lists collapse behind Show all" do
    (CompanyProfile::VISIBLE_ITEMS + 1).times do |i|
      link(company("Supplier #{i}"), "supplies", @kairos)
    end
    get company_path(slug: "kairos-power")

    assert_select "#deals-heading ~ ul.nd-list > li", CompanyProfile::VISIBLE_ITEMS
    assert_select "details.nd-more summary", "Show all #{CompanyProfile::VISIBLE_ITEMS + 3} deals"
  end

  test "link preview tags" do
    get company_path(slug: "kairos-power")

    assert_select "meta[property='og:title'][content='Kairos Power']"
    assert_select "meta[property='og:description'][content='Develops salt-cooled reactors.']"
    assert_select "link[rel=canonical][href=?]", "http://www.example.com/companies/kairos-power"
  end

  test "an unverified or unknown company is not found" do
    get company_path(slug: "ghost-partner")
    assert_response :not_found

    get company_path(slug: "nobody")
    assert_response :not_found
  end
end
