# Roblox cloud server test (Open Cloud Luau Execution) (2026-10-15)

Run our server code in a real Roblox server without Studio. Background and raw results: [roblox-live-testing.md](roblox-live-testing.md) §2, §4.

## Rules

- **Target a dedicated test place, Saved versions only, never live.** Upload the build with `versionType=Saved` and pass `--version N`. Never test by publishing. The test place doesn't exist yet (waiting on Merijn); until it does, use Saved versions on place 135787188192378 (universe 10770917350) and set `PLACE_ID`/`UNIVERSE_ID` env once it exists.
- **DataStores are real in a task.** Every script that boots the server sets `workspace.DataStoreMode = "Memory"` first (`live.luau`, `session.luau`, `playtest.luau` do). Never call DataStore APIs from a test.
- **Key scope:** `universe.place.luau-execution-session:write` on the universe (get task/logs accept read or write). Key from env or `~/.config/roblox-ci.env`; never print it.
- **Never `--shim`** as a gate (diagnosis only).

## Place scripts and physics don't auto-run

A task gets a server with the place loaded, but the place's own Scripts don't start and physics doesn't step (`Stepped` never fires, unanchored parts don't fall). No players exist. So the task script boots the game itself:

- `require` the server ModuleScripts (or copy `Server.Source` into a ModuleScript and require it, as `ci/playtest.luau` does), with `DataStoreMode = "Memory"`.
- Drive the loop (`GameLoop.step`, Heartbeat) and use fake players (`{UserId, DisplayName, Character = rig}` + `Sessions.join`).
- Keep `init.server.luau` thin with startup in a boot module, so live servers and tasks call the same entry point.

## Commands

```sh
. ~/.config/roblox-ci.env      # sets ROBLOX_OPEN_CLOUD_API_KEY; don't echo it
cd /workspace/roblox/steal-a-slime-b0      # or your worktree's games/steal-a-slime
python3 /workspace/roblox/live-testing/ci/run.py --version N --out /tmp/run-vN-$(date +%s%N).json
python3 /workspace/roblox/live-testing/ci/run.py tools/livetest/cloud/session.luau --version N \
  --out /tmp/session-vN-$(date +%s%N).json
/workspace/roblox/live-testing/ci/release-check.sh N      # run.py wrapper, results in ci/releases/N-<ts>/
```

Exit codes: 0 all assertions pass, 1 an assertion failed, 2 task/HTTP/tooling error. Local dry run without network: `lune run tools/livetest/cloud-local <place> tools/livetest/cloud/session.luau --seconds 200`.

## Running in parallel

Tasks can run in parallel (limits: 10 open tasks per place, 5 creates/min per key owner, 5 min per task). Give every run its own result file.

**Lesson (v20, 2026-10-15):** run.py and the cloud session were started at the same time and finished in the same second. run.py names its default result `ci/result-<UTC second>.json`, so one result overwrote the other. Fix: always pass a unique `--out` per run (as above), or run them one after the other. `release-check.sh` relies on the default name, so don't run two of those at once.
