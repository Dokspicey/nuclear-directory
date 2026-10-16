# Deploying to Render

Production runs on [Render](https://render.com), described in `render.yaml`
(a Render "Blueprint"): one web service built from `backend/Dockerfile` and
one Postgres 16 database, both in Oregon. Solid Queue runs inside Puma
(`SOLID_QUEUE_IN_PUMA=true`), so there is no separate worker.

**Memory.** The web service is a 512 MB instance running the site and the
background jobs (Solid Queue inside Puma). To fit, Puma runs in single mode,
Solid Queue in async mode (its dispatcher, worker and scheduler are threads in
the same process, not forks; `config/puma.rb`, `SOLID_QUEUE_MODE=fork` undoes
it) and jemalloc returns freed memory quickly (`MALLOC_CONF`). Because Puma and
the job threads share one database pool in async mode, `DB_POOL=12` sizes it so
a long crawl never leaves web requests waiting for a connection. Idle it uses
about 130 MB instead of 280 MB. To check: Render → web service → Metrics →
Memory, and Events, which shows "ran out of memory" if it ever restarts.

**Every deploy** builds the image, runs `bin/rails db:migrate`, then starts
the new version and switches traffic once `/up` returns 200. If the build,
the migration or the health check fails, the old version keeps serving.
Pushes to `main` that change `backend/` deploy only after CI passes.

Migrations run against the live database while the old version is still
serving, and a failed deploy doesn't undo a migration that already ran. So
every migration must also work with the code currently in production:
add columns and tables first, and remove or rename them in a later deploy,
once nothing reads them.

**First deploy.** In the Render dashboard: New → Blueprint, pick this repo,
fill in the secrets it asks for, then Apply. Render creates the database and
the web service and deploys `main`. The app is at `https://nuclear-directory.org`
once its DNS points at Render (see Domain below). The
`nuclear-directory.onrender.com` address is turned off in `render.yaml`; to
check a fresh setup before DNS is in place, set `renderSubdomainPolicy:
enabled` until the domain verifies.

**Seed production** after the first deploy succeeds, and again after each
deploy that changes `backend/db/seeds.rb` or `backend/db/seeds/`. Deploys
don't seed on their own. Open the web service → Shell and run:

```bash
bin/rails db:seed
```

It loads the same verified seed as development and is safe to re-run.

**Secrets** live only in the Render dashboard (web service → Environment),
never in git: `RAILS_MASTER_KEY` (the contents of `backend/config/master.key`),
`OPENROUTER_API_KEY`, `POSTHOG_API_KEY`, `POSTHOG_HOST` (optional) and
`SENTRY_DSN`.
`DATABASE_URL` is filled in by Render from the database. The model ids and
`DATA_QUALITY_MONTHLY_BUDGET` aren't secret, so they're set in `render.yaml`;
change them there in a PR. Render asks for the
secrets only when the Blueprint is first created; change them later under
Environment (saving restarts the service). Adding a new secret means adding it
to `render.yaml` with `sync: false` and then setting its value in the
dashboard.

**Domain.** `nuclear-directory.org` is the web service's custom domain
(`domains` in `render.yaml`; Render adds `www`, which redirects to it). The
`nuclear-directory.onrender.com` address is turned off
(`renderSubdomainPolicy: disabled`), so the site has one public address. DNS is
at Namecheap: the bare domain is an ALIAS to `nuclear-directory.onrender.com`
(or an A record to `216.24.57.1`) and `www` is a CNAME to
`nuclear-directory.onrender.com`. The iCloud
mail records (MX, SPF and `apple-domain` TXT, `sig1._domainkey`, `_dmarc`)
live alongside them and must not be changed. Cutover steps and the old values
are in issue #57.

**Errors and uptime.** Errors go to Sentry once `SENTRY_DSN` is set; until
then nothing is sent. Visitor data stays out: no IPs, cookies, form or request
bodies, search queries, SQL or job arguments (see
`backend/config/initializers/sentry.rb`). Setting it up is a one-time job in
Sentry (issue #102, section F): create the project, turn on "Prevent Storing
of IP Addresses", add `SENTRY_DSN` to the web service's Environment, and add
an uptime monitor that checks `/up` every 5 minutes and emails
hello@nuclear-directory.org when it fails.

**Roll back.** Web service → Events (or Deploys), find the last good deploy and
choose Rollback. This redeploys that image; it does not undo database
migrations, so a migration that must be reversed needs a new commit. Render
turns off auto-deploy after a rollback; turn it back on (Settings → Auto-Deploy:
"After CI checks pass") once the fix is on `main`. To restore data, paid
Render Postgres offers point-in-time recovery (see [Backups](backups.md)).
