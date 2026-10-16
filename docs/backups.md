# Backups

There are two kinds, so a problem at Render alone can't lose the data.

**Point-in-time recovery, on Render.** The paid database can be rewound to
any moment in the last 3 days (Hobby workspace; 7 on Pro). Database →
Recovery → pick a time. Render creates a *new* database at that moment and
leaves the current one alone; check it, then point the web service's
`DATABASE_URL` at it. Use this for recent mistakes, like a bad migration or a
wrong bulk edit.

**Daily encrypted copy, off Render.** The `nuclear-directory-backup` cron
job (`backup/`) runs every day at 09:00 UTC, one to two hours after the daily
crawl (3 a.m. New York time).
It dumps the database with
`pg_dump`, encrypts the dump with [age](https://age-encryption.org) and
uploads it as a release to the private repo
`tosinoladokun/nuclear-directory-backups`, keeping the newest 14 (two weeks;
backups are ordered by the timestamp in their tag, `backup-YYYY-MM-DDTHHMMZ`). Only the private key decrypts them. It lives in Tosin's password
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
   Environment (so the next daily backup copies the new database).
6. Open a PR that points `render.yaml` at the new database, so the next
   Blueprint sync doesn't switch either one back. Keep the old database
   until that PR has synced and the site and a backup run are confirmed
   working; only then delete it.
