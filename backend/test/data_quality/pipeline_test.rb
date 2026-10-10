require "test_helper"
require_relative "support/fake_directory"
require_relative "support/dummy_plugin"

class DataQuality::PipelineTest < ActiveSupport::TestCase
  setup do
    @lookup = FakeDirectory::Lookup.new(organizations: { "Acme Nuclear" => 7 })
    @writer = FakeDirectory::FactWriter.new
    @directory = FakeDirectory.client(lookup: @lookup, fact_writer: @writer)
  end

  def run_pipeline(**options)
    DataQuality::Pipeline.run("dummy", plugin: DummyPlugin.new, directory: @directory, **options)
  end

  def dummy_candidates = Candidate.where(source: Source.where(source_kind: "dummy")).order(:id)

  test "a dummy plug-in runs through every stage and publishes via FactWriter" do
    runs = run_pipeline(verifier: PublishEverything.new)

    assert_equal %w[crawl extract match verify], runs.map(&:stage)
    assert runs.all?(&:succeeded?)
    assert runs.all? { |run| run.source_kind == "dummy" && run.finished_at }
    assert_equal({ "sources" => 1, "candidates" => 2 }, runs[1].stats)
    assert_equal 1, runs[2].stats["matched"]
    assert_equal 2, runs[3].stats["published"]

    existing, created = dummy_candidates
    assert existing.status_merged?
    assert_equal [ "Organization", 7 ], [ existing.subject_type, existing.subject_id ]
    assert created.status_merged?
    assert_equal 1001, created.subject_id

    assert_equal 2, @writer.writes.size
    write = @writer.writes.first
    assert_equal "organization", write[:kind]
    assert_equal({ name: "Acme Nuclear", id: 7 }, write[:attributes], "a matched candidate updates its record")
    evidence = write[:evidence].sole
    assert_equal "crawler", evidence[:found_by]
    assert_equal existing.source_id, evidence[:source_id]
    assert_equal "Acme Nuclear", evidence[:quote]
    assert_equal runs.last.id, evidence[:crawl_run_id]
    assert_equal "verified", write[:verification][:status]
    assert_nil @writer.writes.second[:attributes][:id], "unmatched candidates create a new record"
  end

  test "by default nothing is published; everything goes to review" do
    run_pipeline

    assert dummy_candidates.all?(&:status_needs_review?)
    assert_empty @writer.writes
  end

  test "a write the directory rejects goes to review with the reason" do
    @directory = FakeDirectory.client(lookup: @lookup, fact_writer: FakeDirectory::FactWriter.new(fail_with: "name taken"))

    verify = run_pipeline(verifier: PublishEverything.new).last

    assert_equal 2, verify.stats["write_errors"]
    assert dummy_candidates.all?(&:status_needs_review?)
    assert_match "name taken", dummy_candidates.first.notes
  end

  test "stages can be rerun alone; rerunning extract replaces unprocessed candidates" do
    run_pipeline(only: %w[crawl extract])
    run_pipeline(only: "extract")

    assert_equal 2, dummy_candidates.count
    assert dummy_candidates.all?(&:status_new?)
  end

  test "a failing stage is recorded and stops the pipeline" do
    broken = DummyPlugin.new
    def broken.crawl(_run) = raise("site is down")

    error = assert_raises(RuntimeError) do
      DataQuality::Pipeline.run("dummy", plugin: broken, directory: @directory)
    end

    assert_equal "site is down", error.message
    run = CrawlRun.where(source_kind: "dummy").sole
    assert run.failed?
    assert_equal "RuntimeError: site is down", run.error
  end

  test "unknown stages and source kinds are refused" do
    assert_raises(ArgumentError) { run_pipeline(only: "publish") }
    assert_raises(DataQuality::Plugin::UnknownSourceKind) { DataQuality::Plugin.for("no_such_source") }
  end
end
