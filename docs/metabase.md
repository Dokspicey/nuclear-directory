# Metabase (local, read-only on production)

Metabase runs on Tosin's Mac in Docker, reading production through a role
that can't write. It never runs on Render. Production's database accepts
connections from the internet only from the one IP address in `render.yaml`,
and only over SSL.

**1. Create the read-only role** (once, and again after any restore from a
backup, which doesn't carry roles). The task below is part of the app, so
run it only after the deploy that added it has finished:

1. In the password manager, generate a password of 32 or more characters for
   a new entry, "Nuclear Directory metabase_ro".
2. On Render, open the web service → Shell and run:

   ```bash
   bin/rails metabase:create_readonly_role
   ```

   Paste the password twice when asked; nothing is shown as you paste. Use
   the prompt, never the password on the command line, so it stays out of
   the shell's history; only a SCRAM hash of it is sent to Postgres. It
   creates `metabase_ro`, which can read the directory's tables but not
   `users`, `sessions`, `correction_reports` or Rails' `solid_*` job and
   cache tables. Its transactions are read-only by default, and it has no
   write permissions at all, so it can't change anything even with that
   default turned off. Running it again updates the password and resets
   the grants from scratch, so a right granted by hand in between doesn't
   survive. Tables are granted when it runs, so after a migration adds a
   table you want in Metabase, run it again (check first that the new table
   holds nothing private; if it does, add it to `PRIVATE_TABLES`).

**2. Allow your IP address.** `render.yaml` lists one address under the
database's `ipAllowList`. When your home IP changes, Metabase times out
connecting. Get the new one with `curl -4 ifconfig.me`, replace the `/32` in
`render.yaml` and merge that PR; the Blueprint applies it within a minute.
To close access again, set `ipAllowList: []`. Never delete the key: Render
would then open the database to everyone.

**3. Start Metabase.** The first time, make its encryption key. Metabase
uses it to encrypt the database password it saves, so the password isn't
readable in its files. From the repo root:

```bash
printf 'MB_ENCRYPTION_SECRET_KEY=%s\n' "$(openssl rand -base64 32)" > .env.metabase
```

Copy the line from `.env.metabase` into the password manager entry too:
without the key, a restored copy of Metabase can't read its saved settings.
`.env.metabase` is gitignored. Then, and every time after:

```bash
docker compose -f docker-compose.metabase.yml --env-file .env.metabase up -d
```

Open <http://localhost:3030> and create the local admin account (it exists
only on this Mac). Then Admin → Databases → Add database:

| Field | Value |
|---|---|
| Database type | PostgreSQL |
| Host | the hostname from the database's **External** Database URL on Render |
| Port | 5432 |
| Database name | `nuclear_directory_production` |
| Username | `metabase_ro` |
| Password | from the password manager |
| Use a secure connection (SSL) | on |

Add only this database: not `nuclear_directory_preview`, and never with the
main `nuclear_directory` user.

**4. Starter questions.** `ops/metabase/questions/` has SQL for companies
by status, sites and units by status, pending facts by reason, candidates
per run and AI recommendation, facts per source, crawl runs, AI spend per
month and power reactor units missing capacity. In
Metabase: New → SQL query, paste a file, save.

**5. Claude Code (MCP).** Metabase has its own MCP server. Turn it on under
Admin → AI → MCP, then run once:

```bash
claude mcp add --scope local --transport http metabase-local http://localhost:3030/api/metabase-mcp
```

In Claude Code, run `/mcp`, pick `metabase-local` and choose Authenticate;
Metabase asks you to approve it in the browser. It signs in as your local
Metabase user, so no key is stored, and the setting lives in your own
`~/.claude.json`, not in this repo. Use this server for this data, not the
Metabase connector on your claude.ai account.

**Stop it** with `docker compose -f docker-compose.metabase.yml --env-file
.env.metabase down`; your questions stay in the `metabase-data` volume
(`down -v` deletes them).
