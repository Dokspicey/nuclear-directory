#!/usr/bin/env bash
# Who holds the preview slot (#328), for PR $1: prints the holder's number
# if another PR holds it, "unlabelled" if PR $1 no longer has the label (or
# is closed), and nothing if PR $1 may deploy. Exits non-zero if GitHub
# can't be read, so a failure never reads as a free slot. Needs GH_TOKEN and
# GITHUB_REPOSITORY. Used by .github/workflows/preview.yml (admission, then
# again just before the push).
set -euo pipefail
pr="$1"
cd "$(dirname "$0")/../.."

# Assigned on its own line: a failure inside a for loop's word list wouldn't
# stop the script, and an empty list would read as "free".
open_prs="$(gh api "repos/${GITHUB_REPOSITORY}/issues?labels=preview&state=open&per_page=100" --jq '.[] | select(.pull_request) | .number')"
if ! grep -qx "$pr" <<< "$open_prs"; then
  echo unlabelled
  exit 0
fi
labelled="[]"
for n in $open_prs; do
  at="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${n}/events?per_page=100" \
    --jq '[.[] | select(.event == "labeled" and .label.name == "preview") | .created_at] | last // empty' | tail -n 1)"
  labelled="$(jq -c --argjson n "$n" --arg at "$at" '. + [{number: $n, labeled_at: $at}]' <<< "$labelled")"
done
jq -r --argjson pr "$pr" -f .github/scripts/preview_holder.jq <<< "$labelled"
