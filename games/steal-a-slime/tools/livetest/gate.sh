#!/usr/bin/env bash
# Release gate: build -> local checks -> upload as Saved -> Luau Execution live
# check of THAT saved version. Never publishes: going live is a separate,
# human-approved step (Merijn OKs every live publish).
#
#   ROBLOX_OPEN_CLOUD_API_KEY=... tools/livetest/gate.sh [place.rbxl]
#
# Without a place file it builds one with rojo (binary .rbxl, from the working tree).
# Env:
#   SKIP_CHECKS=1  skip the local checks (lune tests, selene, stylua, check-place)
#
# Live gate (tools/livetest/cloud/live.luau -> result.gate): slimes > 0 (the
# v10 SlimeMesh shim doesn't count), every plot Sign has non-empty text, no
# require/step/loop/script errors during the replayed boot.
# Results land in tools/livetest/results/gate-v<N>-<ts>.json.
# Exit 0 = gate passed on the Saved version; 1 = local checks or gate failed;
# 2 = upload/HTTP/tooling error.
# The key reaches curl on stdin (-H @-): never in argv, never on disk, never echoed.
set -euo pipefail

cd "$(dirname "$0")/../.."
export PATH="$HOME/.local/bin:$PATH"
UNIVERSE_ID="${UNIVERSE_ID:-10770917350}"
PLACE_ID="${PLACE_ID:-135787188192378}"
RESULTS=tools/livetest/results
TS="$(date +%Y%m%d-%H%M%S)"

if [[ -z "${ROBLOX_OPEN_CLOUD_API_KEY:-}" ]]; then
  echo "ROBLOX_OPEN_CLOUD_API_KEY is not set" >&2
  exit 2
fi

PLACE="${1:-}"
if [[ -z "$PLACE" ]]; then
  PLACE="$(mktemp -d)/steal-a-slime.rbxl"
  rojo build -o "$PLACE" >/dev/null
  echo "built: $PLACE ($(git rev-parse --short HEAD)$(git diff --quiet -- src default.project.json world || echo ', dirty'))"
fi

if [[ "${SKIP_CHECKS:-0}" != 1 ]]; then
  echo "--- local checks"
  lune run tests | tail -1
  selene src tests >/dev/null
  stylua --check src tests >/dev/null
  lune run scripts/check-place "$PLACE"
  echo "local checks: PASS"
fi

# Uploads $PLACE as a Saved version (never Published); prints the new
# versionNumber. Retries 409 "Server is busy" / 429 / 5xx with backoff (seen on 2026-10-15).
upload() {
  local resp code attempt
  for attempt in 1 2 3 4 5 6; do
    resp="$(printf 'x-api-key: %s\n' "$ROBLOX_OPEN_CLOUD_API_KEY" | curl -sS -H @- -X POST \
      -H 'Content-Type: application/octet-stream' --data-binary @"$PLACE" -w '\n%{http_code}' \
      "https://apis.roblox.com/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions?versionType=Saved")"
    code="${resp##*$'\n'}"
    resp="${resp%$'\n'*}"
    if [[ "$code" == 200 ]]; then
      echo "$resp" | jq -er .versionNumber
      return
    fi
    echo "upload Saved (attempt $attempt): HTTP $code $resp" >&2
    [[ "$code" == 409 || "$code" == 429 || "$code" == 5* ]] || return 2
    sleep $((attempt * 30))
  done
  return 2
}

# Runs live.luau against version $1, saving to $2; prints the gate summary.
live() {
  local rc=0
  OUT="$2" tools/livetest/cloud/run.sh tools/livetest/cloud/live.luau "$1" >/dev/null 2>&1 || rc=$?
  if [[ ! -s "$2" ]]; then
    echo "live check v$1: no result (run.sh exit $rc)" >&2
    return 2
  fi
  jq -c '{state, placeVersion: .result.placeVersion, gate: (.result.gate // null | if . then del(.emptySignPaths) else . end)}' "$2"
  jq -e --argjson v "$1" '.state == "COMPLETE" and .result.placeVersion == $v and .result.gate.ok == true' "$2" >/dev/null
}

echo "--- upload Saved"
SAVED="$(upload)"
echo "saved versionNumber: $SAVED"

echo "--- live gate on v$SAVED"
GATE_OUT="$RESULTS/gate-v$SAVED-$TS.json"
if ! live "$SAVED" "$GATE_OUT"; then
  echo "GATE FAIL on v$SAVED ($GATE_OUT)" >&2
  exit 1
fi
echo "GATE PASS on v$SAVED ($GATE_OUT)"
