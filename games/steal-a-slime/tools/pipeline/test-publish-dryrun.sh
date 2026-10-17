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
# No network: the report API fallback (fetch_report) and the full-run request call ghbot-gojo; stub it to fail.
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 1\n' >"$T/bin/ghbot-gojo"; chmod +x "$T/bin/ghbot-gojo"; export PATH="$T/bin:$PATH"
fails=0
reset() { rm -rf "$STATUS_DIR" "$STUDIO_REPORTS_DIR" "$LIVE_DIR" "$NEEDS_REVIEW_DIR"; mkdir -p "$STATUS_DIR" "$STUDIO_REPORTS_DIR"; }
cloud() { echo "{\"status\":\"$2\",\"finished\":\"$(date -Iseconds)\"}" >"$STATUS_DIR/$1.json"; }
run() { OUT="$(SUPERSEDE_ONLY="${SO:-0}" "$HERE/publish.sh" "$CHECKOUT" "$1" 2>&1)"; RC=$?; }
check() { # check <name> <expected rc> <grep pattern|-> 
  if [[ $RC == "$2" ]] && { [[ "$3" == - ]] || grep -q -- "$3" <<<"$OUT"; } && { [[ -z "${4:-}" ]] || ! grep -q -- "$4" <<<"$OUT"; }; then
    echo "ok   $1 (rc=$RC)"
  else echo "FAIL $1 (rc=$RC, want $2 /$3/)"; sed 's/^/     /' <<<"$OUT"; fails=$((fails + 1)); fi
}

# NB: AUTO_PUBLISH=1 below; the dry run prints "DRY_RUN steps" when the sha would publish.
report() { # report <sha> <status> <frames_reviewed> [run_kind, default full; "none" omits the field]
  jq -n --arg sha "$1" --arg st "$2" --argjson fr "$3" --arg at "$(date -d '+1 hour' -Iseconds)" --arg rk "${4:-full}" \
    '{sha: $sha, status: $st, checked_at: $at, frames_reviewed: $fr, reviewed_by: ["phoenix"]} + (if $rk == "none" then {} else {run_kind: $rk} end)' >"$STUDIO_REPORTS_DIR/$1.json"
}
gate() { cloud "$1" pass; report "$1" pass true; } # fully gated
no_publish_steps() { ! grep -q "DRY_RUN steps" <<<"$OUT"; }

# superseded only by a newer sha that is itself fully gated
reset; gate "$NEW"; gate "$OLD"
run "$OLD"; check "older gated sha is superseded by newer gated sha" 4 "superseded_by=$NEW"
[[ ! -e "$STATUS_DIR/$OLD.publish.json" ]] && echo "ok   dry-run wrote no publish.json" || { echo "FAIL dry-run wrote a file"; fails=$((fails + 1)); }

reset; gate "$MID"; gate "$OLD" # newest has no status yet -> nearest gated newer sha wins
run "$OLD"; check "superseded by nearest gated newer sha (newest has no status)" 4 "superseded_by=$MID"

reset; cloud "$NEW" pass; gate "$OLD" # starvation: newer sha is cloud-pass only, no report
run "$OLD"; check "gated A, newer B cloud-pass without report: A publishes" 0 "DRY_RUN steps" "skipped-superseded"
reset; cloud "$NEW" pass; gate "$OLD"; report "$NEW" pass false
run "$OLD"; check "gated A, newer B report frames_reviewed=false: A publishes" 0 "DRY_RUN steps" "skipped-superseded"

reset; cloud "$NEW" fail; gate "$OLD"
run "$OLD"; check "newer sha with cloud fail does not supersede" 0 "DRY_RUN steps" "skipped-superseded"

reset; cloud "$NEW" pass; cloud "$OLD" pass # waiting A, newer B also waiting: both stay waiting
run "$OLD"; check "ungated A with only newer ungated shas stays waiting" 3 "blocked: no studio report" "skipped-superseded"
run "$NEW"; check "ungated newest sha waits" 3 "blocked: no studio report"

reset; cloud "$NEW" pass; cloud "$OLD" pass
jq -n '{status:"pass",finished:"2000-01-01T00:00:00+00:00"}' >"$STATUS_DIR/$OLD.json"
run "$OLD"; check "timeout alone never makes a waiting sha terminal" 3 "still waiting" "no-publish"

reset; gate "$NEW"; cloud "$OLD" pending
run "$OLD"; check "pending older sha superseded by gated newer" 4 "superseded_by=$NEW"

reset; gate "$NEW"
run "$OLD"; check "older sha without any status superseded by gated newer" 4 "superseded_by=$NEW"

# ordering / never older than live
reset; gate "$NEW"; gate "$OLD"
run "$NEW"; check "A and B gated: B (newest) publishes" 0 "DRY_RUN steps"
reset; gate "$NEW"; gate "$OLD"; mkdir -p "$LIVE_DIR"; echo '{"status":"live"}' >"$LIVE_DIR/$NEW.json"
run "$OLD"; check "live newer than candidate: no publish" 4 "superseded_by=$NEW" "DRY_RUN steps"
reset; gate "$MID"; gate "$OLD"; mkdir -p "$LIVE_DIR"; echo '{"status":"live"}' >"$LIVE_DIR/$MID.json"
run "$OLD"; check "never older than live (candidate is ancestor of live)" 4 "already live" "DRY_RUN steps"
reset; gate "$NEW"; mkdir -p "$LIVE_DIR"; echo '{"status":"live"}' >"$LIVE_DIR/$OLD.json"
run "$NEW"; check "candidate newer than live publishes" 0 "DRY_RUN steps"
reset; gate "$OLD"; mkdir -p "$LIVE_DIR"; echo '{"status":"live"}' >"$LIVE_DIR/$NEW.json"
run "$OLD"; check "ungated-newer irrelevant; live newer blocks even without cloud status of live sha" 4 "already live"
reset; cloud "$OLD" pass; mkdir -p "$LIVE_DIR"; echo '{"status":"live"}' >"$LIVE_DIR/$MID.json"
run "$OLD"; check "ungated candidate older than live is superseded" 4 "already live"

reset; cloud "$NEW" pass; echo '{"status":"live"}' >"$STATUS_DIR/$OLD.publish.json"
run "$OLD"; check "already live sha is a noop" 0 "noop: already live" "skipped-superseded: newer"

reset; cloud "$NEW" pass; echo '{"status":"no-publish"}' >"$STATUS_DIR/$OLD.publish.json"; cloud "$OLD" pass
run "$OLD"; check "no-publish sha is a noop" 0 "noop: already no-publish" "skipped-superseded: newer"

reset; gate "$NEW"; echo '{"status":"ready"}' >"$STATUS_DIR/$OLD.publish.json"; gate "$OLD"
run "$OLD"; check "ready sha is superseded by gated newer" 4 "superseded_by=$NEW"

reset; gate "$NEW"; gate "$OLD"
SO=1 run "$OLD"; check "SUPERSEDE_ONLY still marks superseded" 4 "superseded_by=$NEW"

reset; gate "$NEW"; gate "$MID"
SO=1 run "$NEW"; check "newest sha is never superseded (SUPERSEDE_ONLY)" 0 - "skipped-superseded"

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

reset; gate "$NEW"; cloud "$OLD" pass; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"
run "$OLD"; check "superseded sha" 4 "superseded_by=$NEW"
expect "skipped-superseded -> marker removed" "$OLD" absent

reset; gate "$NEW"; cloud "$OLD" pass; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"
SO=1 run "$OLD"; expect "SUPERSEDE_ONLY superseded -> marker removed" "$OLD" absent

for st in live no-publish smoke-failed skipped-superseded; do
  reset; cloud "$OLD" pass; echo "{\"status\":\"$st\"}" >"$STATUS_DIR/$OLD.publish.json"; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"
  run "$OLD"; expect "terminal $st -> marker removed" "$OLD" absent
done

# newest-only marker: A (older) and B (newer) both cloud-pass, un-reviewed
reset; cloud "$NEW" pass; cloud "$OLD" pass
run "$OLD"; expect "older un-reviewed sha has no marker when newer one waits" "$OLD" absent
run "$NEW"; expect "newest un-reviewed sha keeps marker" "$NEW" present
# starvation case: A gated publishes, B keeps its marker
reset; gate "$OLD"; cloud "$NEW" pass; export AUTO_PUBLISH=1
run "$OLD"; check "starvation: A gated publishes" 0 "DRY_RUN steps"
run "$NEW"; check "starvation: B still waiting" 3 "blocked: no studio report"
expect "starvation: B keeps marker" "$NEW" present
export AUTO_PUBLISH=0
reset; gate "$NEW"; cloud "$OLD" pass; mkdir -p "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"
run "$OLD"; expect "marker of sha older than gated sha removed" "$OLD" absent
reset; cloud "$OLD" pass; mkdir -p "$LIVE_DIR" "$NEEDS_REVIEW_DIR"; touch "$(mk "$OLD")"; echo '{"status":"live"}' >"$LIVE_DIR/$MID.json"
run "$OLD"; expect "marker of sha older than live removed" "$OLD" absent

# ---- run_kind: only FULL Studio reports gate a publish -----------------------
export AUTO_PUBLISH=1
reset; cloud "$NEW" pass; report "$NEW" pass true partial
run "$NEW"; check "partial pass report (reviewed) never gates" 3 "run_kind"
no_publish_steps && echo "ok   partial pass report: no publish steps" || { echo "FAIL partial pass report published"; fails=$((fails + 1)); }
expect "partial pass report -> needs-review marker stays" "$NEW" present

reset; cloud "$NEW" pass; report "$NEW" fail true partial
run "$NEW"; check "partial fail report is not terminal (rc 3, not no-publish)" 3 "run_kind" "no-publish"
expect "partial fail report -> needs-review marker exists" "$NEW" present

reset; cloud "$NEW" pass; report "$NEW" pass true none
run "$NEW"; check "report without run_kind is blocked" 3 "run_kind"
no_publish_steps && echo "ok   report without run_kind: no publish steps" || { echo "FAIL run_kind-less report published"; fails=$((fails + 1)); }

reset; cloud "$NEW" pass; report "$NEW" pass true perf
run "$NEW"; check "perf report (even reviewed) never gates" 3 "run_kind"
no_publish_steps && echo "ok   perf report: no publish steps" || { echo "FAIL perf report published"; fails=$((fails + 1)); }

reset; cloud "$NEW" pass; report "$NEW" pass true full
run "$NEW"; check "full pass reviewed report publishes" 0 "DRY_RUN steps"
expect "full pass reviewed -> no marker" "$NEW" absent

reset; cloud "$NEW" pass; report "$NEW" fail true full
run "$NEW"; check "full fail report is still no-publish" 4 "no-publish"

reset; cloud "$NEW" pass
run "$NEW"; check "marker set requests a full Studio run" 3 "would request full Studio run (studio-reports/requests/$NEW.json)"
reset; cloud "$NEW" pass; FULL_REQUEST=0 run "$NEW"; check "FULL_REQUEST=0 disables the request" 3 "needs-review: marker set" "would request"
# live path (DRY_RUN=0 only for the request): stamp once per sha, command overridable
reset; cloud "$NEW" pass
printf '#!/usr/bin/env bash\necho "$1" >>"%s/req.log"\n' "$T" >"$T/req.sh"; chmod +x "$T/req.sh"
DRY_RUN=0 FULL_REQUEST_CMD="$T/req.sh" run "$NEW"; DRY_RUN=0 FULL_REQUEST_CMD="$T/req.sh" run "$NEW"
[[ "$(cat "$T/req.log" 2>/dev/null)" == "$NEW" && -e "$STATUS_DIR/$NEW.full-request" ]] && echo "ok   request attempted once per sha (stamp has no .json)" || { echo "FAIL request once: $(cat "$T/req.log" 2>/dev/null)"; fails=$((fails + 1)); }
reset; cloud "$NEW" pass; rm -f "$T/req.log"
printf '#!/usr/bin/env bash\necho "$1" >>"%s/req.log"; exit 1\n' "$T" >"$T/req-fail.sh"; chmod +x "$T/req-fail.sh"
DRY_RUN=0 FULL_REQUEST_CMD="$T/req-fail.sh" run "$NEW"; DRY_RUN=0 FULL_REQUEST_CMD="$T/req-fail.sh" run "$NEW"
[[ "$(wc -l <"$T/req.log" 2>/dev/null)" == 2 && ! -e "$STATUS_DIR/$NEW.full-request" ]] && echo "ok   failed request leaves no stamp and is retried" || { echo "FAIL request retry: $(cat "$T/req.log" 2>/dev/null)"; fails=$((fails + 1)); }
export AUTO_PUBLISH=0

# ---- already-live / terminal no-op -------------------------------------------
export AUTO_PUBLISH=1
for st in live smoke-failed no-publish skipped-superseded; do
  reset; cloud "$NEW" pass; cloud "$OLD" pass; echo "{\"status\":\"$st\"}" >"$STATUS_DIR/$OLD.publish.json"
  run "$OLD"; check "terminal $st is a noop" 0 "noop: already $st" "upload\|skipped-superseded: "
  grep -q "\"$st\"" "$STATUS_DIR/$OLD.publish.json" && echo "ok   $st publish.json untouched" || { echo "FAIL $st rewritten"; fails=$((fails + 1)); }
done
for bad in "" "{not json"; do
  reset; cloud "$NEW" pass; cloud "$OLD" pass; printf '%s' "$bad" >"$STATUS_DIR/$OLD.publish.json"
  mkdir -p "$LIVE_DIR"; echo '{"status":"live"}' >"$LIVE_DIR/$OLD.json"
  run "$OLD"; check "bad publish.json ('$bad') + live/<sha>.json live is a noop" 0 "noop: already live" "upload\|skipped-superseded: "
done
reset; gate "$NEW"; cloud "$OLD" pass; : >"$STATUS_DIR/$OLD.publish.json"; mkdir -p "$LIVE_DIR"; : >"$LIVE_DIR/$OLD.json"
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
