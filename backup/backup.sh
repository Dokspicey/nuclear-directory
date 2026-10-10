#!/usr/bin/env bash
# Dumps the database, encrypts it with age and uploads it as a release asset
# to a private GitHub repo, keeping the newest BACKUP_KEEP releases.
# See "Backups" in README.md.
#
# Env:
#   DATABASE_URL          database to dump
#   BACKUP_AGE_RECIPIENT  age public key (age1...); only its private half decrypts
#   BACKUP_REPO           owner/name of the private backups repo
#   BACKUP_GITHUB_TOKEN   fine-grained token for BACKUP_REPO, Contents read/write
#   BACKUP_KEEP           releases to keep (default 12)
#   BACKUP_OUTPUT_DIR     if set, write the file there and skip GitHub (local tests)
set -euo pipefail

: "${DATABASE_URL:?}" "${BACKUP_AGE_RECIPIENT:?}"
keep="${BACKUP_KEEP:-12}"
stamp="$(date -u +%Y-%m-%dT%H%MZ)"
name="nuclear-directory-${stamp}.dump.age"
dir="${BACKUP_OUTPUT_DIR:-$(mktemp -d)}"
file="${dir}/${name}"

# Exact row counts, printed now and again by restore.sh, so a restore can be
# checked against the database it came from.
row_counts() {
  psql "$1" --no-psqlrc --quiet --tuples-only --no-align --field-separator=' ' --command "
    SELECT table_name,
           (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM public.%I', table_name), false, true, '')))[1]::text
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER BY table_name"
}

echo "Row counts at backup time:"
row_counts "$DATABASE_URL"

# Custom format (compressed, restorable with pg_restore). The plain dump only
# ever exists in the pipe; only the encrypted file touches disk.
pg_dump --format=custom --no-owner --no-acl "$DATABASE_URL" | age --encrypt --recipient "$BACKUP_AGE_RECIPIENT" --output "$file"
echo "Wrote ${name} ($(du -h "$file" | cut -f1))"

if [[ -n "${BACKUP_OUTPUT_DIR:-}" ]]; then
  exit 0
fi

: "${BACKUP_REPO:?}" "${BACKUP_GITHUB_TOKEN:?}"
api() {
  curl --fail-with-body --silent --show-error --retry 3 \
    -H "Authorization: Bearer ${BACKUP_GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

tag="backup-${stamp}"
release_id="$(api -X POST "https://api.github.com/repos/${BACKUP_REPO}/releases" \
  -d "$(jq -n --arg tag "$tag" '{tag_name: $tag, name: $tag, body: "Encrypted pg_dump (custom format). Decrypt with the age key in the password manager; see README \"Backups\"."}')" \
  | jq -r .id)"
api -X POST -H "Content-Type: application/octet-stream" --data-binary @"$file" \
  "https://uploads.github.com/repos/${BACKUP_REPO}/releases/${release_id}/assets?name=${name}" > /dev/null
echo "Uploaded to ${BACKUP_REPO} release ${tag}"

# Prune: keep the newest $keep backup releases, delete the rest and their tags.
api "https://api.github.com/repos/${BACKUP_REPO}/releases?per_page=100" \
  | jq -r --argjson keep "$keep" \
      '[.[] | select(.tag_name | startswith("backup-"))] | sort_by(.created_at) | reverse | .[$keep:][] | "\(.id) \(.tag_name)"' \
  | while read -r id old_tag; do
      api -X DELETE "https://api.github.com/repos/${BACKUP_REPO}/releases/${id}" > /dev/null
      api -X DELETE "https://api.github.com/repos/${BACKUP_REPO}/git/refs/tags/${old_tag}" > /dev/null
      echo "Pruned ${old_tag}"
    done
