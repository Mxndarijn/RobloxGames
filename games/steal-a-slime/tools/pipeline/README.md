# Main-branch cloud test stage

`tools/pipeline/cloud-test.sh` runs the server specs inside a real Roblox
server for one commit. It uploads the build as a **Saved** version and never
publishes; `publish.sh` is the separate, gated release step.

```sh
ROBLOX_OPEN_CLOUD_API_KEY=... tools/pipeline/cloud-test.sh <repo-checkout> <sha>
```

Exit 0 = pass, 1 = test failures, 2 = error (build, upload or task).

## What it does

1. **Stage the specs.** `lune run tools/pipeline/stage-specs <dir>` copies
   `tests/*.luau` (not `tests/ui`) and rewrites their Lune string requires to
   the place's real instances, using the `default.project.json` mapping:
   `../src/shared/X` becomes `ReplicatedStorage.Shared.X`, `../src/server/X`
   becomes `ServerScriptService.Server.X`, `./X` becomes `script.Parent.X`,
   and so on. The specs then test the modules the place ships, not copies.
   Files that need Lune (`@lune/*`, `../tools`, `../scripts`) are left out,
   and so is anything that names a DataStore API. The status lists them under
   `skipped_specs`; those specs keep running under `lune run tests` only.
   `TestRunner` gets one line, `TestRunner._tests = tests`, so the runner can
   report each failure by name. Specs are side-effect scripts with no
   `return`, but a ModuleScript must return exactly one value, so each staged
   `*.spec` without a top-level return gets `return true` appended. Otherwise
   Open Cloud reports "Module code did not return exactly one value" per spec.
2. **Build.** `rojo build` of `default.project.json`, plus
   `ServerStorage.CloudTests` (the staged specs). The project is generated
   in a temp dir with absolute `$path`s, so the checkout isn't touched.
   `world/*.rbxmx` are tracked, so `scripts/gen-world` doesn't need to run.
3. **Upload Saved** to universe 10770917350 / place 135787188192378.
   409 / 429 / 5xx are retried with a 1, 2, 4, 8 min backoff (`UPLOAD_BACKOFF`).
4. **Run** `tools/pipeline/cloud-tests.luau` through Open Cloud Luau
   Execution against *that* version
   (`.../places/<id>/versions/<n>/luau-execution-session-tasks`). It sets
   `DataStoreMode = "Memory"` first, requires every
   `ServerStorage.CloudTests.*.spec`, runs the registered tests and returns
   `{ok, passed, failed, total, specs, failures: [{name, error}]}`. A spec
   that fails to load counts as one failure named `<spec> (load)`.
5. **Write the status file**, check for a Studio report, and call the
   publish hook (`publish.sh`).

### Why a test-only build

The specs are not in the shipped place, and the Luau Execution script runs
against a stored version. So the stage uploads its own Saved version: the
normal tree plus a `ServerStorage.CloudTests` folder of ModuleScripts. Nothing
runs them, and `ServerStorage` doesn't replicate. **Don't publish this Saved
version.** Release builds still come from `rojo build` of `default.project.json`
(see `/guides/roblox-release-process.md`).

Stage tools (`stage-specs.luau`, `cloud-tests.luau`) are loaded from the
script's own directory, and specs from `<repo-checkout>`. So a newer script
can test an older sha.

## Environment

| Variable | Default |
|---|---|
| `ROBLOX_OPEN_CLOUD_API_KEY` | required. Sent to curl on stdin (`-H @-`), never in argv, logs or on disk |
| `STATUS_DIR` | `/workspace/roblox/pipeline/status` |
| `STUDIO_REPORTS` | `/workspace/roblox/pipeline/studio-reports` |
| `AUTO_PUBLISH` | `0`. Passed to `publish.sh`; `1` allows publishing after the gate |
| `TASK_TIMEOUT` / `POLL_LIMIT_S` | `120s` / `180` |
| `UPLOAD_BACKOFF` / `TASK_BACKOFF` | `60 120 240 480` / `5 10 20` (seconds) |

## Status file

`$STATUS_DIR/<sha>.json`, copied to `$STATUS_DIR/latest.json`. The full log
is in `$STATUS_DIR/<sha>.log`, including the task's own log lines.

```json
{
  "sha": "53479e86c64cc341261facc77751fbe2e569148f",
  "stage": "cloud-tests",
  "status": "pass | fail | error",
  "message": "612 passed in 35 specs",
  "started": "2026-10-16T10:45:00+02:00",
  "finished": "2026-10-16T10:46:10+02:00",
  "duration_s": 70,
  "place": "10770917350/135787188192378",
  "saved_version": 31,
  "passed": 612, "failed": 0, "specs": 35,
  "skipped_specs": [{ "spec": "Contract.spec", "reason": "requires \"@lune/fs\" (Lune only)" }],
  "failures": [{ "name": "Carry > drops on death", "error": "..." }],
  "task_path": "universes/.../luau-execution-session-tasks/...",
  "log": "/workspace/roblox/pipeline/status/<sha>.log",
  "studio_report": null,
  "gate_ready": false,
  "auto_publish": false
}
```

`error` means the stage couldn't produce a verdict (build, upload, task, or
missing result). It says nothing about the code.

## Studio report (Phoenix PC)

Phoenix's PC Studio check pushes `<sha>.json` to the `studio-reports` branch (mirrored to `/workspace/roblox/pipeline/studio-reports/`); the full format, with `frames_reviewed`/`reviewed_by`, is in `docs/release-pipeline.md`:

```json
{ "sha": "<full sha>", "status": "pass | fail", "run_kind": "full | partial", "checked_at": "<ISO 8601>", "studio_version": "0.6xx...", "notes": "..." }
```

The report is copied into `studio_report` when its `sha` matches.
`gate_ready` is `true` only when the cloud tests passed **and** the report says
`pass` with `run_kind == "full"` (partial PC runs never gate; `publish.sh` asks the PC for a full run via
`studio-reports/requests/<sha>.json` when it sets the needs-review marker). The script reads the report each run, so a report that arrives later
shows up on the next run for that sha.

## Publishing: publish.sh

`publish_hook` calls `tools/pipeline/publish.sh <checkout> <sha>` after a cloud
pass. It evaluates the gate (cloud pass + Studio report on the `studio-reports`
branch with `frames_reviewed` and `reviewed_by`) and only publishes with
`AUTO_PUBLISH=1` (default 0): clean build (no `CloudTests`), Saved upload,
smoke test on that version, then `versionType=Published` of the clean file.
The test Saved version from this stage is never promoted. `DRY_RUN=1` makes
no network writes. A missing report 30 min (`REPORT_TIMEOUT_S`=1800) after the
cloud pass marks the sha `no-publish`. Newest only: when a newer sha on
`origin/main` (first-parent order) has cloud status `pass`, an older pending,
passing or `ready` sha gets `status/<sha>.publish.json`
`{"status":"skipped-superseded","superseded_by":"<sha>"}` and never publishes;
this is re-checked right before each upload. Test it with
`tools/pipeline/test-publish-dryrun.sh` (temp dirs, no network). Full description, handoff JSON and flags:
`docs/release-pipeline.md`.

Needs-review marker: while a sha has cloud `pass` but no Studio report, or a
`pass` report with `frames_reviewed` not true, `publish.sh` touches an empty
`$NEEDS_REVIEW_DIR/<40-char sha>` (default `/workspace/roblox/pipeline/needs-review`).
It removes it once frames are reviewed, on report `fail`, or when the sha ends
`live` / `skipped-superseded` / `no-publish` / `smoke-failed`.

## Running it on every main commit

Outside the repo, `/workspace/roblox/pipeline/watch.sh` uses a `flock` and
fetches `origin/main` in `/workspace/roblox/RobloxGames-pipeline`, a dedicated
clone kept detached. When the sha differs from `pipeline/last-sha`, it checks
that sha out and runs its `cloud-test.sh`. Until this file is on main, it
falls back to `CLOUD_TEST_FALLBACK`. A pass or fail records the sha. An error
is retried on later ticks, up to 3 times per sha.

- systemd: `~/.config/systemd/user/roblox-cloud-tests.{service,timer}`
  (every 2 min): `systemctl --user enable --now roblox-cloud-tests.timer`
- no user systemd: `nohup /workspace/roblox/pipeline/watch-loop.sh >/dev/null 2>&1 &`

**Newest only.** `publish.sh` never publishes a sha when a newer sha on
`origin/main` (first-parent order, `MAIN_REF`) has cloud status `pass`. A
pending or passing/`ready` older sha gets `status/<sha>.publish.json`
`{"status":"skipped-superseded","superseded_by":"<sha>"}` (exit 4). `live`,
`no-publish` and `smoke-failed` are left alone. The check runs at the start and
right before each upload; `SUPERSEDE_ONLY=1` runs just the check (`watch.sh`
uses it for `ready` shas). `tools/pipeline/test-publish-dryrun.sh` tests this
offline with temp status dirs and real shas from main, with no network.
