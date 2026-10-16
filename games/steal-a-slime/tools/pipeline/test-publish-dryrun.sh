#!/usr/bin/env bash
# Dry-run tests for the newest-only rule in publish.sh. Uses temp STATUS_DIR /
# STUDIO_REPORTS_DIR, real shas from the first-parent history of MAIN_REF
# (default origin/main) and DRY_RUN=1: no network, no writes outside the temp dir.
#   tools/pipeline/test-publish-dryrun.sh [checkout-dir]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKOUT="${1:-$(git -C "$HERE" rev-parse --show-toplevel)}"
export MAIN_REF="${MAIN_REF:-origin/main}"
mapfile -t SHAS < <(git -C "$CHECKOUT" rev-list --first-parent "$MAIN_REF" | head -4)
[[ ${#SHAS[@]} -ge 3 ]] || { echo "need >=3 commits on $MAIN_REF"; exit 2; }
NEW="${SHAS[0]}" MID="${SHAS[1]}" OLD="${SHAS[2]}"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export STATUS_DIR="$T/status" STUDIO_REPORTS_DIR="$T/reports" LIVE_DIR="$T/live" DRY_RUN=1 AUTO_PUBLISH=1
fails=0
reset() { rm -rf "$STATUS_DIR" "$STUDIO_REPORTS_DIR" "$LIVE_DIR"; mkdir -p "$STATUS_DIR" "$STUDIO_REPORTS_DIR"; }
cloud() { echo "{\"status\":\"$2\",\"finished\":\"$(date -Iseconds)\"}" >"$STATUS_DIR/$1.json"; }
run() { OUT="$(SUPERSEDE_ONLY="${SO:-0}" "$HERE/publish.sh" "$CHECKOUT" "$1" 2>&1)"; RC=$?; }
check() { # check <name> <expected rc> <grep pattern|-> 
  if [[ $RC == "$2" ]] && { [[ "$3" == - ]] || grep -q -- "$3" <<<"$OUT"; } && { [[ -z "${4:-}" ]] || ! grep -q -- "$4" <<<"$OUT"; }; then
    echo "ok   $1 (rc=$RC)"
  else echo "FAIL $1 (rc=$RC, want $2 /$3/)"; sed 's/^/     /' <<<"$OUT"; fails=$((fails + 1)); fi
}

reset; cloud "$NEW" pass; cloud "$OLD" pass
run "$OLD"; check "older passing sha is superseded by newest" 4 "superseded_by=$NEW"
[[ ! -e "$STATUS_DIR/$OLD.publish.json" ]] && echo "ok   dry-run wrote no publish.json" || { echo "FAIL dry-run wrote a file"; fails=$((fails + 1)); }

reset; cloud "$MID" pass; cloud "$OLD" pass # newest has no status yet -> next newer passed wins
run "$OLD"; check "superseded by nearest passed newer sha (newest has no status)" 4 "superseded_by=$MID"

reset; cloud "$NEW" fail; cloud "$OLD" pass
run "$OLD"; check "newer sha with cloud fail does not supersede" 3 "blocked: " "skipped-superseded: newer"

reset; cloud "$OLD" pending; cloud "$NEW" pass
run "$OLD"; check "pending older sha superseded" 4 "superseded_by=$NEW"

reset; cloud "$NEW" pass
run "$OLD"; check "older sha without any status superseded" 4 "superseded_by=$NEW"

reset; cloud "$NEW" pass; echo '{"status":"live"}' >"$STATUS_DIR/$OLD.publish.json"
run "$OLD"; check "already live sha left alone" 3 "blocked: no cloud-test status" "skipped-superseded: newer"

reset; cloud "$NEW" pass; echo '{"status":"no-publish"}' >"$STATUS_DIR/$OLD.publish.json"; cloud "$OLD" pass
run "$OLD"; check "no-publish sha left alone" 3 "blocked:" "skipped-superseded: newer"

reset; cloud "$NEW" pass; echo '{"status":"ready"}' >"$STATUS_DIR/$OLD.publish.json"; cloud "$OLD" pass
run "$OLD"; check "ready sha is superseded" 4 "superseded_by=$NEW"

reset; cloud "$NEW" pass; cloud "$OLD" pass
SO=1 run "$OLD"; check "SUPERSEDE_ONLY still marks superseded" 4 "superseded_by=$NEW"

reset; cloud "$NEW" pass; cloud "$MID" pass
SO=1 run "$NEW"; check "newest sha is never superseded (SUPERSEDE_ONLY)" 0 - "skipped-superseded: newer"

reset; cloud "$NEW" pass
run "0000000000000000000000000000000000000000"; check "sha not on main first-parent line is not marked" 3 "blocked: no cloud-test" "skipped-superseded: newer"

reset
run "$NEW"; check "default report timeout is 1800s" 3 "blocked: no cloud-test"
grep -q 'REPORT_TIMEOUT_S="${REPORT_TIMEOUT_S:-1800}"' "$HERE/publish.sh" && echo "ok   REPORT_TIMEOUT_S default 1800" || { echo "FAIL timeout default"; fails=$((fails + 1)); }

if (( fails )); then echo "$fails FAILED"; exit 1; fi
echo "all passed"
