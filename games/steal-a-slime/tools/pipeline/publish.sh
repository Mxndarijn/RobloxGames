#!/usr/bin/env bash
# Release stage for Steal a Slime (see docs/release-pipeline.md).
#
#   tools/pipeline/publish.sh <checkout-dir> <sha>
#   AUTO_PUBLISH=1 ROBLOX_OPEN_CLOUD_API_KEY=... tools/pipeline/publish.sh <checkout-dir> <sha>
#   DRY_RUN=1 AUTO_PUBLISH=1 tools/pipeline/publish.sh <checkout-dir> <sha>
#
# 1. gate: status/<sha>.json pass AND a valid Phoenix Studio report that is a FULL run
#    (report run_kind == "full"; partial PC-watcher runs, or reports without run_kind,
#    never gate a publish, whatever their status),
# 2. only with AUTO_PUBLISH=1: clean build (no CloudTests) -> upload Saved ->
#    smoke test that version -> terrain-burial probe on that version (blocking) ->
#    upload the same clean file as Published -> burial probe on the published version (alert only).
#    The cloud-test Saved version is never promoted.
# DRY_RUN=1 evaluates the gate, builds + asserts, prints the calls it would make
# and writes nothing outside $WORK. The key reaches curl on stdin only.
#
# Newest fully-gated only (first-parent order of $MAIN_REF). Fully gated = cloud pass +
# FULL Studio report pass + frames_reviewed + reviewed_by + checked_at after merge. A sha is
# skipped-superseded ONLY when a newer sha is itself fully gated or published, or when a
# live sha already descends from it (never publish older than live). A newer sha that is
# merely cloud-passed does not supersede, so review lag cannot starve the pipeline: the
# newest gated sha publishes while newer un-reviewed ones keep waiting. A waiting sha has
# no terminal timeout (REPORT_TIMEOUT_S only flavours the log). Checked at the start and
# again right before each upload. SUPERSEDE_ONLY=1 stops after that check.
#
# Needs-review marker: while $SHA has cloud pass but Phoenix has not yet reviewed
# frames (no Studio report, a report that is not run_kind full, or a full report with
# status=pass and frames_reviewed != true) and no
# newer sha is also waiting for review (only the newest keeps it), an empty file $NEEDS_REVIEW_DIR/<40-char sha> exists so Gojo can ping Phoenix. It is
# removed once frames_reviewed is true, the report is fail, or the sha ends
# live / skipped-superseded / no-publish / smoke-failed / burial-failed. Honoured under DRY_RUN too.
# Setting the marker also asks the PC watcher for a full run: best-effort write of
# studio-reports/requests/<sha>.json on branch studio-reports (once per sha: stamp
# $STATUS_DIR/<sha>.full-request written after a successful write, so failures retry; FULL_REQUEST=0 disables; FULL_REQUEST_CMD overrides
# the writer, called as: FULL_REQUEST_CMD <full-sha>).
#
# A sha already live / smoke-failed / burial-failed / no-publish / skipped-superseded (or with live/<sha>.json
# status live) is a no-op: exit 0, nothing uploaded.
#
# Exit: 0 live / ready / noop / dry-run ok, 3 pending (retry next tick),
#       4 no-publish or skipped-superseded (terminal), 2 error (retry),
#       5 smoke failed (terminal-ish: not published),
#       6 burial-failed (terrain_burial probe FAILed on the saved version with terrain ready: not published).
# Burial probe (tools/livetest/cloud/terrain_burial.luau): pre-publish FAIL blocks; an inconclusive
# probe (error, terrain not ready, no grounded parts) only warns. Post-publish it never changes the
# exit code: a FAIL writes $PIPE/alerts/<sha>.burial.json and logs "ALERT burial FAIL"; no rollback.
# BURIAL_GATE=off skips both probes.
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
FULL_REQUEST="${FULL_REQUEST:-1}"
FULL_REQUEST_CMD="${FULL_REQUEST_CMD:-}"
BURIAL_GATE="${BURIAL_GATE:-on}"
CLOUD_RUN="${CLOUD_RUN:-$HERE/../livetest/cloud/run.sh}"
BURIAL_SCRIPT="${BURIAL_SCRIPT:-$HERE/../livetest/cloud/terrain_burial.luau}"
ALERTS_DIR="${ALERTS_DIR:-$PIPE/alerts}"
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
# request_full_run: best-effort candidate signal to the PC watcher (it cannot see the box).
# Writes studio-reports/requests/<sha>.json on branch studio-reports; attempted once per sha.
# The stamp has no .json extension: watch.sh globs *.json in $STATUS_DIR.
request_full_run() {
  local path="studio-reports/requests/$FULL_SHA.json" stamp="$STATUS_DIR/$SHA.full-request" body
  [[ "$FULL_REQUEST" == 1 && -n "$FULL_SHA" && ! -e "$stamp" ]] || return 0
  if [[ "$DRY_RUN" == 1 ]]; then
    log "DRY_RUN: would request full Studio run ($path)"
    return 0
  fi
  # The stamp is written only once the request exists, so a failed write is retried next tick.
  if [[ -n "$FULL_REQUEST_CMD" ]]; then
    if "$FULL_REQUEST_CMD" "$FULL_SHA"; then date -Iseconds >"$stamp"; else log "full-run request: FULL_REQUEST_CMD failed (retried next tick)"; fi
    return 0
  fi
  if ghbot-gojo api "repos/$REPO_SLUG/contents/$path?ref=studio-reports" --jq .sha >/dev/null 2>&1; then
    log "full-run request: $path already exists"
    date -Iseconds >"$stamp"
    return 0
  fi
  body="$(jq -n --arg sha "$FULL_SHA" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{sha: $sha, requested_at: $at, by: "publish.sh", reason: "needs-review: cloud pass, no full reviewed Studio report"}' | base64 -w0)" || body=""
  if [[ -n "$body" ]] && ghbot-gojo api -X PUT "repos/$REPO_SLUG/contents/$path" \
    -f message="studio-reports: request full run for ${FULL_SHA:0:12}" -f branch=studio-reports -f content="$body" >/dev/null 2>&1; then
    log "full-run request: wrote $path"
    date -Iseconds >"$stamp"
  else
    log "full-run request: could not write $path (retried next tick)"
  fi
}
needs_review_set() {
  [[ -n "$FULL_SHA" ]] || return 0
  case "$(jq -r .status "$STATUS_DIR/$SHA.publish.json" 2>/dev/null)" in "" | ready) ;; *) return 0 ;; esac # terminal: never re-mark
  mkdir -p "$NEEDS_REVIEW_DIR" && touch "$NEEDS_REVIEW_DIR/$FULL_SHA"
  log "needs-review: marker set ($NEEDS_REVIEW_DIR/$FULL_SHA)"
  request_full_run
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

# write_live_status <saved> <published> <merged_at>: writes status/<sha>.publish.json and
# live/<sha>.json. The ~150KB studio report goes in via a file (--slurpfile), never argv
# (--argjson "$REPORT" died with "Argument list too long").
write_live_status() {
  mkdir -p "$LIVE_DIR" "$STATUS_DIR"
  printf '%s' "$REPORT" >"$WORK/studio_report.json"
  jq -n --arg sha "$SHA" --argjson saved "$1" --argjson published "$2" --arg at "$(date -Iseconds)" \
    --arg place "$UNIVERSE_ID/$PLACE_ID" --slurpfile report "$WORK/studio_report.json" --arg merged "$3" \
    '{sha: $sha, status: "live", saved_version: $saved, published_version: $published, smoke: "pass",
      place: $place, merged_at: $merged, published_at: $at, studio_report: $report[0],
      frames_reviewed: ($report[0].frames_reviewed // false), reviewed_by: ($report[0].reviewed_by // [])}' >"$WORK/live.json" || return 1
  write_json "$STATUS_DIR/$SHA.publish.json" <"$WORK/live.json" &&
    write_json "$LIVE_DIR/$SHA.json" <"$WORK/live.json"
}
# run_burial_probe <version> <outfile>: runs the burial probe on a place version. The probe sets
# ok=pass, so run.sh's exit code is ignored; the verdict comes from burial_verdict.
run_burial_probe() {
  OUT="$2" TIMEOUT=300s "$CLOUD_RUN" "$BURIAL_SCRIPT" "$1" >>"$LOG" 2>&1 || true
}
# burial_verdict <outfile>: prints pass | fail | inconclusive (missing/errored/terrain not ready/no grounded parts).
burial_verdict() {
  jq -r '.result as $r | if ($r | type) != "object" then "inconclusive"
    elif $r.pass == true then "pass"
    elif ($r.result == "FAIL" or $r.pass == false) and $r.terrain_ready == true and (($r.grounded_parts // 0) > 0) then "fail"
    else "inconclusive" end' "$1" 2>/dev/null || echo inconclusive
}
# burial_json <outfile> <version> <verdict>: {result, summary, over_threshold, worst (top 10), version, at}
burial_json() {
  jq -c --argjson version "$2" --arg verdict "$3" --arg at "$(date -Iseconds)" \
    '(.result // {}) as $r | {result: ($verdict | ascii_upcase), summary: ($r.summary // null), over_threshold: ($r.over_threshold // null),
      worst: (($r.worst // [])[:10]), version: $version, at: $at}' "$1" 2>/dev/null ||
    jq -nc --argjson version "$2" --arg at "$(date -Iseconds)" '{result: "INCONCLUSIVE", summary: null, over_threshold: null, worst: [], version: $version, at: $at}'
}
[[ "${PUBLISH_LIB_ONLY:-0}" == 1 ]] && return 0 # tests source the helpers above

# noop_if_done: exit 0 when $SHA already ended in a terminal state, or live/<sha>.json says
# live (covers an empty/corrupt publish.json left by a publish that died at the final write).
noop_if_done() {
  local cur live_st
  cur="$(jq -r '.status // empty' "$STATUS_DIR/$SHA.publish.json" 2>/dev/null)"
  case "$cur" in live | smoke-failed | burial-failed | no-publish | skipped-superseded) ;; *)
    live_st="$(jq -r '.status // empty' "$LIVE_DIR/$SHA.json" 2>/dev/null)"
    [[ "$live_st" == live ]] || return 0
    cur="live (live/$SHA.json)" ;;
  esac
  log "noop: already $cur"
  needs_review_clear
  exit 0
}

# ---- gate helpers ------------------------------------------------------------
# Report source: local mirror, GitHub API when the mirror file is missing or
# the mirror hasn't been refreshed for MIRROR_STALE_S.
mirror_fresh() {
  [[ -d "$STUDIO_REPORTS_DIR" ]] || return 1
  local newest now
  newest="$(find "$STUDIO_REPORTS_DIR" -maxdepth 1 -printf '%T@\n' | sort -n | tail -1)"
  now="$(date +%s)"
  [[ -n "$newest" ]] && (( now - ${newest%.*} <= MIRROR_STALE_S ))
}
fetch_report() { # fetch_report <sha>: prints report JSON on stdout, empty if none
  local f="$STUDIO_REPORTS_DIR/$1.json" api
  if [[ -f "$f" ]] && mirror_fresh; then
    cat "$f"
    return
  fi
  log "report: mirror file missing or mirror stale; GET repos/$REPO_SLUG/contents/studio-reports/$1.json?ref=studio-reports"
  api="$(ghbot-gojo api "repos/$REPO_SLUG/contents/studio-reports/$1.json?ref=studio-reports" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)"
  if [[ -n "$api" ]]; then echo "$api"; elif [[ -f "$f" ]]; then cat "$f"; fi # API down: stale mirror beats nothing
}

# report_problem <sha> <report> <merge-time>: reason on stdout when the report is
# missing/incomplete/stale/not-full, nothing when valid (a valid FULL status=fail report is "valid";
# a partial or run_kind-less report is never valid, whatever its status).
report_problem() {
  local sha="$1" report="$2" merge="$3" checked
  [[ -n "$report" ]] || { echo "no studio report"; return; }
  echo "$report" | jq -e . >/dev/null 2>&1 || { echo "report is not valid JSON"; return; }
  echo "$report" | jq -r --arg sha "$sha" '
    if .sha != $sha then "report sha mismatch"
    elif .run_kind != "full" then "report run_kind is not full (partial Studio runs never gate a publish)"
    elif .status != "pass" and .status != "fail" then "report status not pass|fail"
    elif (.checked_at | type) != "string" then "report has no checked_at"
    elif .frames_reviewed != true then "frames_reviewed is not true"
    elif ((.reviewed_by | type) != "array") or ((.reviewed_by | length) == 0) or (any(.reviewed_by[]; (type != "string") or . == "")) then "reviewed_by empty"
    else empty end' | { read -r p; echo "$p"; } | grep . && return
  checked="$(epoch "$(echo "$report" | jq -r .checked_at)")" || checked=""
  if [[ -z "$checked" ]]; then echo "checked_at unparseable"
  elif (( checked <= $(epoch "$merge") )); then echo "checked_at ($(echo "$report" | jq -r .checked_at)) is not later than merge time ($merge)"
  fi
}

# eval_gate <sha>: sets G_STATE, G_REPORT, G_PROBLEM, G_UNREVIEWED, G_MERGE.
#   G_STATE: nocloud (no/pending status) | cloudfail | cloudpass-only (waiting on the
#            Studio report/frame review) | reportfail | gated (cloud pass + valid pass report)
#   G_UNREVIEWED=1: cloud pass and Phoenix has not reviewed frames yet (needs-review).
eval_gate() {
  local s="$1" cloud
  G_STATE=nocloud G_REPORT="" G_PROBLEM="" G_UNREVIEWED=0 G_MERGE=""
  [[ -f "$STATUS_DIR/$s.json" ]] || { G_PROBLEM="no cloud-test status for $s"; return; }
  cloud="$(jq -r .status "$STATUS_DIR/$s.json" 2>/dev/null)"
  case "$cloud" in
    pass) ;;
    fail) G_STATE=cloudfail; G_PROBLEM="cloud tests failed"; return ;;
    *) G_PROBLEM="cloud status '$cloud'"; return ;;
  esac
  G_MERGE="$(git -C "$CHECKOUT" show -s --format=%cI "$s" 2>/dev/null)" || { G_MERGE=""; G_PROBLEM="sha $s not in checkout"; return; }
  G_REPORT="$(fetch_report "$s")"
  if [[ -z "$G_REPORT" ]] ||
    echo "$G_REPORT" | jq -e --arg sha "$s" '.sha == $sha and (.run_kind != "full" or (.status == "pass" and .frames_reviewed != true))' >/dev/null 2>&1; then
    G_UNREVIEWED=1
  fi
  G_PROBLEM="$(report_problem "$s" "$G_REPORT" "$G_MERGE")"
  G_STATE=cloudpass-only
  if [[ -z "$G_PROBLEM" ]]; then
    if [[ "$(echo "$G_REPORT" | jq -r .status)" == fail ]]; then G_STATE=reportfail; else G_STATE=gated; fi
  fi
}

# sha_terminal <sha>: true when status/<sha>.publish.json is a terminal state.
sha_terminal() {
  case "$(jq -r '.status // empty' "$STATUS_DIR/$1.publish.json" 2>/dev/null)" in
    live | smoke-failed | burial-failed | no-publish | skipped-superseded) return 0 ;;
  esac
  [[ "$(jq -r '.status // empty' "$LIVE_DIR/$1.json" 2>/dev/null)" == live ]]
}

# live_shas: every sha with live/<sha>.json status live.
live_shas() {
  local f
  for f in "$LIVE_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    [[ "$(jq -r '.status // empty' "$f" 2>/dev/null)" == live ]] && basename "$f" .json
  done
}

# newer_shas: shas strictly newer than $SHA on $MAIN_REF (first-parent), newest first.
# Prints nothing when $SHA is not on the first-parent line.
newer_shas() {
  local n found=0 newer=()
  while read -r n; do
    [[ "$n" == "$SHA" ]] && { found=1; break; }
    newer+=("$n")
  done < <(git -C "$CHECKOUT" rev-list --first-parent "$MAIN_REF" 2>/dev/null)
  [[ $found == 1 ]] && printf '%s\n' "${newer[@]}"
}

# superseder: prints "<sha> <why>" when $SHA must not be published: a live sha that
# $SHA is an ancestor of (never publish older than live), or a newer sha that is fully
# gated or already published. Nothing otherwise. A newer sha that is merely cloud-passed
# does NOT supersede (that is the starvation bug).
superseder() {
  local l n
  FULL="${FULL_SHA:-$SHA}"
  while read -r l; do
    [[ "$l" == "$FULL" || "$l" == "$SHA" ]] && continue
    git -C "$CHECKOUT" merge-base --is-ancestor "$FULL" "$l" 2>/dev/null && { echo "$l already live (not older than live)"; return; }
  done < <(live_shas)
  while read -r n; do
    [[ -n "$n" ]] || continue
    sha_terminal "$n" && [[ "$(jq -r '.status // empty' "$STATUS_DIR/$n.publish.json" 2>/dev/null)" == live ]] && { echo "$n published"; return; }
    eval_gate "$n"
    [[ "$G_STATE" == gated ]] && { echo "$n fully gated"; return; }
  done < <(newer_shas)
}
# check_superseded: writes skipped-superseded and exits 4 when superseder() finds one.
# Shas that already ended live / no-publish / smoke-failed / burial-failed are left alone.
check_superseded() {
  local cur by why
  cur="$(jq -r .status "$STATUS_DIR/$SHA.publish.json" 2>/dev/null)"
  case "$cur" in "" | ready) ;; *) needs_review_clear; return 0 ;; esac
  read -r by why <<<"$(superseder)"
  [[ -n "$by" ]] || return 0
  log "skipped-superseded: $by $why (superseded_by=$by)"
  needs_review_clear
  if [[ "$DRY_RUN" == 1 ]]; then
    log "DRY_RUN: would write $STATUS_DIR/$SHA.publish.json status=skipped-superseded superseded_by=$by"
  else
    jq -n --arg sha "$SHA" --arg by "$by" --arg why "$why" --arg at "$(date -Iseconds)" \
      '{sha: $sha, status: "skipped-superseded", superseded_by: $by, reason: ("newer sha " + $why), at: $at}' |
      write_json "$STATUS_DIR/$SHA.publish.json"
  fi
  exit 4
}

# newest_unreviewed_here: true when no sha newer than $SHA is itself a live candidate
# waiting for frame review (cloud pass, non-terminal, unreviewed). Only the newest one
# keeps a needs-review marker.
newest_unreviewed_here() {
  local n
  while read -r n; do
    [[ -n "$n" ]] || continue
    sha_terminal "$n" && continue
    eval_gate "$n"
    [[ "$G_STATE" == cloudpass-only && "$G_UNREVIEWED" == 1 ]] && return 1
  done < <(newer_shas)
  return 0
}

# ---- gate ----------------------------------------------------------------
noop_if_done
check_superseded
[[ "$SUPERSEDE_ONLY" == 1 ]] && exit 0
eval_gate "$SHA"
CLOUD_FINISHED="$(jq -r '.finished // empty' "$STATUS_DIR/$SHA.json" 2>/dev/null)"
case "$G_STATE" in
  nocloud) log "blocked: $G_PROBLEM"; exit 3 ;;
  cloudfail) terminal no-publish "cloud tests failed"; exit 4 ;;
esac
if [[ -z "$G_MERGE" ]]; then log "error: $G_PROBLEM"; exit 2; fi
MERGE_TIME="$G_MERGE"

# Needs-review marker: only the newest un-reviewed cloud-pass sha keeps one.
if [[ "$G_UNREVIEWED" == 1 ]] && newest_unreviewed_here; then needs_review_set; else needs_review_clear; fi
eval_gate "$SHA" # newest_unreviewed_here clobbered the G_* state

if [[ "$G_STATE" == reportfail ]]; then terminal no-publish "studio report status=fail"; exit 4; fi
if [[ "$G_STATE" != gated ]]; then
  # Never terminal: a sha waiting for review only loses to a newer *gated* sha
  # (handled by check_superseded above), so it cannot starve the pipeline.
  FIN="$(epoch "$CLOUD_FINISHED" || echo 0)"
  AGE=$(( $(date +%s) - FIN ))
  log "blocked: $G_PROBLEM (cloud pass ${AGE}s ago$( ((AGE > REPORT_TIMEOUT_S)) && echo ", past ${REPORT_TIMEOUT_S}s: still waiting, no newer gated sha"))"
  exit 3
fi
REPORT="$G_REPORT"
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
  if [[ "$BURIAL_GATE" == off ]]; then
    log "  2b/5. BURIAL_GATE=off: burial probes skipped"
  else
    log "  2b. run.sh tools/livetest/cloud/terrain_burial.luau <saved_version> (TIMEOUT=300s); FAIL with terrain ready => status burial-failed, exit 6, not published; inconclusive => WARN, continue"
  fi
  log "  3. POST $UP?versionType=Published  (same clean place file) -> published_version"
  log "  4. write $STATUS_DIR/$SHA.publish.json {status: live} and $LIVE_DIR/$SHA.json"
  [[ "$BURIAL_GATE" == off ]] || log "  5. run.sh terrain_burial.luau <published_version>; record burial in live/<sha>.json; FAIL => $ALERTS_DIR/$SHA.burial.json + 'ALERT burial FAIL' (exit stays 0, no rollback)"
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
if OUT="$SMOKE_OUT" "$CLOUD_RUN" "$HERE/../livetest/cloud/smoke.luau" "$SAVED" >>"$LOG" 2>&1; then
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

# ---- terrain burial probe on the saved version (blocking only on a conclusive FAIL) ------
if [[ "$BURIAL_GATE" == off ]]; then
  log "burial: BURIAL_GATE=off, skipping pre-publish probe"
else
  BURIAL_PRE="$WORK/burial-pre.json"
  run_burial_probe "$SAVED" "$BURIAL_PRE"
  BV="$(burial_verdict "$BURIAL_PRE")"
  log "burial on saved version $SAVED: $BV $(jq -r '.result.summary // empty' "$BURIAL_PRE" 2>/dev/null)"
  case "$BV" in
    fail)
      needs_review_clear
      burial_json "$BURIAL_PRE" "$SAVED" fail >"$WORK/burial.json"
      jq -n --arg sha "$SHA" --argjson saved "$SAVED" --arg at "$(date -Iseconds)" --slurpfile b "$WORK/burial.json" \
        '{sha: $sha, status: "burial-failed", saved_version: $saved, smoke: "pass", burial: $b[0], summary: $b[0].summary, worst: $b[0].worst, at: $at}' |
        write_json "$STATUS_DIR/$SHA.publish.json"
      exit 6 ;;
    pass) ;;
    *) log "WARN burial probe inconclusive on saved version $SAVED (error, terrain not ready or no grounded parts); continuing" ;;
  esac
fi

# ---- publish the clean file -------------------------------------------------
check_superseded # a newer sha may have passed while this one was building / smoking
PUBLISHED="$(upload Published)" && [[ "$PUBLISHED" =~ ^[0-9]+$ ]] || { log "error: upload Published failed"; exit 2; }
log "LIVE: $SHA published as place version $PUBLISHED (clean saved $SAVED)"
write_live_status "$SAVED" "$PUBLISHED" "$MERGE_TIME"
needs_review_clear

# ---- terrain burial probe on the published version (alert only: no rollback, exit stays 0) ---
if [[ "$BURIAL_GATE" == off ]]; then
  log "burial: BURIAL_GATE=off, skipping post-publish probe"
else
  BURIAL_POST="$WORK/burial-post.json"
  run_burial_probe "$PUBLISHED" "$BURIAL_POST"
  BV="$(burial_verdict "$BURIAL_POST")"
  burial_json "$BURIAL_POST" "$PUBLISHED" "$BV" >"$WORK/burial.json"
  log "burial on published version $PUBLISHED: $BV"
  for f in "$LIVE_DIR/$SHA.json" "$STATUS_DIR/$SHA.publish.json"; do
    jq --slurpfile b "$WORK/burial.json" '. + {burial: $b[0]}' "$f" >"$WORK/burial-merge.json" 2>/dev/null && write_json "$f" <"$WORK/burial-merge.json"
  done
  if [[ "$BV" == fail ]]; then
    mkdir -p "$ALERTS_DIR" && write_json "$ALERTS_DIR/$SHA.burial.json" <"$WORK/burial.json"
    log "ALERT burial FAIL: $SHA live as version $PUBLISHED: $(jq -r .summary "$WORK/burial.json")"
  elif [[ "$BV" != pass ]]; then
    log "WARN burial probe inconclusive on published version $PUBLISHED"
  fi
fi
exit 0
