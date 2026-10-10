# nuclear-directory

[![CI](https://github.com/tosinoladokun/nuclear-directory/actions/workflows/ci.yml/badge.svg)](https://github.com/tosinoladokun/nuclear-directory/actions/workflows/ci.yml)

Open directory and relationship map of the US nuclear industry supply chain.

## Layout

- `backend/` — Rails 8 app (Ruby 3.3, Postgres 16, Hotwire, Tailwind)
- `docker-compose.yml` — local development: `db` (Postgres) and `web` (Rails)

Background jobs use Solid Queue, which stores jobs in Postgres (no Redis).
In development the job worker runs inside the web process.

## Run it

You only need [Docker](https://www.docker.com/products/docker-desktop/).

```bash
cp .env.example .env
```

```bash
docker compose run --rm web bin/rails db:prepare
```

```bash
docker compose up
```

Then open http://localhost:3000. Stop with `Ctrl+C`; add `-d` to `up` to run it
in the background and `docker compose down` to stop it.

`db:prepare` creates the database, runs migrations and, on first setup, loads
the seed data. Rerun it after pulling new migrations.

The seed data is the roles and technologies lists plus 45 hand-checked
organizations, one YAML file each in `backend/db/seeds/organizations/`. Every
fact in them is loaded as verified, with its source and quote as evidence.
After changing `backend/db/seeds.rb` or those files, reload the seeds (safe to
re-run):

```bash
docker compose run --rm web bin/rails db:seed
```

## Run the tests

```bash
docker compose run --rm web bin/rails db:test:prepare test
```

CI runs the same tests plus RuboCop (the style checker) on every pull
request and on `main`. Run the linter locally with:

```bash
docker compose run --rm web bin/rubocop
```

Tests use a separate `nuclear_directory_test` database, so they never touch
development data.

## Open a console

Rails console:

```bash
docker compose run --rm web bin/rails console
```

Postgres shell:

```bash
docker compose exec db psql -U postgres nuclear_directory_development
```

## Configuration

Settings live in `.env` (gitignored). See `.env.example` for the full list:
`DATABASE_URL`, `OPENROUTER_API_KEY` and the OpenRouter model ids. Never
commit real keys.

`backend/config/master.key` decrypts `backend/config/credentials.yml.enc`. It
is gitignored; keep a copy in a password manager.

## Deploying to Render

Production runs on [Render](https://render.com), described in `render.yaml`
(a Render "Blueprint"): one web service built from `backend/Dockerfile` and
one Postgres 16 database, both in Oregon. Solid Queue runs inside Puma
(`SOLID_QUEUE_IN_PUMA=true`), so there is no separate worker.

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
the web service and deploys `main`. The app is at
`https://nuclear-directory.onrender.com` (or the URL Render shows).

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
Render Postgres offers point-in-time recovery (see Backups below).

## Backups

There are two kinds, so a problem at Render alone can't lose the data.

**Point-in-time recovery, on Render.** The paid database can be rewound to
any moment in the last 3 days (Hobby workspace; 7 on Pro). Database →
Recovery → pick a time. Render creates a *new* database at that moment and
leaves the current one alone; check it, then point the web service's
`DATABASE_URL` at it. Use this for recent mistakes, like a bad migration or a
wrong bulk edit.

**Weekly encrypted copy, off Render.** The `nuclear-directory-backup` cron
job (`backup/`) runs every Sunday at 10:00 UTC. It dumps the database with
`pg_dump`, encrypts the dump with [age](https://age-encryption.org) and
uploads it as a release to the private repo
`tosinoladokun/nuclear-directory-backups`, keeping the newest 12 (about three
months). Only the private key decrypts them. It lives in Tosin's password
manager, never in git or on Render; `render.yaml` holds just the public key.
If that key is lost, so are the backups. The job's log on Render lists every
table's row count at backup time. Run it on demand with Cron job → Trigger
Run. A failed run shows in the cron job's Events, and Render emails about
failures if Workspace Settings → Notifications has them on (the default).

The upload uses `BACKUP_GITHUB_TOKEN`, a fine-grained GitHub token that can
only write to the backups repo. The repo needs at least one commit (create
it with a README), since releases need something to tag. The token expires after a year; make a new one the
same way and replace it under the cron job's Environment.

**Test a restore** (do this after setting up backups, and every few months).
It needs Docker, the GitHub CLI signed in (`gh auth login`) and this repo:

1. Copy the backup key from the password manager: the whole entry, as
   `age-keygen` wrote it (comment lines and the `AGE-SECRET-KEY-1…` line).
2. From the repo root, run:

   ```bash
   backup/restore-latest
   ```

   This downloads the newest backup, restores it into a fresh local database
   called `nuclear_directory_restore_test` and prints row counts. The key
   goes from the clipboard straight into the container and is never saved.
   Pass a release tag (`backup/restore-latest backup-2026-10-11T1000Z`) to
   restore an older one.
3. Compare the counts with the ones in that run's log on Render. They should
   match exactly.

**Restore into production.** Only when Render's own recovery can't help, for
example because the data needed is older than 3 days. It restores into a new
database, then switches the app over, so the current one is untouched until
the end. Same tools as the restore test, run from a Mac:

1. On Render: New → Postgres. Name `nuclear-directory-db-restored`, Postgres
   16, Oregon, same plan as the current one. When it's ready, open its Access
   Control and add your current IP address (only that one).
2. Copy its **External** Database URL and, in Terminal, run
   `export RESTORE_TARGET_URL="$(pbpaste)"`. This keeps the URL out of your
   shell history.
3. Copy the backup key from the password manager, then run
   `backup/restore-latest` (or `backup/restore-latest <release-tag>` for an
   older backup). It refuses a database that already has tables.
4. Check the row counts against that backup run's log on Render, then remove
   your IP from the new database's Access Control and run
   `unset RESTORE_TARGET_URL`.
5. Set `DATABASE_URL` to the new database's **Internal** Database URL in
   both places that use it, and save each: the web service's Environment
   (it restarts on it) and the `nuclear-directory-backup` cron job's
   Environment (so the next weekly backup copies the new database).
6. Open a PR that points `render.yaml` at the new database, so the next
   Blueprint sync doesn't switch either one back. Keep the old database
   until that PR has synced and the site and a backup run are confirmed
   working; only then delete it.

## Starting over

To wipe the database and installed gems:

```bash
docker compose down -v
```
