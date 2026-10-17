# Roblox: build, test and publish (Rojo + Lune + Open Cloud)

> **Restored 2026-10-15 from workspace notes after /guides loss; verify.** The body was restored by Phoenix's session at 10:19 from `steal-a-slime-b0`, the 2026-10-14 original wording found in transcripts, and the worklist. It was cross-checked against `tools/livetest/gate.sh`, `rokit.toml`, `publish-response.json` (v10) and `team/roblox-feasibility.md` §4. *[restore note, 2026-10-15]:* the latest published version is **v11** (Luau Execution resolved it), but `publish-response.json` still says 10, and who published v11 is unknown. v11 still crashes at boot. The fixes 15e3fef (SlimeMesh) and 4eb4dbc (PlotSigns) were unpublished at restore time; see `roblox-live-testing.md` §4. Open Cloud place publishing doesn't update `EditableImage`, `EditableMesh`, `PartOperation` (unions), `SurfaceAppearance` or `BaseWrap`; places that use those must be published from Studio (`team/roblox-feasibility.md`).

Written 2026-10-14 after shipping Steal a Slime v7 (`/workspace/roblox/steal-a-slime-b0`) from the Linux bot box; updated through v10 (2026-10-15). Template repo: `/workspace/roblox/speed-escape-skeleton`. Tool install details: `roblox-toolchain-linux.md`.

## 1. Toolchain

Pin tools per repo in `rokit.toml`:

```toml
[tools]
rojo = "rojo-rbx/rojo@7.7.1"
selene = "Kampfkarren/selene@0.32.0"
stylua = "JohnnyMorganz/StyLua@2.6.0"
lune = "lune-org/lune@0.11.0"
wally = "UpliftGames/wally@0.3.2"
```

```sh
rokit install          # https://github.com/rojo-rbx/rokit (or use the binaries already in ~/.local/bin)
wally install          # optional; Packages/ is git-ignored and "$path": {"optional": "Packages"} keeps builds working without it
```

| Tool | Use | Command (from repo root) |
|---|---|---|
| rojo | project JSON → place file | `rojo build -o build.rbxlx` (XML, diffable) / `rojo build -o game.rbxl` (binary, for publishing) |
| lune | unit tests, place-file scripting | `lune run tests` (runs `tests/init.luau`) |
| selene | lint (`std = "roblox"`, `roblox.yml` from `selene generate-roblox-std`) | `selene src tests` |
| stylua | format | `stylua --check src tests` / `stylua src tests` |

CI (`.github/workflows/ci.yml`): `CompeyDev/setup-rokit`, then the same four commands. All four must pass before publishing, plus `lune run scripts/check-place <place>` (section 4).

## 2. Contract-first multi-bot layout

Several bots work in one repo; a `CONTRACT.md` is the single source of truth and each folder has one owner.

```
CONTRACT.md            folder ownership, remotes, payloads, attributes, config table (shared)
src/shared/   -> ReplicatedStorage.Shared       pure modules, Lune-safe (shared / gameplay bot)
src/server/   -> ServerScriptService.Server     thin Roblox adapter + pure, tested systems (gameplay bot)
src/visuals/  -> ReplicatedStorage.Visuals + StarterPlayerScripts.VisualsClient (visuals bot)
src/ui/       -> StarterPlayerScripts.UI         (UI bot)
tests/        Lune specs, not in the Rojo tree; tests/Contract.spec.luau guards the contract
```

Rules that worked:
- **Pure core, thin adapter.** Gameplay lives in pure modules (World state + outbox, Carry, Steal, Income, ...). The Roblox script only wires remotes, Heartbeat and Instances. Lune has no engine, so anything touching `game`/`Instance.new` can only be checked by the build and a real play-test.
- **Dual require:** `if script then require(script.Parent.X) else require("./X")`, so the same module runs in Roblox and Lune. No Roblox API calls at load time.
- **Communicate through the contract, not code.** Remotes table, `State` payload, and Instance attributes (e.g. `OwnerUserId`, `Carrying`, `HideFromUserId`) are documented; names live in `Constants.luau`; `Contract.spec` asserts them. Change code and contract in the same change.
- **Don't edit other owners' folders.** If you need behaviour there (e.g. a client-side prompt hide), publish an attribute + rule in the contract and let the owner implement it.
- Each LocalScript is its own top-level folder under StarterPlayerScripts, otherwise Rojo nests them.

## 3. Publishing with Open Cloud

Needs an Open Cloud API key with **universe-places: write** for the universe, exported as `ROBLOX_OPEN_CLOUD_API_KEY`. Never echo/cat/log it, never `set -x`, never write it to a file.

Keep the key out of argv too: pass the header to curl on stdin.

```sh
rojo build -o game.rbxl     # binary place
lune run scripts/check-place game.rbxl
printf 'x-api-key: %s\n' "$ROBLOX_OPEN_CLOUD_API_KEY" | curl -sS -H @- -X POST \
  -H 'Content-Type: application/octet-stream' --data-binary @game.rbxl \
  -o publish-response.json -w 'HTTP %{http_code}\n' \
  "https://apis.roblox.com/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions?versionType=Published"
cat publish-response.json   # expect HTTP 200 and {"versionNumber":N}
```

### Saved vs Published
- `versionType=Saved` uploads a new version without making it live; `Published` goes live for new servers (old servers keep the old version until they close). Both get a new `versionNumber`.
- Open Cloud can't promote a Saved version to Published, so publishing means uploading the same file again with `Published`.
- Gate pattern (`tools/livetest/gate.sh` in steal-a-slime-b0, untracked as of 2026-10-15): build → local checks (lune tests, selene, stylua, check-place) → upload **Saved** → Luau Execution live check of that saved version → upload the same bytes as **Published** only if the check passed. `PUBLISH=0` stops after the gate. Luau Execution needs the key to also have `universe.place.luau-execution-session` **write**; details in `roblox-live-testing.md`.
- Retry `409 "Server is busy"`, `429` and `5xx` with backoff (seen 2026-10-15); fail on other codes.
- The response contains only `versionNumber`; record it in PLAYTEST.md (version, date, `versionType`, commit) so testers know which build they're on.
- Only publish when told to. Example: Steal a Slime, universe 10770917350, place 135787188192378 → v10 (commit `f7f7f38`).

## 4. Static world (no void spawns)

The built place had an empty Workspace (no floor, no SpawnLocation): the world was only built at runtime by `WorldView.setup`, which since v8 first yielded on `InsertService:LoadAsset`. Characters auto-load on join, so players spawned with nothing under them, fell past `FallenPartsDestroyHeight` and respawned into the void again (fixed in v9, commit `0040c0f`).

- The map is in the place file: `lune run scripts/gen-world` runs the unchanged `WorldBuilder.build` and writes `world/Map.rbxmx`, `world/Plots.rbxmx`, `world/HubSpawn.rbxmx` (anchored SpawnLocation on the Ground). `default.project.json` maps them under Workspace and sets `FallenPartsDestroyHeight = -1000`. Rerun gen-world after changing layouts and commit the result.
- At runtime, build/adopt the world **before** anything that yields; `WorldBuilder` reuses same-named static parts (idempotent) and forces `Anchored`.
- Kill plane: a pure `Rescue` + Heartbeat check moves living characters below Y -60 back to their plot Base / HubSpawn with zero velocity.
- `lune run scripts/check-place <place>` (also `tests/StaticWorld.spec`, `PlaceSafety.spec`): anchored non-slime parts, a SpawnLocation on solid ground, Ground under every Base/HomeZone, world files fresh.
- `world/` is the only map source. Archer's `src/visuals/tools/build-map.luau` writes `src/visuals/static/*.rbxm`, which is git-ignored and not mapped; mapping both would duplicate Map/Plots.

## 5. Pitfalls learned

- **Memory-mode leaking into production.** A workspace attribute like `DataStoreMode = "Memory"` is handy for tests, but must not be in the published place. Check the built file before publishing:
  ```luau
  -- lune run check.luau game.rbxl
  local roblox = require("@lune/roblox")
  local game = roblox.deserializePlace(require("@lune/fs").readFile((...)))
  for _, i in { game:GetService("Workspace"), table.unpack(game:GetDescendants()) } do
  	assert(i:GetAttribute("DataStoreMode") == nil, i:GetFullName())
  end
  ```
  Also: a server that falls back to memory when `GetDataStore` fails will silently not save. Log it loudly.
- **No per-player visibility from the server.** `ProximityPrompt.Enabled` (and every other property) replicates to all clients. To hide a prompt from one player (e.g. the owner's own Steal prompt) the server tags it with an attribute and a LocalScript sets `Enabled = false` locally, re-applying when the server changes `Enabled`. Keep the server check too (refuse the owner).
- **Pivot:** with a PrimaryPart set, `PivotTo` uses `PrimaryPart.PivotOffset`, not `Model.WorldPivot`.
- **`.rbxlx` vs `.rbxl`:** both build fine; publish the binary `.rbxl`. Both are git-ignored.
- **Lune test discovery:** run from the repo root; `tests/init.luau` walks `tests/` (incl. subfolders) for `*.spec.luau`.
- **Lune only runs the `else` branch of dual requires** (`script` is nil). A wrong `script.Parent...` path (SlimeMesh used `Parent.Parent.Shared`, but Shared is in ReplicatedStorage) killed the whole server Script at boot in v9 and v10: no remotes, no slimes, no data. Server modules get Shared via `game:GetService("ReplicatedStorage").Shared`; `tests/RequirePaths.spec.luau` rojo-builds the place and walks every `require(script...)` chain, and `tests/LiveBoot.spec.luau` boots the real server Script (commit `15e3fef`).
- **Adapter code has no unit tests**; `tests/Members.spec.luau` statically checks `Module.member` references.
- **Studio-only tools** (`run-in-roblox`, Rojo plugin) don't work on Linux. Bots can boot the server headless (`tools/livetest`) and via Open Cloud Luau Execution (`roblox-live-testing.md`), but physics, rendering and client feel still need a human play-test. Write a PLAYTEST.md checklist per release.
- **Shared checkout:** other bot sessions may edit, commit or publish in the same repo while you work. Check `git status`/`git log` first, commit only your files, and build/publish from a clean `git worktree` of HEAD when others have WIP.
- **DataStore session locks:** quick rejoins between servers can hit the old server's lock; retry with backoff and treat locks older than a few minutes as stale.
