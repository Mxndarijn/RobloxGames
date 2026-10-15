#!/usr/bin/env bash
# Runs a Luau script inside a real Roblox server for the published place via
# Open Cloud Luau Execution, polls until done, prints logs + the JSON result.
#
#   ROBLOX_OPEN_CLOUD_API_KEY=... tools/livetest/cloud/run.sh [script.luau] [placeVersion]
#   OUT=tools/livetest/results/live-$(date +%Y%m%d-%H%M%S).json ... run.sh tools/livetest/cloud/live.luau
#
# OUT (optional) gets {task, state, logs, result}; a script that returns a JSON
# string (live.luau) has it decoded into `result`.
# Default script: tools/livetest/cloud/smoke.luau. Default version: the latest
# published one. Needs an API key with luau-execution-session WRITE for the
# experience (see /guides/roblox-live-testing.md). The key reaches curl on
# stdin (-H @-): never in argv, never on disk, never echoed.
# Exit 0 = task COMPLETE and the script returned ok=true; 1 = checks failed;
# 2 = task FAILED / HTTP error.
set -euo pipefail

UNIVERSE_ID="${UNIVERSE_ID:-10770917350}"
PLACE_ID="${PLACE_ID:-135787188192378}"
SCRIPT="${1:-$(dirname "$0")/smoke.luau}"
VERSION="${2:-}"
TIMEOUT="${TIMEOUT:-300s}"
API="https://apis.roblox.com/cloud/v2"

if [[ -z "${ROBLOX_OPEN_CLOUD_API_KEY:-}" ]]; then
  echo "ROBLOX_OPEN_CLOUD_API_KEY is not set" >&2
  exit 2
fi

# curl with the key header read from stdin; the key never hits argv or disk.
cloud() {
  printf 'x-api-key: %s\n' "$ROBLOX_OPEN_CLOUD_API_KEY" | curl -sS -H @- "$@"
}

if [[ -n "$VERSION" ]]; then
  CREATE_URL="$API/universes/$UNIVERSE_ID/places/$PLACE_ID/versions/$VERSION/luau-execution-session-tasks"
else
  CREATE_URL="$API/universes/$UNIVERSE_ID/places/$PLACE_ID/luau-execution-session-tasks"
fi

BODY="$(jq -n --rawfile script "$SCRIPT" --arg timeout "$TIMEOUT" '{script: $script, timeout: $timeout}')"
CREATED="$(cloud -X POST -H 'Content-Type: application/json' --data-binary "$BODY" -w '\n%{http_code}' "$CREATE_URL")"
CODE="${CREATED##*$'\n'}"
CREATED="${CREATED%$'\n'*}"
if [[ "$CODE" != 200 ]]; then
  echo "create task: HTTP $CODE" >&2
  echo "$CREATED" | jq . >&2 2>/dev/null || echo "$CREATED" >&2
  [[ "$CODE" == 403 ]] && echo "403: the key needs luau-execution-session write for universe $UNIVERSE_ID" >&2
  exit 2
fi
TASK_PATH="$(echo "$CREATED" | jq -r .path)"
echo "task: $TASK_PATH"

STATE=""
for _ in $(seq 1 120); do
  sleep 3
  TASK="$(cloud "$API/$TASK_PATH")"
  STATE="$(echo "$TASK" | jq -r .state)"
  case "$STATE" in
    COMPLETE | FAILED | CANCELLED) break ;;
  esac
done
echo "state: $STATE"

echo "--- logs"
LOGS="$(cloud "$API/$TASK_PATH/logs?maxPageSize=1000" || echo '{}')"
echo "$LOGS" | jq -r '.luauExecutionSessionTaskLogs[]?.messages[]?' || true

# Return values arrive as output.results[0]; a JSON string is decoded.
RESULT="$(echo "$TASK" | jq '.output.results[0]? | if type == "string" then (fromjson? // .) else . end')"
if [[ -n "${OUT:-}" ]]; then
  mkdir -p "$(dirname "$OUT")"
  jq -n --arg task "$TASK_PATH" --arg state "$STATE" --argjson logs "$LOGS" --argjson result "${RESULT:-null}" \
    --argjson error "$(echo "$TASK" | jq '.error // null')" \
    '{task: $task, state: $state, error: $error, logs: [$logs.luauExecutionSessionTaskLogs[]?.messages[]?], result: $result}' >"$OUT"
  echo "saved: $OUT"
fi

echo "--- result"
if [[ "$STATE" == COMPLETE ]]; then
  echo "$RESULT" | head -c 4000
  echo
  OK="$(echo "$RESULT" | jq -r 'if type == "object" and has("ok") then .ok else "none" end')"
  [[ "$OK" == true || "$OK" == none ]] && exit 0
  exit 1
fi
echo "$TASK" | jq '.error // .'
exit 2
