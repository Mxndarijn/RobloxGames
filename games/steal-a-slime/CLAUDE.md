# Steal a Slime: notes for bots

## HARD RULE: never touch production DataStores

- Tests, live checks and scripted sessions run on the **in-memory store only**: workspace attribute `DataStoreMode = "Memory"` (CONTRACT.md §2 DataStore).
- Open Cloud Luau Execution runs on the real place, where **DataStores are real**. Every cloud script that boots the Server entry must set `DataStoreMode = "Memory"` first (`tools/livetest/cloud/live.luau`, `cloud/session.luau` and `live-testing/ci/playtest.luau` do). `cloud/smoke.luau` only requires modules and never calls DataService. Never call `DataStoreService`, `GetDataStore`, `GetOrderedDataStore`, `UpdateAsync`, `SetAsync` or `RemoveAsync` from a test, a cloud script or a one-off probe. Don't read or "clean up" player keys either.
- Cash and time cheats go through `src/server/TestHooks.luau` only. Its guard (contract/v13-additions.md §8.12): `TestHooks.enable` refuses unless `DataStoreMode == "Memory"`. No remote, prompt or chat command reaches it, and `tests/TestHooks.spec` fails if any other `src/` file references it. Never weaken that guard.
- Never ship a place that sets `DataStoreMode`. `scripts/check-place` and `tests/PlaceSafety.spec` fail on it; don't bypass them.

## Release rules

- Follow `/guides/roblox-release-process.md`. **Never upload `versionType=Published`**: only `Saved`, until Merijn gives the OK and says who publishes.
- Never print or commit `ROBLOX_OPEN_CLOUD_API_KEY` (env or `~/.config/roblox-ci.env`).
- Upload 409 "Server is busy": stop after 4 tries with backoff (1, 2, 4, 8 min).
- Gate builds are copied to `/workspace/roblox/gate-out/steal-a-slime-<sha>.rbxl`. Test that exact file.
- Live check: `python3 /workspace/roblox/live-testing/ci/run.py --version N`. Never use `--shim`.

## Ownership (CONTRACT.md §1)

| Area | Owner | Notes |
|---|---|---|
| `src/server`, `src/shared`, `world/`, `scripts/`, `tools/livetest` | Phoenix | Changes to shared names go through `CONTRACT.md` first: commit the contract before the code. |
| `src/ui`, `tests/ui` | Jolt | Don't edit them from another role. Report findings to Jolt instead. |
| `src/visuals` | Archer | Don't edit it. `src/visuals/static/*.rbxm` is build-map output: **never `git add` it**. It is not in the Rojo tree, and `world/` is the only map source. |

- Several bots commit to this checkout at the same time. Run `git status` / `git log` before you commit. Stage only your own files by path; never `git add -A`. Run `stylua` only on your own files.
- Shared modules use `if script then require(script.Parent.X) else require("./X")`, so they run both in Roblox and under Lune. Keep that pattern. Keep pure modules free of Roblox APIs at load time.
- The client never decides outcomes: it calls `Request` and renders `State`.

## Checks (run from the repo root; toolchain in `rokit.toml`, `rokit install`)

```sh
lune run src/visuals/tools/build-map.luau     # Archer's map build (writes untracked src/visuals/static)
lune run src/visuals/tools/check-map.luau
rojo build -o build.rbxlx                     # or -o steal-a-slime.rbxl for an upload
lune run tests                                # unit + LiveBoot + RequirePaths + Members specs
selene src tests
stylua --check src tests
lune run scripts/check-place.luau build.rbxlx # place safety (no DataStoreMode, void-safety)
scripts/typecheck.sh                          # luau-lsp: fails on src/server + src/shared, reports src/ui + src/visuals
lune run tools/livetest/session build.rbxlx   # stand-in player session on the memory store
```

Cloud stand-in session on a Saved version: `python3 /workspace/roblox/live-testing/ci/run.py tools/livetest/cloud/session.luau --version N`. Results go to `tools/livetest/results/`.

`scripts/typecheck.sh` rewrites the dual require pattern to its Roblox branch in a temp copy (luau-lsp can't type if-expression requires), checks it against the Rojo sourcemap and maps the paths back. `--all` makes src/ui and src/visuals errors fatal too.
