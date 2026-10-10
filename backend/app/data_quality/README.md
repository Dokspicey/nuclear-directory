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

## Matching and candidate payloads

Extract writes `candidates` (`kind`, `payload`, `quote`, `source_id`). Match
([`stages/match.rb`](stages/match.rb)) then links each one to the directory:

| Outcome | When | Candidate becomes |
|---|---|---|
| **Found** | exact NRC docket, domain, or name/alias (normalized) | `matched`, subject = that record. Nothing is written yet: when verify publishes it, the quote is added as evidence and an organization gains the name as an alias (its own name is kept). A human-verified record only gets its blanks filled; a disagreement goes to review, and a rejected record is never changed. |
| **Not found** | nothing exact and nothing similar | `matched`, subject = a new **pending** record with the quote as evidence |
| **New unit of a known site** | an NRC unit (has a docket) whose only similar record is a site (no docket, no parent) that covers it | `matched`, subject = a new **pending** unit with `parent_id` = the site |
| **Ambiguous** | identifiers point at different records, or a similar record exists | `needs_review`, with the reason in `notes`. Never merged automatically. |

"Similar" means the same leading distinctive word, ignoring unit numbers and
generic words ("Vogtle 3" vs "Plant Vogtle Units 3 & 4", "Southern Nuclear
Operating Co." vs "Southern Company"). Facilities with different NRC dockets
are never similar, so "Braidwood 2" isn't flagged against "Braidwood 1".
Evidence from match is `found_by: crawler` with no confidence; verify sets
the confidence and decides whether the fact is published.

Organizations and facilities are matched first, so links in the same run can
find records proposed a moment earlier.

**Units and sites.** The seed names plants at site level ("Plant Vogtle Units 3
& 4", no docket); the NRC lists units ("Vogtle 3", with a docket). A site
covers the units its name lists ("Units 3 & 4" covers 3 and 4); a name that
lists none ("Susquehanna Steam Electric Station") covers every unit. A unit the
site doesn't cover ("Vogtle 1", or "Palisades" against "Palisades Pioneer Units
1 & 2"), or with more than one possible site, goes to review. When verify
publishes a unit, its `state`, `facility_type`, `status` and `country_code`
fill the site's **blank** fields only (FactWriter `fill_blank: true`), with
the unit's quote as evidence; the site's verification is left alone.

**Payloads.** Records carry their attributes, as named in the
[FactWriter table](../directory/README.md#kinds). Links name each end with a
nested hash that identifies it (organizations by `name` and/or `domain`,
facilities by `name` and/or `nrc_docket`):

```ruby
{ kind: "organization", payload: { "name" => "Southern Nuclear Operating Co." } }
{ kind: "facility", payload: { "name" => "Vogtle 3", "nrc_docket" => "05200025",
  "facility_type" => "power_reactor", "status" => "operating", "reactor_type" => "PWR", "state" => "GA" } }
{ kind: "facility_relationship", payload: {
  "organization" => { "name" => "Southern Nuclear Operating Co." },
  "facility" => { "name" => "Vogtle 3", "nrc_docket" => "05200025" },
  "relationship_type" => "operates" } }
{ kind: "organization_role", payload: { "organization" => { "name" => "…" }, "role" => "operator" } }
{ kind: "relationship", payload: { "from_organization" => { "name" => "…" },
  "to_organization" => { "name" => "…" }, "relationship_type" => "supplies" } }
```

A link whose end isn't found, or is itself in review, goes to `needs_review`
too. `organization_alias` candidates aren't matched automatically yet.

## Enrichment sources

Some sources only add values to records NRC already defines. **EIA**
(`plugins/eia_generators.rb`, #61) adds net summer capacity (`capacity_mw`) and
coordinates to NRC units from EIA's monthly generator inventory (Form
EIA-860M). It never creates or renames facilities.

```bash
docker compose run --rm web bin/rails "data_quality:run[eia_generators]"
```

- **Crawl** reads EIA's 860M page, takes the newest `<month>_generator<year>.xlsx`,
  and stores only its nuclear rows as CSV. There's one source per monthly
  file, so evidence names the exact file. If the workbook can't be read (for
  example, the layout changed), the source is marked `needs_human`.
- **Extract** makes a `facility` candidate per generator. The payload carries
  `"identify" => { "name", "state", "unit", "eia_plant_id" }` and the values to
  set. The quote is the generator's CSV row.
- **Match** finds the unit, in this order (`Directory::Lookup.facility_units`):
  1. the NRC units sharing the **most** distinctive words with EIA's plant name
     ("Wolf Creek" picks Wolf Creek 1 over Hope Creek 1);
  2. among those, units in EIA's state or with no state yet (a tie-break only;
     NRC unit candidates carry no state, and EIA's is used);
  3. the one with the same unit number. A plant with a single, unnumbered NRC
     unit takes that unit ("R E Ginna" → "Ginna").
  - The candidate is attached; nothing is written until verify publishes it.
  - Two equally good fits, or a rejected unit → `needs_review`.
  - No fit yet → the candidate stays `new` and is retried on the next run.
- **Verify** writes only the values. The unit's verification is unchanged,
  since EIA doesn't vouch for the record itself. A verified unit's
  coordinates also fill its site's blank ones.

Any payload with an `"identify"` key is treated as enrichment this way.
