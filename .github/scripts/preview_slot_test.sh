#!/usr/bin/env bash
# Tests for .github/scripts/preview_holder.jq: who holds the preview slot
# (#328). Run by CI (blueprint job).
set -euo pipefail
cd "$(dirname "$0")/../.."
fail=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }
holder() { jq -r --argjson pr "$1" -f .github/scripts/preview_holder.jq <<< "$2"; }

a='{"number":305,"labeled_at":"2026-10-17T01:00:00Z"}'
b='{"number":324,"labeled_at":"2026-10-17T02:00:00Z"}'

check "free when it's the only labelled PR" "$(holder 324 "[$b]")" ""
check "a newcomer is refused while another PR holds the slot" "$(holder 324 "[$a, $b]")" "305"
check "the holder's push deploys while a newcomer still has its label" "$(holder 305 "[$b, $a]")" ""
check "once the holder merges, closes or loses its label, the next PR may deploy" "$(holder 324 "[$b]")" ""
check "same time: the lower number holds it" \
  "$(holder 400 '[{"number":400,"labeled_at":"2026-10-17T02:00:00Z"},{"number":399,"labeled_at":"2026-10-17T02:00:00Z"}]')" "399"
check "no labelled PRs: free" "$(holder 324 '[]')" ""

exit $fail
