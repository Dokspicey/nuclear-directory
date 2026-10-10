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

To see how it's doing (blocked sources, last runs, review queue, model spend):

```bash
docker compose run --rm web bin/rails data_quality:status
```

**Guards (#81):**
- **One run per source kind at a time.** `Pipeline.run` holds a Postgres advisory lock, and a second
  run stops with `Pipeline::AlreadyRunning`. `RunJob` also limits concurrency per source kind in Solid Queue.
- **No stuck runs.** Each run first marks runs of its source kind left "running" for over 2 hours as
  failed ("Abandoned…").
- **Spend guard.** Before every model call, this month's model cost (from `crawl_runs.stats`) is checked
  against `DATA_QUALITY_MONTHLY_BUDGET` (default $5; a non-number or negative value is a configuration
  error). Once it's used up, calls are refused with `Budget::Exceeded` and the run fails with that
  reason. It's a soft limit: calls already in flight still finish, so spend can pass it by a fraction
  of a cent per concurrent run. The OpenRouter key's own credit limit is the hard stop.

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
- **Titles:** a fetched HTML page's `<title>` (or `og:title`) becomes `sources.title`. For sources that
  were never fetched (e.g. the hand-checked seed), run the one-off
  `bin/rails data_quality:backfill_titles`: one polite fetch per untitled URL, keeping only the title.
  A page without one (a PDF) gets "site, date", and a block leaves the title empty.

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
the plug-in flagged them). Match links the ones it can to directory records (`matched`). Verify then
recommends or sends to review; a human publishes (`merged`) from the admin. See "Matching and
candidate payloads" below for match's outcomes.

## Verify recommends; a human publishes

Tosin approves everything that goes public. Verify (`stages/verify.rb`) never writes to the directory.
For each `new` or `matched` candidate:

1. **Code checks first**, with no model call. These go to `needs_review`, with the reason in `notes`:
   - its record was rejected or unpublished by a human after match attached it
   - it disagrees with a human-verified value on its record ("human-verified state is NJ; this source
     says DE"; names aren't compared)
   - its quote isn't in the source as stored. Each plug-in defines that: `quote_in_source?`, by default
     the page's visible text, and for NRC a whole table row
2. **The verifier agent** (`Verifiers::Agent`, `OPENROUTER_VERIFY_MODEL`, prompt `verify-v2`) reads the
   claim (`Claim.describe`) against an excerpt (`verification_context`; for NRC the header and the row),
   15 claims per call. All model calls happen before anything is written.
   - supported and at least 80% sure: **`ai_recommendation: "recommend_publish"`**; the candidate stays
     `new`/`matched` and the fact stays pending
   - anything else: `needs_review`, with the model's reason
   - it never rejects on its own

The recommendation lives on the candidate: `ai_recommendation`, `ai_reason`, `ai_confidence`, `ai_model`,
`ai_checked_at` and `verify_run`. `Candidate.recommended` lists those waiting for approval, indexed by
recommendation and run.

## Review: how a human decides (`review.rb`, #85)

The admin (#86) calls only `DataQuality::Review`; it never touches candidates, FactWriter or directory
models. Every action takes `by: "human:…"` (anything else raises) and returns results with `errors`
rather than raising, e.g. when an edit would duplicate another fact.

| Call | What it does |
|---|---|
| `candidates(queue: :recommended \| :needs_review, run_id:, reason:)` | What to decide on, oldest first. Each item has the claim, quote, source, the AI's recommendation and, for a conflict, `differences` (`{ "state" => ["NJ", "DE"] }`, human-verified vs this source) |
| `reasons(queue:, run_id:)` | Kinds of question in a queue, for the reason filter |
| `approve(ids, by:)` | Publishes each in one FactWriter write as a human (not protected): the fact, its evidence (the verifier's confidence, the verify run) and `verification: { status: "verified", by:, context: { candidate_id, crawl_run_id } }`. An approved unit fills its site's blank fields |
| `edit_and_approve(id, attributes:, by:)` | Changes values, then approves. Link ends and slug can't be edited; a failed publish keeps the original values |
| `reject(ids, by:, reason:)` | Rejects candidates, and the record match proposed only for one of them |
| `pending_facts(kind:)` | Directory facts waiting for a human that no open candidate covers (e.g. seed facts loaded as pending), with their evidence's sources |
| `approve_fact`, `reject_fact`, `unpublish(type:, id:, by:, reason:)` | Decide on a directory fact. `approve_fact` takes edited `attributes` and also republishes |
| `history(type:, id:)` | Every decision on a fact, newest first |

Candidates record `reviewed_by` / `reviewed_at`; facts record each decision in the audit trail.

**NRC extract.** The extractor model (`OPENROUTER_EXTRACT_MODEL`, prompt `nrc-extract-v1`) reads the
reactor table as plain lines and returns each unit with its row quoted. Every answer is checked
against the exact parse of the table, by docket. Candidates always carry the table's values; a unit
the model got wrong, misquoted or skipped goes to review with both values in `notes`, and units it
invents are dropped. The tally is in the extract run's `stats["ai_check"]`, so the model's accuracy
is measured on a source we can check before it's trusted on messier ones. Per unit: the unit
(`facility`), its operator (`organization`, one per name) and an `operates` link. The unit's `state` is
evidence, not the final word: NRC's Location measures from a nearby city, which near a border is in
another state (Salem and Hope Creek are in NJ, listed from "Wilmington, DE"; Catawba SC; Fermi 2 MI).
EIA's plant state will win for that field (Tosin's decision). That's planned in the EIA plug-in (#72,
not merged yet); until then NRC's state is stored as is.

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
which returns a result: `ok?` with a plain `SourceRef` in `ref`, or `errors`. Only absolute http(s)
URLs are accepted (no `javascript:`, `data:` or relative paths), since sources are shown as links.

## Matching and candidate payloads

Extract writes `candidates` (`kind`, `payload`, `quote`, `source_id`). Match
([`stages/match.rb`](stages/match.rb)) then links each one to the directory:

| Outcome | When | Candidate becomes |
|---|---|---|
| **Found** | exact NRC docket, domain, or name/alias (normalized) | `matched`, subject = that record. Nothing is written yet: when a human approves it, the quote is added as evidence and an organization gains the name as an alias (its own name is kept). If it disagrees with a human-verified value, verify sends it to review with both values; approving it then applies the new value, since the approver is a human. A record that was rejected or unpublished is never changed or attached to: the candidate goes to review, with who decided and when. |
| **Not found** | nothing exact and nothing similar | `matched`, subject = a new **pending** record with the quote as evidence |
| **New unit of a known site** | an NRC unit (has a docket) whose only similar record is a site (no docket, no parent) that covers it | `matched`, subject = a new **pending** unit with `parent_id` = the site |
| **Ambiguous** | identifiers point at different records, or a similar record exists | `needs_review`, with the reason in `notes`. Never merged automatically. |

"Similar" means the same leading distinctive word, ignoring unit numbers and
generic words ("Vogtle 3" vs "Plant Vogtle Units 3 & 4", "Southern Nuclear
Operating Co." vs "Southern Company"). Facilities with different NRC dockets
are never similar, so "Braidwood 2" isn't flagged against "Braidwood 1".
Evidence from match is `found_by: crawler` with no confidence; when a human
approves, the evidence gets the verifier's confidence (if it recommended publishing).

Organizations and facilities are matched first, so links in the same run can
find records proposed a moment earlier.

**Units and sites.** The seed names plants at site level ("Plant Vogtle Units 3
& 4", no docket); the NRC lists units ("Vogtle 3", with a docket). A site
covers the units its name lists ("Units 3 & 4" covers 3 and 4); a name that
lists none ("Susquehanna Steam Electric Station") covers every unit. A unit the
site doesn't cover ("Vogtle 1", or "Palisades" against "Palisades Pioneer Units
1 & 2"), or with more than one possible site, goes to review. When a human
approves a unit, its `state`, `facility_type`, `status` and `country_code`
fill the site's **blank** fields only (FactWriter `fill_blank: true`), with
the unit's quote as evidence; the site's verification is left alone. If the
unit disagrees with a human-reviewed site (e.g. a different state), nothing is
filled and the candidate notes why; the unit stays published.

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
