#!/usr/bin/env bash
# Main-branch cloud test stage for Steal a Slime (see tools/pipeline/README.md).
#
#   ROBLOX_OPEN_CLOUD_API_KEY=... tools/pipeline/cloud-test.sh <checkout-dir> <sha>
#
# 1. stages tests/*.luau (tools/pipeline/stage-specs.luau) and builds
#    default.project.json + ServerStorage.CloudTests with rojo,
# 2. uploads that place as versionType=Saved (never Published),
# 3. runs tools/pipeline/cloud-tests.luau against THAT version through Open
#    Cloud Luau Execution,
# 4. writes $STATUS_DIR/<sha>.json and $STATUS_DIR/latest.json.
#
# The key reaches curl on stdin (-H @-): never in argv, logs or on disk.
# Exit 0 = pass, 1 = test failures, 2 = error (build, upload, task).
set -uo pipefail

CHECKOUT="${1:?usage: cloud-test.sh <checkout-dir> <sha>}"
SHA="${2:?usage: cloud-test.sh <checkout-dir> <sha>}"
GAME_DIR="$(cd "$CHECKOUT/${GAME_SUBDIR:-games/steal-a-slime}" && pwd)" || exit 2
# Stage tools come from this script's directory, specs from the checkout, so a
# sha older than tools/pipeline can still be tested.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UNIVERSE_ID="${UNIVERSE_ID:-10770917350}"
PLACE_ID="${PLACE_ID:-135787188192378}"
STATUS_DIR="${STATUS_DIR:-/workspace/roblox/pipeline/status}"
STUDIO_REPORTS="${STUDIO_REPORTS:-/workspace/roblox/pipeline/studio-reports}"
AUTO_PUBLISH="${AUTO_PUBLISH:-0}" # 1 = publish.sh may publish (see docs/release-pipeline.md)
TASK_TIMEOUT="${TASK_TIMEOUT:-120s}"
POLL_LIMIT_S="${POLL_LIMIT_S:-180}"
# CLAUDE.md: 409 "Server is busy" backoff 1, 2, 4, 8 min, then stop.
UPLOAD_BACKOFF="${UPLOAD_BACKOFF-60 120 240 480}"
TASK_BACKOFF="${TASK_BACKOFF-5 10 20}"
API="https://apis.roblox.com"

mkdir -p "$STATUS_DIR"
LOG="$STATUS_DIR/$SHA.log"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cloud-test-${SHA:0:12}-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
: >"$LOG"

STARTED="$(date -Iseconds)"
START_S="$(date +%s)"
SAVED_VERSION=""
TASK_PATH=""
RESULT='null'

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG" >&2; }

# curl with the key header read from stdin.
cloud() {
  printf 'x-api-key: %s\n' "$ROBLOX_OPEN_CLOUD_API_KEY" | curl -sS --max-time 120 -H @- "$@"
}

# cloud_retry "<waits>" curl-args...: retries 409/429/5xx and network errors.
# Leaves the body in $WORK/resp and the HTTP code in $HTTP_CODE.
HTTP_CODE=""
cloud_retry() {
  local waits="$1" resp wait
  shift
  for wait in 0 $waits; do
    if [[ $wait -gt 0 ]]; then
      log "retry in ${wait}s (HTTP $HTTP_CODE)"
      sleep "$wait"
    fi
    resp="$(cloud "$@" -w $'\n%{http_code}')" || resp=$'\n000'
    HTTP_CODE="${resp##*$'\n'}"
    resp="${resp%$'\n'*}"
    [[ "$HTTP_CODE" == 409 || "$HTTP_CODE" == 429 || "$HTTP_CODE" == 5* || "$HTTP_CODE" == 000 ]] || break
  done
  printf '%s' "$resp" >"$WORK/resp"
}

# Phoenix's PC Studio check, written by hand or by the Studio PC:
# studio-reports/<sha>.json = {sha, status: "pass"|"fail", checked_at, studio_version, notes}
studio_report() {
  local f="$STUDIO_REPORTS/$SHA.json"
  if [[ -f "$f" ]] && jq -e --arg sha "$SHA" '.sha == $sha' "$f" >/dev/null 2>&1; then
    jq -c . "$f"
  else
    echo null
  fi
}

# Hands the sha to publish.sh, which evaluates the gate (cloud pass + Studio
# report) and only publishes with AUTO_PUBLISH=1. A pending gate (no report
# yet) is fine: the watcher re-checks it every tick.
publish_hook() {
  [[ "$1" == pass ]] || { log "publish hook: cloud status $1, skipped"; return 0; }
  log "publish hook: AUTO_PUBLISH=$AUTO_PUBLISH"
  AUTO_PUBLISH="$AUTO_PUBLISH" STATUS_DIR="$STATUS_DIR" \
    STUDIO_REPORTS_DIR="$STUDIO_REPORTS" "$HERE/publish.sh" "$CHECKOUT" "$SHA" >>"$LOG" 2>&1
  log "publish hook: publish.sh rc=$?"
  return 0
}

# finish <pass|fail|error> <message>
finish() {
  local status="$1" message="$2" report gate_ready=false finished
  finished="$(date -Iseconds)"
  report="$(studio_report)"
  if [[ "$status" == pass ]] && echo "$report" | jq -e '.status == "pass"' >/dev/null 2>&1; then
    gate_ready=true
  fi
  log "$status: $message"
  jq -n \
    --arg sha "$SHA" --arg status "$status" --arg message "$message" \
    --arg started "$STARTED" --arg finished "$finished" \
    --argjson duration "$(($(date +%s) - START_S))" \
    --arg version "$SAVED_VERSION" --arg task "$TASK_PATH" --arg log "$LOG" \
    --argjson result "$RESULT" --argjson report "$report" --argjson gate "$gate_ready" \
    --argjson skipped "$(cat "$WORK/skipped.json" 2>/dev/null || echo '[]')" \
    --arg place "$UNIVERSE_ID/$PLACE_ID" \
    '{
      sha: $sha, stage: "cloud-tests", status: $status, message: $message,
      started: $started, finished: $finished, duration_s: $duration,
      place: $place,
      saved_version: (if $version == "" then null else ($version | tonumber) end),
      passed: ($result.passed? // 0), failed: ($result.failed? // 0),
      specs: ($result.specs? // null), skipped_specs: $skipped,
      failures: ($result.failures? // []),
      task_path: (if $task == "" then null else $task end), log: $log,
      studio_report: $report, gate_ready: $gate, auto_publish: false
    }' >"$STATUS_DIR/$SHA.json.tmp"
  mv "$STATUS_DIR/$SHA.json.tmp" "$STATUS_DIR/$SHA.json"
  cp "$STATUS_DIR/$SHA.json" "$STATUS_DIR/latest.json.tmp"
  mv "$STATUS_DIR/latest.json.tmp" "$STATUS_DIR/latest.json"
  publish_hook "$status"
  case "$status" in
    pass) exit 0 ;;
    fail) exit 1 ;;
    *) exit 2 ;;
  esac
}

log "cloud-tests $SHA in $GAME_DIR"
[[ -n "${ROBLOX_OPEN_CLOUD_API_KEY:-}" ]] || finish error "ROBLOX_OPEN_CLOUD_API_KEY is not set"
for tool in rojo lune jq curl; do
  command -v "$tool" >/dev/null || finish error "$tool not on PATH"
done

# 1. Build -------------------------------------------------------------------
# The specs go in ServerStorage.CloudTests with requires rewritten to the
# place's own modules. The rest of the tree is default.project.json as is,
# with $path made absolute so the project can live in $WORK.
(cd "$GAME_DIR" && lune run "$HERE/stage-specs.luau" "$WORK/CloudTests") >>"$LOG" 2>&1 ||
  finish error "stage-specs failed (see log)"
jq --arg root "$GAME_DIR" --arg tests "$WORK/CloudTests" '
  walk(if type == "object" and has("$path") then
    .["$path"] |= (if type == "string" then "\($root)/\(.)" else map_values("\($root)/\(.)") end)
  else . end)
  | .tree.ServerStorage = {"$className": "ServerStorage", "CloudTests": {"$path": $tests}}
' "$GAME_DIR/default.project.json" >"$WORK/cloud-tests.project.json" || finish error "project rewrite failed"
PLACE="$WORK/steal-a-slime-cloud-tests.rbxl"
rojo build "$WORK/cloud-tests.project.json" -o "$PLACE" >>"$LOG" 2>&1 || finish error "rojo build failed (see log)"
log "built $(du -h "$PLACE" | cut -f1) place"

# 2. Upload Saved --------------------------------------------------------------
cloud_retry "$UPLOAD_BACKOFF" -X POST -H 'Content-Type: application/octet-stream' \
  --data-binary @"$PLACE" \
  "$API/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions?versionType=Saved"
BODY="$(cat "$WORK/resp")"
log "upload Saved: HTTP $HTTP_CODE $BODY"
[[ "$HTTP_CODE" == 200 ]] || finish error "upload Saved failed: HTTP $HTTP_CODE"
SAVED_VERSION="$(echo "$BODY" | jq -r '.versionNumber // empty')"
[[ "$SAVED_VERSION" =~ ^[0-9]+$ ]] || finish error "upload response has no versionNumber"

# 3. Luau Execution against that version ---------------------------------------------
jq -n --rawfile script "$HERE/cloud-tests.luau" --arg timeout "$TASK_TIMEOUT" \
  '{script: $script, timeout: $timeout}' >"$WORK/task.json"
cloud_retry "$TASK_BACKOFF" -X POST -H 'Content-Type: application/json' --data-binary @"$WORK/task.json" \
  "$API/cloud/v2/universes/$UNIVERSE_ID/places/$PLACE_ID/versions/$SAVED_VERSION/luau-execution-session-tasks"
BODY="$(cat "$WORK/resp")"
[[ "$HTTP_CODE" == 200 ]] || {
  log "create task: HTTP $HTTP_CODE $BODY"
  finish error "create task failed: HTTP $HTTP_CODE"
}
TASK_PATH="$(echo "$BODY" | jq -r '.path // empty')"
[[ -n "$TASK_PATH" ]] || finish error "create task response has no path"
log "task $TASK_PATH"

STATE=""
DEADLINE=$(($(date +%s) + POLL_LIMIT_S))
while [[ $(date +%s) -lt $DEADLINE ]]; do
  sleep 3
  TASK="$(cloud "$API/cloud/v2/$TASK_PATH")" || continue
  STATE="$(echo "$TASK" | jq -r '.state // empty' 2>/dev/null)"
  case "$STATE" in
    COMPLETE | FAILED | CANCELLED) break ;;
  esac
done
log "task state: ${STATE:-unknown}"
{
  echo "--- task logs"
  cloud "$API/cloud/v2/$TASK_PATH/logs?maxPageSize=1000" |
    jq -r '.luauExecutionSessionTaskLogs[]?.messages[]?' 2>/dev/null
  echo "--- end task logs"
} >>"$LOG"

case "$STATE" in
  COMPLETE) ;;
  FAILED | CANCELLED)
    log "task error: $(echo "$TASK" | jq -c '.error // {}')"
    finish error "luau execution $STATE"
    ;;
  *) finish error "luau execution did not finish within ${POLL_LIMIT_S}s (state ${STATE:-unknown})" ;;
esac

# 4. Result ---------------------------------------------------------------
RESULT="$(echo "$TASK" | jq -c '.output.results[0]? | if type == "string" then (fromjson? // null) else . end | if type == "object" then . else null end')"
[[ "$RESULT" != null && -n "$RESULT" ]] || {
  RESULT=null
  finish error "task returned no JSON result"
}
log "result: $(echo "$RESULT" | jq -c '{ok, passed, failed, specs, error}')"
if echo "$RESULT" | jq -e '.error' >/dev/null; then
  finish error "$(echo "$RESULT" | jq -r .error)"
elif echo "$RESULT" | jq -e '.ok == true' >/dev/null; then
  finish pass "$(echo "$RESULT" | jq -r '"\(.passed) passed in \(.specs) specs"')"
else
  finish fail "$(echo "$RESULT" | jq -r '"\(.failed) failed, \(.passed) passed"')"
fi
