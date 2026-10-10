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

Fetch with `DataQuality::Snapshot.take(source, fetcher: DataQuality::Fetcher.new)`, never your own HTTP:
- **`Fetcher`** identifies as `NuclearDirectoryBot`, obeys robots.txt, waits between requests to a host,
  sends ETag / If-Modified-Since, and never retries.
- **`Snapshot`** fetches a source at most once a day and records the result on it: content and hash,
  `blocked` with the CDN reference on a 403 (`needs_human` after 3 in a row), or `needs_human` if
  robots.txt disallows it.
- **Extract skips** sources whose content hash hasn't changed since the last extraction.

Never work around a block. `plugins/nrc_reactor_list.rb` is the reference plug-in.

## What extract produces

`extract(source, run)` returns candidate hashes, which the extract stage saves to `candidates`:

| Key | What it is |
|---|---|
| `kind` | One of `Candidate::KINDS`: the six FactWriter kinds plus `organization_alias` |
| `payload` | String keys. Records use FactWriter attribute names. Links name each end with a nested hash (`"organization" => { "name" => … }`, `"facility" => { "name" => …, "nrc_docket" => … }`), never `*_id`; match resolves those |
| `quote` | The supporting text, copied exactly from the source |
| `status`, `notes` | Optional: `status: "needs_review"` with the reason in `notes` sends a candidate straight to review. The stage marks it `review_origin: "extract"`, so re-extracting a changed source replaces it (with the source's `new` candidates) instead of piling up duplicates |

The extract stage adds `source_id` and `crawl_run_id`. Candidates start `new` (or `needs_review` if
the plug-in flagged them). Match links the ones it can to directory records (`matched`), and verify
then publishes (`merged`), sends to review (`needs_review`) or rejects (`rejected`). See
`stages/match.rb` for what match does with the rest.

**NRC extract.** The extractor model (`OPENROUTER_EXTRACT_MODEL`, prompt `nrc-extract-v1`) reads the
reactor table as plain lines and returns each unit with its row quoted. Every answer is checked
against the exact parse of the table, by docket. Candidates always carry the table's values; a unit
the model got wrong, misquoted or skipped goes to review with both values in `notes`, and units it
invents are dropped. The tally is in the extract run's `stats["ai_check"]`, so the model's accuracy
is measured on a source we can check before it's trusted on messier ones. Per unit: the unit
(`facility`), its operator (`organization`, one per name) and an `operates` link. The unit's `state` is
evidence, not the final word: NRC's Location measures from a nearby city, which near a border is in
another state (Salem and Hope Creek are in NJ, listed from "Wilmington, DE"; Catawba SC; Fermi 2 MI).
EIA's plant state wins for that field (Tosin's decision; the EIA plug-in applies it).

## Talking to the directory

The contract is in [`app/directory/README.md`](../directory/README.md).
`directory_client.rb` uses `Directory::Lookup.organization` / `.facility` and
`Directory::FactWriter.write(kind, attributes, evidence: [...], verification: {...})`.

Two tests keep the module and the directory in step:
- `directory_client_test.rb` runs `DirectoryClient`, and the whole pipeline,
  against the real directory classes.
- It also checks that the fakes in `support/fake_directory.rb` have the same
  method signatures as the real interfaces.

## Giving others a source

Sources belong to this module. Code outside it (e.g. the seed loader) gets one
with `DataQuality::Sources.find_or_create(url:, source_kind:, published_on:)`,
which returns a plain `SourceRef`.
