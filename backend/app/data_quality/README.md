# DataQuality

The workflow that fills the directory from public sources:

```
crawl → extract → match → verify → publish / review
```

It is a self-contained module (decision in #1) so it can later move to its
own service or repo without rewrites.

## The boundary

- **Owns:** `sources`, `crawl_runs`, `candidates` (models `Source`, `CrawlRun`, `Candidate`).
- **Reads** directory data only through `Directory::Lookup`.
- **Writes** facts and evidence only through `Directory::FactWriter`.
- Both calls live in one file, [`directory_client.rb`](directory_client.rb). Nothing
  else in the module may name directory models or `Directory::` code.

`test/data_quality/boundary_test.rb` enforces this and fails CI on a violation:
a directory model (`Organization`, `Evidence`, …), `Directory::` outside
`directory_client.rb`, `.subject` (which loads a directory record), or
`constantize`.

## Layout

| File | What it is |
|---|---|
| `pipeline.rb` | Runs stages in order, or just some of them |
| `stage.rb`, `stages/` | One class per stage. Each run is a `crawl_runs` row |
| `plugin.rb`, `plugins/` | One plug-in per `source_kind`: its crawl and extract logic |
| `verdict.rb`, `verifiers/` | Verify outcomes. Default sends everything to review until #15 |
| `directory_client.rb` | The only door into the directory |
| `open_router/client.rb` | LLM calls with JSON-schema output, retries, token accounting |
| `config.rb` | Settings from env (`OPENROUTER_*`) |
| `run_job.rb` | Background job (Solid Queue, queue `data_quality`) |

Tests live in `test/data_quality/`. They use a fake directory
(`support/fake_directory.rb`) and a dummy plug-in, and never make real HTTP calls.

## Running it

```bash
docker compose run --rm web bin/rails "data_quality:run[nrc_reactor_list]"
```

```bash
docker compose run --rm web bin/rails "data_quality:stage[extract,nrc_reactor_list]"
```

Or from code: `DataQuality::RunJob.perform_later("nrc_reactor_list", only: "extract")`.
The quotes stop zsh from treating `[...]` as a file pattern.

## Adding a source

Create `plugins/<source_kind>.rb` defining `DataQuality::Plugins::<SourceKind> < DataQuality::Plugin`
with `crawl(run)` and `extract(source, run)` (see `plugin.rb`). Match and verify are shared.

## What the module expects from the directory (#32)

`directory_client.rb` calls exactly this. The fakes in
`test/data_quality/support/fake_directory.rb` implement the same calls.

```ruby
Directory::Lookup.find_organization(name:, domain:)   # => object with #id, or nil
Directory::Lookup.find_facility(name:, nrc_docket:)    # => object with #id, or nil

Directory::FactWriter.write(
  kind:,         # candidate kind, e.g. "organization"
  attributes:,   # candidate payload hash
  subject:,      # { type:, id: } of the matched record, or nil to create
  evidence:,     # { source_id:, quote:, found_by:, confidence:, crawl_run_id: }
  verified_by:   # e.g. "agent:verifier/<model>"
) # => result with #success?, #record_type, #record_id, #errors
```

If #32 settles on different names, change `directory_client.rb` and the fakes. Nothing else.
