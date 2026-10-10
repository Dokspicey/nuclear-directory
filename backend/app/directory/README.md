# Directory interfaces

`Directory::Lookup` (read) and `Directory::FactWriter` (write) are the **only**
way code outside the directory touches directory data. The data quality
pipeline (`DataQuality::`) and the seed loader both go through them, so there
is one way facts get written. Decision and reasoning: issue #1 (comments),
issue #32.

## Who owns what

| Directory owns | DataQuality owns |
|---|---|
| organizations, organization_aliases, roles, technologies, organization_roles, organization_technologies, facilities, relationships, facility_relationships, evidence | sources, crawl_runs, candidates |

`evidence.source_id` is the one foreign key that crosses the line. Outside the
directory, don't use the directory's models (`Organization`, `Facility`, …)
directly. Call these interfaces instead.

## Directory::Lookup

Returns frozen value objects (`Directory::OrganizationRef`,
`Directory::FacilityRef`), never models, or `nil` when nothing matches. Pass
exactly one keyword.

```ruby
Directory::Lookup.organization(name: "TerraPower, Inc.")   # name or any alias, normalized
Directory::Lookup.organization(domain: "https://www.terrapower.com/news")
Directory::Lookup.organization(slug: "terrapower")
Directory::Lookup.organization(id: 12)

Directory::Lookup.facility(nrc_docket: "05000424")
Directory::Lookup.facility(name: "Plant Vogtle Units 3 & 4")  # case-insensitive
```

- `OrganizationRef`: `id, slug, name, domain, verification_status, verified_by, verified_at`
- `FacilityRef`: `id, slug, name, nrc_docket, parent_id, verification_status, verified_by, verified_at, facility_type, status, state, country_code, latitude, longitude`
- `Directory::Lookup.fact_state(type:, id:)`: any fact's current decision, as `FactStateRef(type, id, name, verification_status, verified_by, verified_at)` (a link's name is a short label)

Every verification status is returned, so check `verification_status` before
treating a match as public.

```ruby
Directory::Lookup.similar_facilities("Vogtle 3")                       # => [FacilityRef, …] (up to 10)
Directory::Lookup.similar_organizations("Southern Nuclear Operating Co.")
```

These find likely duplicates that an exact lookup misses: records that share
the same leading distinctive word, ignoring unit numbers and generic words
like "nuclear", "station" or "company". Used to send a candidate to review
instead of creating a duplicate.

Names are compared after `OrganizationAlias.normalize`: lowercased, `&` becomes
"and", punctuation removed, trailing Inc / LLC / Co / Corp / Ltd and similar
dropped. "TerraPower, LLC" and "terrapower" match.

## Directory::FactWriter

```ruby
result = Directory::FactWriter.write(kind, attributes, evidence: [...], verification: {...})
result.ok?      # true when written
result.id       # the fact's id
result.created  # true if new, false if an existing fact was updated
result.errors   # array of messages; empty when ok
```

A failed write changes nothing and returns errors. It does not raise.

### Kinds

| kind | attributes | an existing fact is found by |
|---|---|---|
| `organization` | `name slug legal_name website domain description hq_city hq_state country_code founded_year status aliases` | name or any alias (normalized), then domain |
| `organization_role` | `organization_id role` (role **key**) | organization + role |
| `organization_technology` | `organization_id technology` (technology **key**) | organization + technology |
| `facility` | `name slug parent_id facility_type status technology reactor_type capacity_mw nrc_docket city state country_code latitude longitude` | NRC docket, then name |
| `relationship` | `from_organization_id to_organization_id relationship_type description started_on ended_on` | from + to + type |
| `facility_relationship` | `organization_id facility_id relationship_type ownership_pct description started_on ended_on` | organization + facility + type |

Pass `id:` to update a fact you already know. Get ids for other records from
`Directory::Lookup`.

- **Organizations**: the name is stored as an alias as well, along with
  `aliases:`. An alias already used by another organization is an error.
  `domain` defaults to the website's; pass `domain: nil` to leave it blank,
  for example when several organizations share one website.
- **Relationship types**: `supplies`, `invests_in` (equity), `funds` (grants
  and awards), `offtake_with`, `subsidiary_of` (child → parent).
- **Facility link types**: `owns`, `operates`, `vendor_for`, `offtakes_from`.

### Filling blanks

`fill_blank: true` sets only the attributes that are blank on an existing
row and leaves the rest alone, e.g. to complete a site's state and status
from one of its units without overwriting what's already there.

### Evidence

Each item: `source_id` (required), `quote`, `found_by` (`crawler`, `verifier`
or `human`), `confidence` (0–1), `crawl_run_id`. Evidence is matched by source
and quote, so writing the same item again updates it and never duplicates it.

### Verification

`verification: { status: "verified", by: "human:tosin", reason: "…", context: { … } }`.
Status is `pending`, `verified`, `rejected` or `unpublished`. `by` (required)
names who decided: `human:<name>` or `agent:verifier/<model>`. `reason` and `context`
(e.g. `{ "candidate_id" => 12, "crawl_run_id" => 4 }`) are optional and go
into the audit trail. Re-applying the same decision keeps the original
`verified_at` and records nothing new. What's public is what the
`.published` scopes return (below).

- **Unpublished** is a human taking a fact off the site (who and when are in
  `verified_by` / `verified_at`). Like `rejected`, it's a closed decision:
  automated writers (`protect_human_verified: true`) can't change the fact at
  all, and match sends a candidate citing it to review ("…which was
  unpublished by human:tosin on 2026-10-10"). A human republishes by writing
  `status: "verified"` again.
- **Only a human** (`by: "human:…"`) can unpublish, or change a fact that's
  rejected or unpublished. Any other write fails with an error. The pipeline
  may still reject, to retire its own proposals.
- **Human actions** (approve, unpublish, republish) are written *without*
  `protect_human_verified`: the human is the authority.

### What's public

Public pages read `<Model>.published`, not `.verified`: a fact is published
when it's verified **and** what it hangs on is published. Unpublishing a
company hides its roles, technologies, relationships and plant links;
unpublishing a site hides its units and their links. Nothing is deleted, and
each fact keeps its own decision, so republishing brings them all back.

One exception for sites (#73): a **pending** site is published once it has a
published unit (a verified unit under a site that isn't rejected or
unpublished), so a site made from NRC units goes public with its first
verified unit. A rejected or unpublished site never shows, whatever its units.

### Bulk writes

`Directory::FactWriter.write_many([{ kind:, attributes:, evidence:, verification:, protect_human_verified: }, …])`
runs a batch (e.g. a bulk approve) in one transaction, each write in its own
savepoint, so one failure doesn't undo the rest. It returns one Result per
write, in order. Each write is audited as usual.

### Audit trail

Every change of a fact's verification is recorded in `verification_events`
(who, when, from → to, reason, context, and the attribute values the same
write changed, before → after), append-only: events can't be edited or
deleted, and they outlive their fact. A human editing values without changing
the decision is recorded too. Decisions on one fact are made one at a time
(the row is locked), so the history is in the order they happened. Read it
with:

```ruby
Directory::Lookup.verification_history(type: "Organization", id: 12)
# => [VerificationEventRef(from_status:, to_status:, by:, reason:, context:, changed_values:, at:), …] newest first
# changed_values: { "hq_state" => ["DE", "WA"] }
```

### Pending facts (the review queue)

Facts waiting for a human's decision (`pending`; never rejected or
unpublished), one kind per call, oldest first:

```ruby
Directory::Lookup.pending_facts(kind: "facility_relationship", after_id: nil, limit: 50)
# => [PendingFactRef(type:, id:, kind:, attributes:, evidence:, created_at:, last_event:), …]
```

- `kind`: one of `Directory::Lookup::FACT_KINDS`. Page with `after_id:` (the
  last id seen).
- `attributes`: the FactWriter attributes as stored (roles and technologies
  as keys), plus the linked records' names (`organization_name`,
  `facility_name`, `from_organization_name`, `to_organization_name`,
  `parent_name`).
- `evidence`: `EvidenceRef(source_id:, quote:, found_by:, confidence:, crawl_run_id:)`.
  Only the source's id: sources belong to the data quality module, which
  resolves URLs and titles.
- `last_event`: the latest `VerificationEventRef`, e.g. why it's waiting.

Candidates aren't consulted: the data quality module leaves out facts an
open candidate already points at. To decide, write the fact as a human:
`FactWriter.write(kind, { id:, … }, verification: { status: "verified", by: "human:tosin", reason:, context: })`.

### Confidence

Recomputed after every write, by one rule in `Evidence.combined_confidence`:
a fact a human has verified scores 1. Otherwise it scores the strongest piece
of evidence, plus 0.1 when sources on two or more domains agree, capped at 1.
