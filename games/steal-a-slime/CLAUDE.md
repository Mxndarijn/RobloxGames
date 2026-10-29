# Steal a Slime: notes for bots

## HARD RULE: never touch production DataStores

- Tests, live checks and scripted sessions run on the **in-memory store only**: workspace attribute `DataStoreMode = "Memory"` (CONTRACT.md §2 DataStore).
- Open Cloud Luau Execution runs on the real place, where **DataStores are real**. Every cloud script that boots the Server entry must set `DataStoreMode = "Memory"` first (`tools/livetest/cloud/live.luau`, `cloud/session.luau` and `live-testing/ci/playtest.luau` do). `cloud/smoke.luau` only requires modules and never calls DataService. Never call `DataStoreService`, `GetDataStore`, `GetOrderedDataStore`, `UpdateAsync`, `SetAsync` or `RemoveAsync` from a test, a cloud script or a one-off probe. Don't read or "clean up" player keys either.
- Every cheat (cash, time, saves, slimes, items) goes through `src/server/TestHooks.luau` only. Its guard (contract/v13-additions.md §8.12): `TestHooks.enable` refuses unless `DataStoreMode == "Memory"`. Its one caller in `src/` is `server/AdminService` (the admin menu, contract/admin-menu.md); no other remote, prompt or chat command reaches it, and `tests/TestHooks.spec` fails if any other `src/` file references it. Never weaken that guard.
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
| `src/visuals` | Archer | Don't edit it. `src/visuals/static/Map.rbxm` / `Plots.rbxm` are Archer's build-map output: they are tracked, but they are not in the Rojo tree and nothing loads them. `world/` is the only map source. Don't regenerate or `git add` them from another role. |

- Several bots commit to this checkout at the same time. Run `git status` / `git log` before you commit. Stage only your own files by path; never `git add -A`. Run `stylua` only on your own files.
- Shared modules use `if script then require(script.Parent.X) else require("./X")`, so they run both in Roblox and under Lune. Keep that pattern. Keep pure modules free of Roblox APIs at load time.
- The client never decides outcomes: it calls `Request` and renders `State`.

## Checks (run from `games/steal-a-slime`; toolchain in `rokit.toml`, `rokit install`)

```sh
rojo build -o build.rbxlx                     # or -o steal-a-slime.rbxl for an upload
lune run tests                                # unit + LiveBoot + RequirePaths + Members specs
selene src tests
stylua --check src tests
lune run scripts/check-place.luau build.rbxlx # place safety (no DataStoreMode, void-safety)
scripts/typecheck.sh                          # luau-lsp: fails on src/server + src/shared, reports src/ui + src/visuals
lune run tools/livetest/session build.rbxlx   # stand-in player session on the memory store
```

CI: `.github/workflows/pr-checks.yml` runs the list above up to `scripts/typecheck.sh` on every PR that touches this game, plus `lune run scripts/test-flags` with every flag on and every flag off; `cheap-gates.yml` runs the Lune tests and the static UI layout check on every push to `main`. Archer's `lune run src/visuals/tools/build-map.luau` / `check-map.luau` only rebuild and check the unused `src/visuals/static` files; they are not part of the gate.

Cloud stand-in session on a Saved version: `python3 /workspace/roblox/live-testing/ci/run.py tools/livetest/cloud/session.luau --version N`. Results go to `tools/livetest/results/`.

`scripts/typecheck.sh` rewrites the dual require pattern to its Roblox branch in a temp copy (luau-lsp can't type if-expression requires), checks it against the Rojo sourcemap and maps the paths back. `--all` makes src/ui and src/visuals errors fatal too.

## Agent coding rules

How to structure code (layers, module and panel templates, recipes, testing policy) is in [ARCHITECTURE.md](ARCHITECTURE.md). Read it before adding a module, an action, a State field, a save version or a flag. The rules that are easiest to get wrong:

- **No history in code.** No version tags (`v28:`), dates, bug or ticket numbers, or "was X, now Y" notes in code, comments or test names. Git and the PR hold history.
- **One source of truth per value.** World dimensions live in `src/visuals/shared/WorldLayout.luau` (or `Config` for gameplay sizes), tunables in `Config`, shared names in `Constants`. Read them from there; never copy a number into a second file. Docs don't restate defaults either: `Config.FEATURES` is the only place a flag's value is written.
- **Flags expire.** One release after a `Config.FEATURES` flag goes ON, delete the flag, its OFF branch, its test overrides and its `tests/ForcedFlags.luau` entries. A flag that is staying OFF gets its code deleted.
- **One DI pattern: `ctx`.** Pass engine access and test overrides in a `ctx` / `Context` argument (see `Actions.Context`). No new module-level `setEnv` / `setSink`-style singletons.
- **Entry scripts only wire.** `init.server.luau` and `init.client.luau` create remotes, build modules and connect signals. Logic, and Studio-only review fakes, go in their own modules with tests.
- **One client frame loop.** Per-frame client work hooks into the existing loop in `init.client.luau`, culls by distance and skips off-screen work. A client module's `start()` returns a cleanup function that disconnects everything it made.
- **UI values from tables.** Colours from `Widgets.Theme`, draw order from `Layout.ZINDEX`, sizes and `TextSize` from `Layout` or a frozen table at the top of the panel. No raw `ZIndex` numbers. Which colour, button, size and wording to use where: [UI-STYLEGUIDE.md](UI-STYLEGUIDE.md).
- **Delete dead code.** When a module's last caller goes, delete the module and its spec in the same PR.
- **Generated files** are either gitignored or covered by a spec that fails when they are stale (like `tests/StaticWorld.spec.luau` for `world/*.rbxmx`).
- **Test behaviour, not source text.** Use `Fixtures` / `ServerFixtures` / `UiHarness`. Source-text asserts are only for safety guards (TestHooks, DataStoreMode) and go through one shared helper.
