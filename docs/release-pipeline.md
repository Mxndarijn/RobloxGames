# Release pipeline (Steal a Slime)

```
merge to main -> cloud tests (box) -> Studio check (Phoenix PC) -> gate -> clean build -> Saved -> smoke -> Published
```

| Stage | Where | Output |
|---|---|---|
| 1. Cloud tests | box, `tools/pipeline/cloud-test.sh` via `watch.sh` | `status/<sha>.json` (`status` pass/fail/error). Uploads a *test* Saved version (has `ServerStorage.CloudTests`). **Never promoted.** |
| 2. Studio check | Phoenix PC, in real Studio, with frame review | `<sha>.json` + `<sha>/` frames on the orphan branch `studio-reports` |
| 3. Gate + publish | box, `tools/pipeline/publish.sh` | `status/<sha>.publish.json`, `live/<sha>.json` |

## Handoff: Studio report

Pushed to the **orphan branch `studio-reports`** of `Mxndarijn/RobloxGames`: `<sha>.json` at the branch root, frames in `<sha>/`
(`studio-reports/<sha>/` once mirrored).

```json
{
  "sha": "<full 40-char sha>",
  "status": "pass",
  "checked_at": "2026-10-16T13:30:00+02:00",
  "studio_version": "0.6xx.x",
  "notes": "free text",
  "perf": {},
  "frames_reviewed": true,
  "reviewed_by": ["Phoenix"]
}
```

`status` is `"pass"` or `"fail"`; `checked_at` is ISO 8601 with offset; `perf` is free-form metrics; `frames_reviewed`
must be `true` and `reviewed_by` a non-empty array of names for the report to count.

**Mirror.** `box-pull.sh --loop 60` copies the branch to `/workspace/roblox/pipeline/studio-reports/` every 60 s and touches
`.synced`. If `<sha>.json` is missing there, or nothing in the mirror dir changed for more than 5 min (`MIRROR_STALE_S`),
`publish.sh` reads `ghbot-gojo api repos/Mxndarijn/RobloxGames/contents/<sha>.json?ref=studio-reports` instead.

## The gate for sha X

All of these must hold:

1. `status/X.json` has `status == "pass"` (cloud tests).
2. The Studio report has `sha == X` exactly, `status == "pass"`, `checked_at` later than X's commit time on main,
   `frames_reviewed == true`, `reviewed_by` a non-empty array of non-empty strings.

Outcomes (exit code of `publish.sh`):

| Case | Result |
|---|---|
| Gate passes | continue (exit 0) |
| Report missing/incomplete/stale `checked_at`, less than 30 min after cloud pass finished | **pending**, exit 3; watcher re-checks each tick |
| Same, more than 30 min (`REPORT_TIMEOUT_S`=1800) after cloud pass | `status/X.publish.json` `{"status":"no-publish","reason":...}`, exit 4, never retried |
| Report `status == "fail"`, or cloud tests `fail` | `no-publish`, exit 4 |
| Cloud status `error` | pending (the watcher retries the cloud run) |
| A newer sha on `origin/main` (first-parent order) has cloud status `pass` | `status/X.publish.json` `{"status":"skipped-superseded","superseded_by":"<newer sha>"}`, exit 4, never published |

### Newest only

Only the newest cloud-passed commit on main ships. For sha X, `publish.sh` walks `git rev-list --first-parent origin/main`
(`MAIN_REF`); if any commit newer than X has `status/<newer>.json` `status == "pass"`, X is skipped. This applies to any X
that is pending (no or incomplete report, no cloud status yet) or passing/`ready`. X that already ended `live`, `no-publish`
or `smoke-failed` is left alone, and a newer sha that is `fail`/`error`/missing does not supersede. The check runs at the
start, before each upload (Saved and Published), and `watch.sh` re-runs it (`SUPERSEDE_ONLY=1`) for `ready` shas each tick.
Test: `tools/pipeline/test-publish-dryrun.sh`.

A sha that is already `live` / `smoke-failed` / `no-publish` / `skipped-superseded` (or whose `live/<sha>.json` has `status: "live"`, even if `publish.json` is empty or corrupt) is a no-op: `publish.sh` logs `noop: already <status>`, exits 0 and uploads nothing. The live JSON embeds the studio report via `jq --slurpfile` from a temp file, never argv (ARG_MAX).
| A newer sha on `origin/main` (first-parent order) has cloud status `pass` | `status/X.publish.json` `{"status":"skipped-superseded","superseded_by":"<newer sha>"}`, exit 4, never published |

### Newest only

Only the newest cloud-passed commit on main may go live. For sha X, `publish.sh` walks `git rev-list --first-parent $MAIN_REF` (default `origin/main`) and looks at every sha newer than X. If any has `status/<newer>.json` `status == "pass"`, X is marked `skipped-superseded` (X's own state may be pending, passing or `ready`). The newest such sha is recorded as `superseded_by`. Shas that already ended `live`, `no-publish` or `smoke-failed` are left alone, as is a sha that is not on main's first-parent line.

The check runs at the start, again before writing `ready`, before the Saved upload, and again right before the Published upload (a newer sha can pass while X builds or is smoke-tested). `SUPERSEDE_ONLY=1` stops after the first check; `watch.sh` uses it to retire `ready` shas. Dry-run tests: `tools/pipeline/test-publish-dryrun.sh`.

### Needs-review markers

So Gojo can ping Phoenix, `publish.sh` keeps an empty file `$NEEDS_REVIEW_DIR/<full 40-char sha>` (default `/workspace/roblox/pipeline/needs-review`, created with `mkdir -p`) while X has cloud `pass` and frames still need review:

- written when there is no Studio report yet, or the report has `status == "pass"` but `frames_reviewed` is not `true`;
- removed when `frames_reviewed` is `true`, the report is `fail`, or X ends `live`, `skipped-superseded`, `no-publish` or `smoke-failed` (including the `SUPERSEDE_ONLY=1` path). A sha with a terminal publish status is never re-marked.

Every `publish.sh` run that evaluates the gate refreshes the marker. `NEEDS_REVIEW_DIR` is honoured under `DRY_RUN=1` (the tests point it at a temp dir). Cloud `fail`/`error`/pending shas get no marker.

## Publishing

`AUTO_PUBLISH` (default `0`). With `0`, a passing gate only writes `status/X.publish.json` `{"status":"ready"}`; nothing is uploaded.

With `AUTO_PUBLISH=1`, after the gate:

1. `rojo build default.project.json` of the checkout at X (normal project, no specs). Asserts `ServerStorage.CloudTests` is absent (checked in the built `.rbxlx` and the project).
2. Upload as `versionType=Saved` to universe 10770917350 / place 135787188192378 (409/429/5xx backoff 1, 2, 4, 8 min).
3. `tools/livetest/cloud/run.sh smoke.luau <saved_version>` (Luau Execution on that exact version). If it fails: `publish.json` `status:"smoke-failed"`, exit 5, **not published**.
4. Upload the same clean file as `versionType=Published`, log the version.
5. Write `status/X.publish.json` and `live/X.json`:
   `{"sha","status":"live","saved_version","published_version","smoke":"pass","place","merged_at","published_at","studio_report":{...}}`.

The Saved version from stage 1 is never promoted. The key is sent to curl on stdin (`-H @-`) only.

`DRY_RUN=1`: evaluates the gate, does the clean build and assertion, prints the exact calls it would make (URLs above), writes nothing and uploads nothing. Only the optional GitHub API read can touch the network.

## Wiring

- `cloud-test.sh`'s `publish_hook` calls `publish.sh` after a pass (the report is usually not there yet, so it stays pending).
- `watch.sh` runs `publish.sh` each tick for every cloud-passed sha (last 2 days) without a `status/<sha>.publish.json`, so pending shas are re-checked until they end `live`, `no-publish`, `skipped-superseded` or `smoke-failed`. A `ready` sha is re-checked every tick with `SUPERSEDE_ONLY=1` so a newer pass still retires it. `AUTO_PUBLISH` comes from `~/.config/roblox-ci.env`.
