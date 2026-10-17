#!/usr/bin/env bash
# Tests for .github/scripts/preview_holder.jq: who holds the preview slot
# (#328). Run by CI (blueprint job).
set -euo pipefail
cd "$(dirname "$0")/../.."
fail=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }
holder() { jq -r --argjson pr "$1" -f .github/scripts/preview_holder.jq <<< "$2"; }

pr() { printf '{"number":%s,"state":"%s","pull_request":{},"labels":[%s]}' "$1" "$2" "$3"; }
preview='{"name":"preview"}'
other='{"name":"area:infra"}'

check "free when no other PR has the label" "$(holder 324 "[$(pr 324 open "$preview"), $(pr 300 open "$other")]")" ""
check "held by another open PR with the label" "$(holder 324 "[$(pr 324 open "$preview"), $(pr 305 open "$preview")]")" "305"
check "the holder's own push isn't blocked by itself" "$(holder 305 "[$(pr 305 open "$preview")]")" ""
check "a closed or merged PR frees the slot" "$(holder 324 "[$(pr 324 open "$preview"), $(pr 305 closed "$preview")]")" ""
issue='{"number":9,"state":"open","labels":[{"name":"preview"}]}'
check "an issue with the label isn't a PR" "$(holder 324 "[$(pr 324 open "$preview"), $issue]")" ""

exit $fail
