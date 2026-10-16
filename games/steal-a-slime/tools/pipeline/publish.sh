#!/usr/bin/env bash
# Release stage for Steal a Slime (see docs/release-pipeline.md).
#
#   tools/pipeline/publish.sh <checkout-dir> <sha>
#   AUTO_PUBLISH=1 ROBLOX_OPEN_CLOUD_API_KEY=... tools/pipeline/publish.sh <checkout-dir> <sha>
#   DRY_RUN=1 AUTO_PUBLISH=1 tools/pipeline/publish.sh <checkout-dir> <sha>
#
# 1. gate: status/<sha>.json pass AND a valid Phoenix Studio report,
# 2. only with AUTO_PUBLISH=1: clean build (no CloudTests) -> upload Saved ->
#    smoke test that version -> upload the same clean file as Published.
#    The cloud-test Saved version is never promoted.
# DRY_RUN=1 evaluates the gate, builds + asserts, prints the calls it would make
# and writes nothing outside $WORK. The key reaches curl on stdin only.
#
# Newest only: a sha with a newer cloud-passed sha on main (first-parent order of
# $MAIN_REF) is never published; it gets status skipped-superseded. Checked at the
# start and again right before each upload. SUPERSEDE_ONLY=1 stops after that check.
#
# Needs-review marker: while $SHA has cloud pass but Phoenix has not yet reviewed
# frames (no Studio report, or report status=pass with frames_reviewed != true) an
# empty file $NEEDS_REVIEW_DIR/<40-char sha> exists so Gojo can ping Phoenix. It is
# removed once frames_reviewed is true, the report is fail, or the sha ends
# live / skipped-superseded / no-publish / smoke-failed. Honoured under DRY_RUN too.
#
# A sha already live / smoke-failed / no-publish / skipped-superseded (or with live/<sha>.json
# status live) is a no-op: exit 0, nothing uploaded.
#
# Exit: 0 live / ready / noop / dry-run ok, 3 pending (retry next tick),
#       4 no-publish or skipped-superseded (terminal), 2 error (retry),
#       5 smoke failed (terminal-ish: not published).
set -uo pipefail

CHECKOUT="${1:?usage: publish.sh <checkout-dir> <sha>}"
SHA="${2:?usage: publish.sh <checkout-dir> <sha>}"
GAME_DIR="$(cd "$CHECKOUT/${GAME_SUBDIR:-games/steal-a-slime}" && pwd)" || exit 2
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UNIVERSE_ID="${UNIVERSE_ID:-10770917350}"
PLACE_ID="${PLACE_ID:-135787188192378}"
PIPE="${PIPE_DIR:-/workspace/roblox/pipeline}"
STATUS_DIR="${STATUS_DIR:-$PIPE/status}"
STUDIO_REPORTS_DIR="${STUDIO_REPORTS_DIR:-$PIPE/studio-reports}"
LIVE_DIR="${LIVE_DIR:-$PIPE/live}"
AUTO_PUBLISH="${AUTO_PUBLISH:-0}"
DRY_RUN="${DRY_RUN:-0}"
REPO_SLUG="${REPO_SLUG:-Mxndarijn/RobloxGames}"
REPORT_TIMEOUT_S="${REPORT_TIMEOUT_S:-1800}"
MAIN_REF="${MAIN_REF:-origin/main}"
SUPERSEDE_ONLY="${SUPERSEDE_ONLY:-0}"
MIRROR_STALE_S="${MIRROR_STALE_S:-300}"
UPLOAD_BACKOFF="${UPLOAD_BACKOFF-60 120 240 480}"
NEEDS_REVIEW_DIR="${NEEDS_REVIEW_DIR:-$PIPE/needs-review}"
API="https://apis.roblox.com"

mkdir -p "$STATUS_DIR"
LOG="$STATUS_DIR/$SHA.publish.log"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/publish-${SHA:0:12}-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
[[ "$DRY_RUN" == 1 ]] && LOG=/dev/stderr

log() { echo "$(date -Iseconds) $*" | { [[ "$LOG" == /dev/stderr ]] && cat >&2 || tee -a "$LOG" >&2; }; }
epoch() { date -d "$1" +%s 2>/dev/null; }

cloud() {
  printf 'x-api-key: %s\n' "$ROBLOX_OPEN_CLOUD_API_KEY" | curl -sS --max-time 180 -H @- "$@"
}
HTTP_CODE=""
cloud_retry() {
  local waits="$1" resp wait
  shift
  for wait in 0 $waits; do
    [[ $wait -gt 0 ]] && { log "retry in ${wait}s (HTTP $HTTP_CODE)"; sleep "$wait"; }
    resp="$(cloud "$@" -w $'\n%{http_code}')" || resp=$'\n000'
    HTTP_CODE="${resp##*$'\n'}"
    resp="${resp%$'\n'*}"
    [[ "$HTTP_CODE" == 409 || "$HTTP_CODE" == 429 || "$HTTP_CODE" == 5* || "$HTTP_CODE" == 000 ]] || break
  done
  printf '%s' "$resp" >"$WORK/resp"
}

# Marker file name is always the full 40-char sha.
FULL_SHA="$SHA"
[[ "$FULL_SHA" =~ ^[0-9a-f]{40}$ ]] || FULL_SHA="$(git -C "$CHECKOUT" rev-parse --verify -q "$SHA^{commit}" 2>/dev/null || true)"
needs_review_set() {
  [[ -n "$FULL_SHA" ]] || return 0
  case "$(jq -r .status "$STATUS_DIR/$SHA.publish.json" 2>/dev/null)" in "" | ready) ;; *) return 0 ;; esac # terminal: never re-mark
  mkdir -p "$NEEDS_REVIEW_DIR" && touch "$NEEDS_REVIEW_DIR/$FULL_SHA"
  log "needs-review: marker set ($NEEDS_REVIEW_DIR/$FULL_SHA)"
}
needs_review_clear() {
  [[ -n "$FULL_SHA" ]] || return 0
  mkdir -p "$NEEDS_REVIEW_DIR"
  if [[ -e "$NEEDS_REVIEW_DIR/$FULL_SHA" ]]; then
    rm -f "$NEEDS_REVIEW_DIR/$FULL_SHA"
    log "needs-review: marker removed"
  fi
}

write_json() { # write_json <path> (stdin)
  cat >"$1.tmp" && mv "$1.tmp" "$1"
}

# terminal <status> <reason> [extra jq object]: writes status/<sha>.publish.json
terminal() {
  local status="$1" reason="$2"
  log "$status: $reason"
  needs_review_clear
  if [[ "$DRY_RUN" == 1 ]]; then
    log "DRY_RUN: would write $STATUS_DIR/$SHA.publish.json status=$status"
    return
  fi
  jq -n --arg sha "$SHA" --arg status "$status" --arg reason "$reason" --arg at "$(date -Iseconds)" \
    '{sha: $sha, status: $status, reason: $reason, at: $at}' | write_json "$STATUS_DIR/$SHA.publish.json"
}

# newer_passed: prints the newest sha after $SHA on $MAIN_REF (first-parent order)
# whose cloud status is pass; nothing if none (or $SHA is not on main's first-parent line).
newer_passed() {
  local n found=0 newer=()
  while read -r n; do
    [[ "$n" == "$SHA" ]] && { found=1; break; }
    newer+=("$n")
  done < <(git -C "$CHECKOUT" rev-list --first-parent "$MAIN_REF" 2>/dev/null)
  [[ $found == 1 ]] || return 0
  for n in "${newer[@]}"; do # newest first
    if [[ -f "$STATUS_DIR/$n.json" && "$(jq -r .status "$STATUS_DIR/$n.json" 2>/dev/null)" == pass ]]; then
      echo "$n"; return 0
    fi
  done
}
# check_superseded: writes skipped-superseded and exits 4 when a newer sha passed.
# Shas that already ended live / no-publish / smoke-failed are left alone.
check_superseded() {
  local cur newer
  cur="$(jq -r .status "$STATUS_DIR/$SHA.publish.json" 2>/dev/null)"
  case "$cur" in "" | ready) ;; *) needs_review_clear; return 0 ;; esac
  newer="$(newer_passed)"
  [[ -n "$newer" ]] || return 0
  log "skipped-superseded: newer sha $newer on $MAIN_REF has cloud status pass"
  needs_review_clear
  if [[ "$DRY_RUN" == 1 ]]; then
    log "DRY_RUN: would write $STATUS_DIR/$SHA.publish.json status=skipped-superseded superseded_by=$newer"
  else
    jq -n --arg sha "$SHA" --arg by "$newer" --arg at "$(date -Iseconds)" \
      '{sha: $sha, status: "skipped-superseded", superseded_by: $by, reason: "newer sha passed cloud tests", at: $at}' |
      write_json "$STATUS_DIR/$SHA.publish.json"
  fi
  exit 4
}

# write_live_status <saved> <published> <merged_at>: writes status/<sha>.publish.json and
# live/<sha>.json. The ~150KB studio report goes in via a file (--slurpfile), never argv
# (--argjson "$REPORT" died with "Argument list too long").
write_live_status() {
  mkdir -p "$LIVE_DIR" "$STATUS_DIR"
  printf '%s' "$REPORT" >"$WORK/studio_report.json"
  jq -n --arg sha "$SHA" --argjson saved "$1" --argjson published "$2" --arg at "$(date -Iseconds)" \
    --arg place "$UNIVERSE_ID/$PLACE_ID" --slurpfile report "$WORK/studio_report.json" --arg merged "$3" \
    '{sha: $sha, status: "live", saved_version: $saved, published_version: $published, smoke: "pass",
      place: $place, merged_at: $merged, published_at: $at, studio_report: $report[0]}' >"$WORK/live.json" || return 1
  write_json "$STATUS_DIR/$SHA.publish.json" <"$WORK/live.json" &&
    write_json "$LIVE_DIR/$SHA.json" <"$WORK/live.json"
}
[[ "${PUBLISH_LIB_ONLY:-0}" == 1 ]] && return 0 # tests source the helpers above

# noop_if_done: exit 0 when $SHA already ended in a terminal state, or live/<sha>.json says
# live (covers an empty/corrupt publish.json left by a publish that died at the final write).
noop_if_done() {
  local cur live_st
  cur="$(jq -r '.status // empty' "$STATUS_DIR/$SHA.publish.json" 2>/dev/null)"
  case "$cur" in live | smoke-failed | no-publish | skipped-superseded) ;; *)
    live_st="$(jq -r '.status // empty' "$LIVE_DIR/$SHA.json" 2>/dev/null)"
    [[ "$live_st" == live ]] || return 0
    cur="live (live/$SHA.json)" ;;
  esac
  log "noop: already $cur"
  needs_review_clear
  exit 0
}

# ---- gate ----------------------------------------------------------------
noop_if_done
check_superseded
[[ "$SUPERSEDE_ONLY" == 1 ]] && exit 0
CLOUD_STATUS="$STATUS_DIR/$SHA.json"
[[ -f "$CLOUD_STATUS" ]] || { log "blocked: no cloud-test status for $SHA"; exit 3; }
CLOUD="$(jq -r .status "$CLOUD_STATUS")"
case "$CLOUD" in
  pass) ;;
  fail | error)
    if [[ "$CLOUD" == fail ]]; then terminal no-publish "cloud tests failed"; exit 4; fi
    log "blocked: cloud tests errored (watcher retries)"; exit 3 ;;
  *) log "blocked: cloud status '$CLOUD'"; exit 3 ;;
esac
CLOUD_FINISHED="$(jq -r '.finished // empty' "$CLOUD_STATUS")"
MERGE_TIME="$(git -C "$CHECKOUT" show -s --format=%cI "$SHA" 2>/dev/null)" || { log "error: sha $SHA not in checkout"; exit 2; }

# Report source: local mirror, GitHub API when the mirror file is missing or
# the mirror hasn't been refreshed for MIRROR_STALE_S.
mirror_fresh() {
  [[ -d "$STUDIO_REPORTS_DIR" ]] || return 1
  local newest now
  newest="$(find "$STUDIO_REPORTS_DIR" -maxdepth 1 -printf '%T@\n' | sort -n | tail -1)"
  now="$(date +%s)"
  [[ -n "$newest" ]] && (( now - ${newest%.*} <= MIRROR_STALE_S ))
}
fetch_report() { # prints report JSON on stdout, empty if none
  local f="$STUDIO_REPORTS_DIR/$SHA.json" api
  if [[ -f "$f" ]] && mirror_fresh; then
    cat "$f"
    return
  fi
  log "report: mirror file missing or mirror stale; GET repos/$REPO_SLUG/contents/$SHA.json?ref=studio-reports"
  api="$(ghbot-gojo api "repos/$REPO_SLUG/contents/$SHA.json?ref=studio-reports" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)"
  if [[ -n "$api" ]]; then echo "$api"; elif [[ -f "$f" ]]; then cat "$f"; fi # API down: stale mirror beats nothing
}
REPORT="$(fetch_report)"

# Needs-review marker: set while Phoenix still has to review frames, clear otherwise.
if [[ -z "$REPORT" ]]; then
  needs_review_set
elif echo "$REPORT" | jq -e --arg sha "$SHA" '.sha == $sha and .status == "pass" and .frames_reviewed != true' >/dev/null 2>&1; then
  needs_review_set
else
  needs_review_clear
fi

# Returns reason on stdout when the report is missing/incomplete, nothing when valid.
report_problem() {
  [[ -n "$REPORT" ]] || { echo "no studio report"; return; }
  echo "$REPORT" | jq -e . >/dev/null 2>&1 || { echo "report is not valid JSON"; return; }
  echo "$REPORT" | jq -r --arg sha "$SHA" '
    if .sha != $sha then "report sha mismatch"
    elif .status != "pass" and .status != "fail" then "report status not pass|fail"
    elif (.checked_at | type) != "string" then "report has no checked_at"
    elif .frames_reviewed != true then "frames_reviewed is not true"
    elif ((.reviewed_by | type) != "array") or ((.reviewed_by | length) == 0) or (any(.reviewed_by[]; (type != "string") or . == "")) then "reviewed_by empty"
    else empty end'
}
PROBLEM="$(report_problem)"
if [[ -z "$PROBLEM" ]]; then
  if [[ "$(echo "$REPORT" | jq -r .status)" == fail ]]; then
    terminal no-publish "studio report status=fail"; exit 4
  fi
  CHECKED="$(epoch "$(echo "$REPORT" | jq -r .checked_at)")" || CHECKED=""
  if [[ -z "$CHECKED" ]]; then PROBLEM="checked_at unparseable"
  elif (( CHECKED <= $(epoch "$MERGE_TIME") )); then PROBLEM="checked_at ($(echo "$REPORT" | jq -r .checked_at)) is not later than merge time ($MERGE_TIME)"
  fi
fi
if [[ -n "$PROBLEM" ]]; then
  FIN="$(epoch "$CLOUD_FINISHED" || echo 0)"
  AGE=$(( $(date +%s) - FIN ))
  if (( AGE > REPORT_TIMEOUT_S )); then
    terminal no-publish "$PROBLEM; ${AGE}s after cloud pass (limit ${REPORT_TIMEOUT_S}s)"; exit 4
  fi
  log "blocked: $PROBLEM (cloud pass ${AGE}s ago, timeout in $((REPORT_TIMEOUT_S - AGE))s)"
  exit 3
fi
log "gate: PASS (cloud pass, studio report pass, reviewed_by=$(echo "$REPORT" | jq -c .reviewed_by))"

if [[ "$AUTO_PUBLISH" != 1 ]]; then
  check_superseded
  terminal ready "gate passed; AUTO_PUBLISH!=1, not publishing"
  exit 0
fi

# ---- clean build -----------------------------------------------------------
for tool in rojo jq curl; do command -v "$tool" >/dev/null || { log "error: $tool not on PATH"; exit 2; }; done
PLACE="$WORK/steal-a-slime.rbxl"
(cd "$GAME_DIR" && rojo build default.project.json -o "$PLACE" && rojo build default.project.json -o "$WORK/check.rbxlx") >"$WORK/build.log" 2>&1 ||
  { log "error: rojo build failed: $(tail -3 "$WORK/build.log")"; exit 2; }
if grep -q 'CloudTests' "$WORK/check.rbxlx" || jq -e '.. | objects | select(has("CloudTests"))' "$GAME_DIR/default.project.json" >/dev/null; then
  log "error: ServerStorage.CloudTests present in clean build"; exit 2
fi
log "clean build ok ($(du -h "$PLACE" | cut -f1)), ServerStorage.CloudTests absent"

UP="$API/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions"
TASKS="$API/cloud/v2/universes/$UNIVERSE_ID/places/$PLACE_ID/versions/<saved_version>/luau-execution-session-tasks"
if [[ "$DRY_RUN" == 1 ]]; then
  log "DRY_RUN steps (no network writes):"
  log "  1. POST $UP?versionType=Saved  (octet-stream, clean place) -> saved_version"
  log "  2. POST $TASKS  (script tools/livetest/cloud/smoke.luau), poll GET $API/cloud/v2/<task path> until COMPLETE, require result.ok==true"
  log "  3. POST $UP?versionType=Published  (same clean place file) -> published_version"
  log "  4. write $STATUS_DIR/$SHA.publish.json {status: live} and $LIVE_DIR/$SHA.json"
  exit 0
fi
[[ -n "${ROBLOX_OPEN_CLOUD_API_KEY:-}" ]] || { log "error: ROBLOX_OPEN_CLOUD_API_KEY is not set"; exit 2; }

upload() { # upload <Saved|Published> -> version number on stdout
  cloud_retry "$UPLOAD_BACKOFF" -X POST -H 'Content-Type: application/octet-stream' --data-binary @"$PLACE" "$UP?versionType=$1"
  log "upload $1: HTTP $HTTP_CODE $(cat "$WORK/resp")"
  [[ "$HTTP_CODE" == 200 ]] || return 1
  jq -r '.versionNumber // empty' "$WORK/resp"
}

check_superseded
SAVED="$(upload Saved)" && [[ "$SAVED" =~ ^[0-9]+$ ]] || { log "error: upload Saved failed"; exit 2; }

# ---- smoke test the saved version ------------------------------------------
SMOKE_OUT="$WORK/smoke.json"
if OUT="$SMOKE_OUT" "$HERE/../livetest/cloud/run.sh" "$HERE/../livetest/cloud/smoke.luau" "$SAVED" >>"$LOG" 2>&1; then
  SMOKE=pass
else
  SMOKE=fail
fi
log "smoke on saved version $SAVED: $SMOKE"
if [[ "$SMOKE" != pass ]]; then
  needs_review_clear
  jq -n --arg sha "$SHA" --argjson saved "$SAVED" --arg at "$(date -Iseconds)" \
    '{sha: $sha, status: "smoke-failed", saved_version: $saved, smoke: "fail", at: $at}' | write_json "$STATUS_DIR/$SHA.publish.json"
  exit 5
fi

# ---- publish the clean file -------------------------------------------------
check_superseded # a newer sha may have passed while this one was building / smoking
PUBLISHED="$(upload Published)" && [[ "$PUBLISHED" =~ ^[0-9]+$ ]] || { log "error: upload Published failed"; exit 2; }
log "LIVE: $SHA published as place version $PUBLISHED (clean saved $SAVED)"
write_live_status "$SAVED" "$PUBLISHED" "$MERGE_TIME"
needs_review_clear
exit 0
