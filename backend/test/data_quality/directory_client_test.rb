require "test_helper"
require_relative "support/fake_directory"
require_relative "support/dummy_plugin"

# DirectoryClient against the real Directory::Lookup and Directory::FactWriter,
# so the module and the directory can't silently drift apart. (Tests may use
# directory models; only module code is held to the boundary.)
class DataQuality::DirectoryClientTest < ActiveSupport::TestCase
  setup do
    @client = DataQuality::DirectoryClient.new
    @run = CrawlRun.create!(stage: "verify", source_kind: "web_page", model: "vendor/verifier")
  end

  def candidate(kind, payload, quote: "TerraPower, founded by Bill Gates")
    Candidate.create!(source: sources(:press_release), kind: kind, payload: payload, quote: quote)
  end

  test "finds organizations by name or alias, then by domain" do
    assert_equal DataQuality::DirectoryClient::Ref.new(type: "Organization", id: organizations(:terrapower).id),
      @client.find("organization", { "name" => "TerraPower, LLC" })
    assert_equal organizations(:terrapower).id,
      @client.find("organization", { "name" => "Unknown name", "domain" => "https://www.terrapower.com/news" }).id
    assert_nil @client.find("organization", { "name" => "Nobody" })
    assert_nil @client.find("organization", {})
  end

  test "writes a new fact with its evidence, verified by the agent" do
    result = @client.write_fact(candidate("organization", { "name" => "NewCo Fission", "website" => "https://newco.example" }),
      confidence: 0.9, crawl_run: @run)

    assert result.success?, result.errors.inspect
    assert_equal "Organization", result.ref.type
    newco = Directory::Lookup.organization(id: result.ref.id)
    assert_equal "NewCo Fission", newco.name
    assert_equal "verified", newco.verification_status

    evidence = Evidence.find_by!(subject_type: "Organization", subject_id: newco.id)
    assert_equal [ "crawler", 0.9, @run.id, sources(:press_release).id ],
      [ evidence.found_by, evidence.confidence.to_f, evidence.crawl_run_id, evidence.source_id ]
    assert_equal "agent:verifier/vendor/verifier", Organization.find(newco.id).verified_by
  end

  test "a matched candidate updates its record instead of creating one" do
    terrapower = organizations(:terrapower)
    matched = candidate("organization", { "name" => "TerraPower", "website" => "https://terrapower.com" })
    matched.update!(status: "matched", subject_type: "Organization", subject_id: terrapower.id)

    assert_no_difference -> { Organization.count } do
      assert @client.write_fact(matched, confidence: 0.8, crawl_run: @run).success?
    end
    assert_equal "https://terrapower.com", terrapower.reload.website
  end

  test "returns the directory's errors instead of raising" do
    result = @client.write_fact(candidate("organization", { "name" => "X", "favourite_colour" => "blue" }),
      confidence: 0.5, crawl_run: @run)

    assert_not result.success?
    assert_match "unknown attributes: favourite_colour", result.errors.join
  end

  test "the dummy plug-in runs through every stage into the real directory" do
    runs = DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, verifier: PublishEverything.new)

    assert runs.all?(&:succeeded?)
    assert_equal 2, runs.last.stats["published"]
    assert_equal %w[Acme\ Nuclear NewCo\ Fission].to_set,
      %w[Acme\ Nuclear NewCo\ Fission].filter_map { |name| Directory::Lookup.organization(name:)&.name }.to_set
  end

  test "the fakes keep the real interface's method signatures" do
    {
      "Lookup.organization" => [ Directory::Lookup.method(:organization), FakeDirectory::Lookup.instance_method(:organization) ],
      "Lookup.facility" => [ Directory::Lookup.method(:facility), FakeDirectory::Lookup.instance_method(:facility) ],
      # FactWriter.write forwards (...) to the instance method, which has the real signature.
      "FactWriter.write" => [ Directory::FactWriter.instance_method(:write), FakeDirectory::FactWriter.instance_method(:write) ]
    }.each do |name, (real, fake)|
      assert_equal real.parameters, fake.parameters, "the fake #{name} no longer matches the real one"
    end
  end
end
