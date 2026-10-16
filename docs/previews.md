# UI previews

To see a pull request's UI before it merges, add the **preview** label to the
PR. A workflow (`.github/workflows/preview.yml`) points the `preview` branch
at the PR's latest commit and comments the link,
https://nuclear-directory-preview.onrender.com. New pushes to a labelled PR
update the preview. It shows the PR merged with the current `main`. There's
one preview at a time: labelling another PR replaces it. Removing the label
only stops further updates; the preview stays live until another PR is
labelled.

The preview is a free Render instance (`nuclear-directory-preview` in
`render.yaml`), so it costs nothing, sleeps after 15 minutes idle and takes
about a minute to wake. Every start runs `backend/bin/preview-start`, which
empties the preview database (dropping and recreating its `public` schema) and
reloads schema and seed. It refuses any database but
`nuclear_directory_preview`. It's kept apart from the live site:

- **Its own database.** `nuclear_directory_preview` on the same Postgres
  server, owned by the `preview_app` role. That role can't connect to the
  production database (`CONNECT` is revoked from `PUBLIC` there), has a
  connection limit of 3 and a 5-second statement timeout, so it can't hog
  the server.
- **No production secrets.** It has its own `SECRET_KEY_BASE` and no master
  key, OpenRouter, Sentry or PostHog keys. No background jobs run (no
  `SOLID_QUEUE_IN_PUMA`), so no crawler.
- **Not indexed.** `NOINDEX=1` adds `X-Robots-Tag: noindex, nofollow` to
  every response, and `robots.txt` disallows everything.

**Admin on the preview.** Each start also makes an admin login,
`preview@nuclear-directory.org`, from `PREVIEW_ADMIN_PASSWORD`
(`bin/rails preview:admin`), so admin screens can be tried there. That task
refuses to run unless `NOINDEX=1` and the database is
`nuclear_directory_preview`. If the variable isn't set, the preview starts
without an admin. To set it: generate a password in the password manager as
"Nuclear Directory preview admin", then Render → `nuclear-directory-preview` →
Environment → `PREVIEW_ADMIN_PASSWORD`. Never reuse the live admin's
password.

CI (`.github/scripts/check_blueprint.rb`) fails if the preview's
`DATABASE_URL` stops being a hand-set value, if it gains a production secret,
if `NOINDEX` goes missing, or if `PREVIEW_ADMIN_PASSWORD` appears on any other
service.

UI PRs also include phone (390px) and desktop screenshots of the changed pages
in the description, so most changes can be reviewed without the preview.

**One-time setup (done 11 Oct 2026).** In psql as the database owner:
create the `preview_app` role (`CONNECTION LIMIT 3`, `statement_timeout` 5s),
create `nuclear_directory_preview` owned by it, and revoke `CONNECT` from
`PUBLIC` on both databases. The exact SQL and its undo are in the PR that
added previews. Then set the preview service's `DATABASE_URL` in Render to
`postgres://preview_app:<password>@<internal host>/nuclear_directory_preview`.
`<internal host>` is the host in the database's **Internal** Database URL.
The password lives only in the password manager and that Render setting.
