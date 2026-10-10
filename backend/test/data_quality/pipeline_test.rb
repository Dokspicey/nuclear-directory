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
    assert_equal({ "sources" => 1, "candidates" => 2, "unchanged" => 0, "empty" => 0 }, runs[1].stats)
    assert_equal 1, runs[2].stats["matched"]
    assert_equal 2, runs[3].stats["published"]

    assert_equal 1, runs[2].stats["proposed"]

    existing, created = dummy_candidates
    assert existing.status_merged?
    assert_equal [ "Organization", 7 ], [ existing.subject_type, existing.subject_id ]
    assert created.status_merged?
    assert_equal 1001, created.subject_id, "verify publishes the record match proposed"

    match_writes, verify_writes = @writer.writes.partition { |write| write[:verification].nil? }
    assert_equal [ { name: "NewCo Fission" } ], match_writes.map { |w| w[:attributes] },
      "match proposes the new one; attaching to the existing one writes nothing"

    assert_equal 2, verify_writes.size
    write = verify_writes.first
    assert_equal "organization", write[:kind]
    assert_equal({ id: 7, aliases: [ "Acme Nuclear" ] }, write[:attributes],
      "a published match keeps its own name and gains the one it was found under as an alias")
    evidence = write[:evidence].sole
    assert_equal "crawler", evidence[:found_by]
    assert_equal existing.source_id, evidence[:source_id]
    assert_equal "Acme Nuclear", evidence[:quote]
    assert_equal runs.last.id, evidence[:crawl_run_id]
    assert_equal "verified", write[:verification][:status]
    assert_equal 1001, verify_writes.second[:attributes][:id]
  end

  test "with the review-everything verifier nothing is published" do
    run_pipeline(verifier: DataQuality::Verifiers::ReviewEverything.new)

    assert dummy_candidates.all?(&:status_needs_review?)
    assert @writer.writes.none? { |write| write[:verification] }, "only pending writes, nothing verified"
  end

  test "a write the directory rejects goes to review with the reason" do
    @directory = FakeDirectory.client(lookup: @lookup, fact_writer: FakeDirectory::FactWriter.new(fail_with: "name taken"))

    match = run_pipeline(verifier: PublishEverything.new)[2]

    assert_equal 1, match.stats["write_errors"], "the proposal fails at match; the attached one fails on publish"
    assert dummy_candidates.all?(&:status_needs_review?)
    assert_match "name taken", dummy_candidates.first.notes
  end

  test "extract skips content it has already processed" do
    run_pipeline(only: %w[crawl extract])
    rerun = run_pipeline(only: "extract").sole

    assert_equal({ "sources" => 0, "candidates" => 0, "unchanged" => 1, "empty" => 0 }, rerun.stats)
    assert_equal 2, dummy_candidates.count
  end

  test "changed content is extracted again, replacing unprocessed candidates" do
    run_pipeline(only: %w[crawl extract])
    source = Source.find_by!(url: DummyPlugin::URL)
    source.update!(content_text: "new text", content_sha256: Digest::SHA256.hexdigest("new text"))

    run_pipeline(only: "extract")

    assert_equal 2, dummy_candidates.count
    assert dummy_candidates.all?(&:status_new?)
    assert_equal source.content_sha256, source.reload.extracted_sha256
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
