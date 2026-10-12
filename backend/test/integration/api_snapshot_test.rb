require "test_helper"
require_relative "../support/directory_builders"

# GET /api/snapshot.json (#193): the public summary other sites read.
class ApiSnapshotTest < ActionDispatch::IntegrationTest
  include DirectoryBuilders

  setup do
    DirectorySnapshot.expire!
    Api::SnapshotsController::RATE_LIMIT_STORE.clear

    vendor = role("reactor_vendor")
    utility = role("utility")
    @kairos = company("Kairos Power", roles: [ vendor ], verified_at: 3.days.ago)
    @nuscale = company("NuScale Power", roles: [ vendor ], verified_at: 2.days.ago)
    # In two categories: utilities, and investors through its deal.
    @duke = company("Duke Energy", roles: [ utility ], verified_at: 1.day.ago)
    link(@duke, "invests_in", @kairos)
    @vogtle = plant("Vogtle", verified_at: 4.days.ago)
    @hidden = company("Pending Co", verified: false)
    @gone = company("Gone Co").tap { |gone| gone.unpublish!(by: "human:test", reason: "test") }
    cite!(@kairos, @nuscale, @duke)
  end

  def snapshot
    get "/api/snapshot.json"
    response.parsed_body
  end

  test "the shape other sites rely on: names and types of every field" do
    body = snapshot

    assert_response :success
    assert_equal %w[categories recentlyAdded totalEntries updatedAt], body.keys.sort
    assert_kind_of Integer, body["totalEntries"]
    assert_nothing_raised { Time.iso8601(body["updatedAt"]) }

    assert_equal %w[fuel reactor-developers plants utilities services power-buyers investors fusion],
      body["categories"].map { |c| c["slug"] }, "the site's eight categories, in its order"
    body["categories"].each do |category|
      assert_equal %w[count examples name slug url], category.keys.sort
      assert_kind_of Integer, category["count"]
      assert category["examples"].all?(String) && category["examples"].size <= 2, category["slug"]
    end

    body["recentlyAdded"].each do |entry|
      assert_equal %w[addedAt category name url], entry.keys.sort
      assert_match(/\A\d{4}-\d{2}-\d{2}\z/, entry["addedAt"])
    end
  end

  test "counts follow the documented rule: entries once in the total, categories may overlap" do
    body = snapshot
    counts = body["categories"].to_h { |c| [ c["slug"], c["count"] ] }

    assert_equal 4, body["totalEntries"], "3 published companies and 1 site; pending and unpublished left out"
    assert_equal({ "reactor-developers" => 2, "utilities" => 1, "investors" => 1, "plants" => 1 }, counts.select { |_, n| n.positive? })
    assert counts.values.all? { |n| n <= body["totalEntries"] }
    assert_equal 1, counts["plants"], "Plants and sites counts every published site"
    assert_operator counts.values.sum, :>, body["totalEntries"] - counts["plants"], "Duke is counted in two categories"
  end

  test "examples and recent additions name only published entries, newest first" do
    body = snapshot
    names = body["categories"].flat_map { |c| c["examples"] } + body["recentlyAdded"].map { |e| e["name"] }

    assert_not_includes names, "Pending Co"
    assert_not_includes names, "Gone Co"
    assert_equal [ "Duke Energy", "NuScale Power", "Kairos Power", "Vogtle" ], body["recentlyAdded"].map { |e| e["name"] }
    assert_equal [ "Utilities and operators", "Reactor developers", "Reactor developers", "Plants and sites" ],
      body["recentlyAdded"].map { |e| e["category"] }
    assert_equal 1.day.ago.to_date.iso8601, body["recentlyAdded"].first["addedAt"]
    assert_equal [ "Duke Energy" ], body["categories"].find { |c| c["slug"] == "investors" }["examples"]
  end

  test "every url opens a real page on the site" do
    body = snapshot
    urls = body["categories"].map { |c| c["url"] } + body["recentlyAdded"].map { |e| e["url"] }

    urls.each do |url|
      assert url.start_with?("http://www.example.com/"), url
      get URI(url).request_uri
      assert_response :success, url
    end
  end

  test "public, cacheable JSON for any origin; read from memory after the first request" do
    snapshot

    assert_equal "application/json", response.media_type
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_equal %w[max-age=300 public s-maxage=3600 stale-while-revalidate=86400],
      response.headers["Cache-Control"].split(", ").sort
    assert_no_queries { get "/api/snapshot.json" }
    assert_response :success
  end

  test "publishing or unpublishing a fact shows in the next snapshot" do
    assert_equal 4, snapshot["totalEntries"]

    company("Oklo", verified_at: Time.current)
    assert_equal 5, snapshot["totalEntries"]
    assert_equal "Oklo", snapshot["recentlyAdded"].first["name"]

    @nuscale.unpublish!(by: "human:tosin", reason: "test")
    assert_equal 4, snapshot["totalEntries"]
  end

  test "read-only, and rate limited per visitor" do
    post "/api/snapshot.json"
    assert_response :not_found

    Api::SnapshotsController::RATE_LIMIT.times { get "/api/snapshot.json" }
    assert_response :success
    get "/api/snapshot.json"
    assert_response :too_many_requests
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end
end
