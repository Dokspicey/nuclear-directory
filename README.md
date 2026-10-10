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
Pushes to `main` deploy only after CI passes.

**First deploy.** In the Render dashboard: New → Blueprint, pick this repo,
fill in the secrets it asks for, then Apply. Render creates the database and
the web service and deploys `main`. The app is at
`https://nuclear-directory.onrender.com` (or the URL Render shows).

**Seed production once**, after the first deploy succeeds. Open the web
service → Shell and run:

```bash
bin/rails db:seed
```

It loads the same verified seed as development and is safe to re-run.

**Secrets** live only in the Render dashboard (web service → Environment),
never in git: `RAILS_MASTER_KEY` (the contents of `backend/config/master.key`),
`OPENROUTER_API_KEY`, `OPENROUTER_EXTRACT_MODEL`, `OPENROUTER_VERIFY_MODEL`,
`DATA_QUALITY_MONTHLY_BUDGET`, `POSTHOG_API_KEY` and `POSTHOG_HOST`.
`DATABASE_URL` is filled in by Render from the database. Render asks for the
secrets only when the Blueprint is first created; change them later under
Environment (saving restarts the service). Adding a new secret means adding it
to `render.yaml` with `sync: false` and then setting its value in the
dashboard.

**Roll back.** Web service → Events (or Deploys), find the last good deploy and
choose Rollback. This redeploys that image; it does not undo database
migrations, so a migration that must be reversed needs a new commit. Render
turns off auto-deploy after a rollback; turn it back on (Settings → Auto-Deploy:
"After CI checks pass") once the fix is on `main`. To restore data, paid
Render Postgres offers point-in-time recovery (database → Recovery).

## Starting over

To wipe the database and installed gems:

```bash
docker compose down -v
```
