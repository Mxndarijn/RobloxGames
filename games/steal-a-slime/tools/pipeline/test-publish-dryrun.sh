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
export STATUS_DIR="$T/status" STUDIO_REPORTS_DIR="$T/reports" LIVE_DIR="$T/live" NEEDS_REVIEW_DIR="$T/needs-review" DRY_RUN=1 AUTO_PUBLISH=1
fails=0
reset() { rm -rf "$STATUS_DIR" "$STUDIO_REPORTS_DIR" "$LIVE_DIR" "$NEEDS_REVIEW_DIR"; mkdir -p "$STATUS_DIR" "$STUDIO_REPORTS_DIR"; }
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
run "$OLD"; check "already live sha is a noop" 0 "noop: already live" "skipped-superseded: newer"

reset; cloud "$NEW" pass; echo '{"status":"no-publish"}' >"$STATUS_DIR/$OLD.publish.json"; cloud "$OLD" pass
run "$OLD"; check "no-publish sha is a noop" 0 "noop: already no-publish" "skipped-superseded: newer"

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

# ---- needs-review markers ----------------------------------------------------
mk() { echo "$NEEDS_REVIEW_DIR/$1"; }
expect() { # expect <name> <marker sha> <present|absent>
  if [[ ( $3 == present && -e "$(mk "$2")" ) || ( $3 == absent && ! -e "$(mk "$2")" ) ]]; then echo "ok   $1"
  else echo "FAIL $1 (marker should be $3)"; fails=$((fails + 1)); fi
}
report() { # report <sha> <status> <frames_reviewed>
  jq -n --arg sha "$1" --arg st "$2" --argjson fr "$3" --arg at "$(date -d '+1 hour' -Iseconds)" \
    '{sha: $sha, status: $st, checked_at: $at, frames_reviewed: $fr, reviewed_by: ["phoenix"]}' >"$STUDIO_REPORTS_DIR/$1.json"
}
export AUTO_PUBLISH=0

reset; cloud "$NEW" pass
run "$NEW"; check "cloud pass + no report is pending" 3 "blocked: no studio report"
expect "cloud pass + no report -> marker created" "$NEW" present
[[ -s "$(mk "$NEW")" ]] && { echo "FAIL marker not empty"; fails=$((fails + 1)); } || echo "ok   marker is empty"

reset; cloud "$NEW" pass; report "$NEW" pass false
run "$NEW"; check "report pass, frames_reviewed=false blocks" 3 "frames_reviewed is not true"
expect "report pass + frames_reviewed=false -> marker created" "$NEW" present

reset; cloud "$NEW" pass; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$NEW")"; report "$NEW" pass true
run "$NEW"; check "frames_reviewed=true passes the gate" 0 "gate: PASS"
expect "frames_reviewed=true -> marker removed" "$NEW" absent

reset; cloud "$NEW" pass; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$NEW")"; report "$NEW" fail true
run "$NEW"; check "report fail is no-publish" 4 "no-publish"
expect "report fail -> marker removed" "$NEW" absent

reset; cloud "$NEW" pass; report "$NEW" fail false
run "$NEW"; expect "report fail, frames not reviewed -> no marker" "$NEW" absent

reset; cloud "$NEW" fail
run "$NEW"; expect "cloud fail -> no marker" "$NEW" absent

reset; cloud "$NEW" pass; cloud "$OLD" pass; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"
run "$OLD"; check "superseded sha" 4 "superseded_by=$NEW"
expect "skipped-superseded -> marker removed" "$OLD" absent

reset; cloud "$NEW" pass; cloud "$OLD" pass; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"
SO=1 run "$OLD"; expect "SUPERSEDE_ONLY superseded -> marker removed" "$OLD" absent

for st in live no-publish smoke-failed skipped-superseded; do
  reset; cloud "$OLD" pass; echo "{\"status\":\"$st\"}" >"$STATUS_DIR/$OLD.publish.json"; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"
  run "$OLD"; expect "terminal $st -> marker removed" "$OLD" absent
done

# ---- already-live / terminal no-op -------------------------------------------
export AUTO_PUBLISH=1
for st in live smoke-failed no-publish skipped-superseded; do
  reset; cloud "$NEW" pass; cloud "$OLD" pass; echo "{\"status\":\"$st\"}" >"$STATUS_DIR/$OLD.publish.json"
  run "$OLD"; check "terminal $st is a noop" 0 "noop: already $st" "upload\|skipped-superseded: newer"
  grep -q "\"$st\"" "$STATUS_DIR/$OLD.publish.json" && echo "ok   $st publish.json untouched" || { echo "FAIL $st rewritten"; fails=$((fails + 1)); }
done
for bad in "" "{not json"; do
  reset; cloud "$NEW" pass; cloud "$OLD" pass; printf '%s' "$bad" >"$STATUS_DIR/$OLD.publish.json"
  mkdir -p "$LIVE_DIR"; echo '{"status":"live"}' >"$LIVE_DIR/$OLD.json"
  run "$OLD"; check "bad publish.json ('$bad') + live/<sha>.json live is a noop" 0 "noop: already live" "upload\|skipped-superseded: newer"
done
reset; cloud "$NEW" pass; cloud "$OLD" pass; : >"$STATUS_DIR/$OLD.publish.json"; mkdir -p "$LIVE_DIR"; : >"$LIVE_DIR/$OLD.json"
run "$OLD"; check "empty publish.json + empty live file is not a noop" 4 "superseded_by=$NEW" "noop"

# ---- live json is built from files, not argv ---------------------------------
reset
BIG="$T/big_report.json"
jq -n --arg sha "$OLD" '{sha: $sha, status: "pass", frames_reviewed: true, reviewed_by: ["phoenix"], blob: ([range(0; 8000) | "frame-detail-line-padding-padding-padding-\(.)"] | join(","))}' >"$BIG"
[[ $(stat -c %s "$BIG") -gt 200000 ]] || { echo "FAIL fake report too small"; fails=$((fails + 1)); }
LIVE_OUT="$(
  PUBLISH_LIB_ONLY=1 DRY_RUN=0 source "$HERE/publish.sh" "$CHECKOUT" "$OLD" 2>/dev/null
  REPORT="$(cat "$BIG")"
  write_live_status 12 34 2024-01-01T00:00:00+00:00 2>&1 && echo WROTE
)"
if [[ "$LIVE_OUT" == *WROTE ]] && for f in "$STATUS_DIR/$OLD.publish.json" "$LIVE_DIR/$OLD.json"; do
  jq -e --arg sha "$OLD" '.sha == $sha and .status == "live" and .saved_version == 12 and .published_version == 34 and .smoke == "pass" and (.studio_report.blob | length) > 100000 and (.merged_at | type) == "string"' "$f" >/dev/null || exit 1
done; then echo "ok   write_live_status builds live json from a 200KB report (no argv)"
else echo "FAIL write_live_status: $LIVE_OUT"; fails=$((fails + 1)); fi

if (( fails )); then echo "$fails FAILED"; exit 1; fi
echo "all passed"
