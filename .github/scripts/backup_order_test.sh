#!/usr/bin/env bash
# Tests for backup/newest_backup.jq and backup/prune_backups.jq: the backups
# must be ordered by their tag's timestamp, never by GitHub's created_at (the
# tagged commit's date, the same for every backup). Run by CI (blueprint job).
set -euo pipefail
cd "$(dirname "$0")/../.."
fail=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }

# All releases share one created date, as on GitHub; listed newest-first is
# not guaranteed, so they're shuffled here.
cli='[
  {"tagName":"backup-2026-10-11T1000Z","isDraft":false,"createdAt":"2026-10-10T16:24:59Z"},
  {"tagName":"backup-2026-10-13T0240Z","isDraft":false,"createdAt":"2026-10-10T16:24:59Z"},
  {"tagName":"backup-2026-10-20T1000Z","isDraft":true, "createdAt":"2026-10-10T16:24:59Z"},
  {"tagName":"v1","isDraft":false,"createdAt":"2027-01-01T00:00:00Z"},
  {"tagName":"backup-2026-10-10T1751Z","isDraft":false,"createdAt":"2026-10-10T16:24:59Z"}]'
check "newest published backup, ignoring drafts and other tags" \
  "$(jq -r -f backup/newest_backup.jq <<< "$cli")" "backup-2026-10-13T0240Z"
check "no backups gives nothing" "$(jq -r -f backup/newest_backup.jq <<< '[]')" ""

rest='[
  {"id":2,"tag_name":"backup-2026-10-11T1000Z","draft":false,"created_at":"2026-10-10T16:24:59Z"},
  {"id":4,"tag_name":"backup-2026-10-18T1000Z","draft":false,"created_at":"2026-10-10T16:24:59Z"},
  {"id":1,"tag_name":"backup-2026-10-10T1751Z","draft":false,"created_at":"2026-10-10T16:24:59Z"},
  {"id":9,"tag_name":"backup-2026-10-25T1000Z","draft":true, "created_at":"2026-10-10T16:24:59Z"},
  {"id":3,"tag_name":"backup-2026-10-13T0240Z","draft":false,"created_at":"2026-10-10T16:24:59Z"},
  {"id":7,"tag_name":"v1","draft":false,"created_at":"2026-10-10T16:24:59Z"}]'
check "keep 2: prune the two oldest backups only, oldest first" \
  "$(jq -r --argjson keep 2 -f backup/prune_backups.jq <<< "$rest" | tr '\n' ' ')" "1 backup-2026-10-10T1751Z 2 backup-2026-10-11T1000Z "
check "keep 12: prune nothing" "$(jq -r --argjson keep 12 -f backup/prune_backups.jq <<< "$rest")" ""

exit $fail
