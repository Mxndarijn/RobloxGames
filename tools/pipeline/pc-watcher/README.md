# PC watcher (Steal a Slime Studio check)

Runs on Merijn's Windows PC (`C:\gate\pc-watcher`). For every new `origin/main` sha it builds the
game, opens it in Roblox Studio, plays it, checks perf, input, menus and HUD layout at three
viewport sizes, tries a 2-player test, and pushes a JSON report plus frames to the orphan branch
`studio-reports`. The box copies those reports to `/workspace/roblox/pipeline/studio-reports/`,
where `games/steal-a-slime/tools/pipeline/cloud-test.sh` reads them (`gate_ready` needs `pass`).

Studio is driven **only** through Roblox's `StudioMCP.exe` (stdio JSON-RPC, `mcp_client.py`). Win32
(ctypes, `win32.py`) is used only for window size, foreground and client-area capture. Nothing is
saved, published or uploaded, and the test build runs on the in-memory DataStore.

## Trigger

A Scheduled Task, `StealASlime-PCWatcher`, starts at logon. It runs as the current user on the
interactive desktop, because Studio needs one. It runs `pythonw watcher.py --home C:\gate\pc-watcher loop`.
The loop calls `git ls-remote origin refs/heads/main` every 60 s. When the sha differs from
`state\last-sha.json`, it does one full run. `state\last-sha.json` is then updated whatever the result,
except for "studio busy" (see step 2), which is retried after 5 min.

## Commands

```
python watcher.py once [--sha SHA] [--no-sync]  # full run for one sha (default origin/main); ignores last-sha
python watcher.py loop                          # what the Scheduled Task runs
python watcher.py step build [--sha SHA]        # debug one step at a time, in this order:
python watcher.py step launch                   #   opens Studio and leaves it open (state\current.json)
python watcher.py step perf                     #   starts play if needed
python watcher.py step play                     #   play + perf + onboarding + shop + esc
python watcher.py step devices                  #   starts play if needed
python watcher.py step shots
python watcher.py step twoplayer
python watcher.py step close
python watcher.py step sync [--sha SHA]
python watcher.py tools                         # dump StudioMCP tool input schemas
python watcher.py mcp get_studio_state '{"studio_id": "$studio"}'   # one raw tool call
python watcher.py capture [--out f.png]         # capture test of the watcher's Studio window
python watcher.py selftest                      # pure checks, any OS (also: python selftest.py)
```

Global flags: `--home DIR` (or `%PCW_HOME%`), `--dry-run` (log the git/rojo commands, skip Studio,
write the report to `out\dry-run\`, no sync), `-v`. All step commands print the step JSON.
`state\mcp-tools.json` holds the tool schemas from the last MCP session. Read it first when an
input call misbehaves.

## Layout on the PC

| Path | What |
|---|---|
| `app\` | the copy of this folder that the task runs (`install.ps1` copies it; the repo clone moves to every test sha) |
| `repo\` | repo clone, detached at the sha under test |
| `bin\rojo.exe` | rojo 7.7.1 (falls back to `rojo` on PATH) |
| `builds\<sha>.rbxl` | the last 5 test builds |
| `out\<sha>\` | `<sha>.json`, `<sha>-<device>.png`, `<sha>-console.txt`, `*-rejected.png` |
| `reports\` | git clone on branch `studio-reports` (sync only) |
| `state\` | `last-sha.json`, `pids.json` (Studio pids the watcher started), `current.json`, `run.lock`, `loop.lock`, `unsynced.json`, `mcp-tools.json` |
| `logs\watcher.log` | rotating log, 5 x 5 MB |
| `config.json` | optional overrides of `watcher.DEFAULTS` (budget, devices, input templates, 2-player args, ...) |

## Flow per sha (budget about 8 min, `run_budget_s` 480)

| # | Step | What | Hard fail on | Typical |
|---|---|---|---|---|
| 1 | build | `git fetch`, `checkout --detach --force <sha>`, `clean -ffdx`, then `rojo build` of `default.project.json` plus Workspace `$attributes {DataStoreMode: "Memory"}` (temp `.pcwatcher.project.json`) to `builds\<sha>.rbxl`. `world/*.rbxmx` are tracked. `scripts/gen-world` and `src/visuals/static` are not in the Rojo tree, so nothing else is needed. | git/rojo error | 5-30 s |
| 2 | launch | Kill Studio pids from an earlier watcher run. If any other Studio window has a place open (title `<place> - Roblox Studio`), the run fails with **"studio busy"** and that Studio is never touched. Otherwise start `RobloxStudioBeta.exe <rbxl>` from the newest `Versions\<ver>` that has `StudioMCP.exe`. Track it and its child pids. Wait until `list_roblox_studios` lists `<sha>.rbxl` and `get_studio_state` answers (120 s). Edit check: DataStoreMode is Memory (set it in-session if not; never saved). Also save the MCP `screen_capture` edit frame. | not listed in 120 s | 15-40 s |
| 3 | play | `start_stop_play true`, wait for the Client (LocalPlayer, character, `SlimeUI`, `TutorialStepId`; 90 s). Then Heartbeat dt over 5 s (avg / p95 / max / fps), `Stats:GetTotalMemoryUsageMb()`, `InstanceCount`, part counts. | client not up | 20-40 s |
| 4 | perf | Server datamodel: MeshParts in Workspace (wild slimes and characters excluded) and unique MeshIds, polled until three equal counts (max 45 s). Budget is 400. The tracked world has **0** MeshParts: `src/server/MeshSwap` creates them at run time, so the Edit count is info only. | > 400, or 0 | 10-15 s |
| 5 | onboarding | The tutorial card (`SlimeUI.TutorialOverlay`) must show for the fresh memory profile. Click its `Hide`; the card must hide. Later (soft): teleport next to the cheapest wild slime, press **E** through `user_keyboard_input`, and record whether `TutorialStepId` moved past `Grab`. | card missing / Hide no effect | 5 s |
| 6 | shop | Try `VirtualInputManager:SendMouseButtonEvent` from the Client execute_luau first. It is expected to be blocked ("lacking capability RobloxScript"); the result is recorded. Then `user_mouse_input` (down, 120 ms, up) at the centre of `Hud.Shop` (then `Nav.Shop`): AbsolutePosition + AbsoluteSize/2 + GuiInset. `ShopPanel` must become visible. Results go in `input_methods`. | shop not opened | 5 s |
| 7 | esc | `user_keyboard_input` Escape; `ShopPanel` must close (game binds Esc via ContextActionService). | still open | 2 s |
| 8 | devices | Resize the Studio main window (SetWindowPos, DPI-aware) until Client `CurrentCamera.ViewportSize` is 1920x1080, 390x844 and 844x390. The first guess is target + (client - viewport). Then secant steps, up to 5 tries. When Studio or Windows clamps the size, the closest size reached is kept and noted. At each size: HUD + nav buttons (`Hud.*`, `Nav.*` by name) must be inside the ScreenGui rect (viewport minus top bar, 1 px), then one frame is captured. The window is restored afterwards. | an element off-screen or missing | 60-90 s |
| 9 | shots (soft) | `shots.json` proof frames: `ui` (click `Nav.<key>`, capture, Esc) and `world` (Server finds target, Client scriptable camera). Missing targets are notes. | never | 0-60 s |
| 10 | two_player | See below. | mode b/c assertion false | 40-150 s |
| 11 | close | Save the console output, stop play, WM_CLOSE the main window, wait 15 s, then `taskkill /T /F` the tracked pids. This also kills a "save changes?" prompt. | - | 5-20 s |
| 12 | report + sync | Write `out\<sha>\<sha>.json`, then commit to `studio-reports` and push. | - | 5 s |

A step that is skipped because an earlier step failed, or because the run budget ran out, also
fails the run. Exceptions: `shots`, and `two_player` reporting "not run".

### Frames

`<sha>-<device>.png` holds the client area of the Studio window (`PrintWindow` with
`PW_RENDERFULLCONTENT`, else `BitBlt`, else a screen copy). The frame includes Studio's panels; the
game viewport is the part described by `devices.<name>.viewport`. A frame is **rejected** (kept as
`*-rejected.png`, listed in `notes`, not in `frames`) when it is blank (luma variance < 40 or < 12
colours on a 64x64 sample grid), when the window title is not Studio's, or when it is a screen copy
taken while Studio was not the foreground window.

### Two players

Studio's "Start Server + N players" is not an MCP tool. Tried in this order:

- **a**: probes `StudioTestService` / `TestService` from Edit for a multi-client API. It only reads; none is known, so it always falls through.
- **b**: starts `RobloxStudioBeta.exe -task StartServer -placeId 0 -universeId 0 -port 53640 -creatorId 0 -creatorType 0 <rbxl>`, waits 20 s, then starts `-task StartClient -port 53640` twice. It then polls `list_roblox_studios` for new studios. Assertion: the server sees 2 or more players with 2 or more owned plots, and a client sees both plots owned. Only the process trees the watcher started are killed afterwards. The flags are guesses; they can be changed in `config.json` (`twoplayer_server_args`, `twoplayer_client_args`). A common variant is `-localPlaceFile <rbxl>`.
- **c**: starts one play session and runs `luau/server_steal_sim.luau` in the Server datamodel. On a fresh pure `World` built with the real server modules (`World`, `Sessions`, `Carry`), two stand-in sessions join and get distinct plots. The victim's slime is grabbed and deposited by the thief, and must move. This needs no real second client and no DataStore, and does not touch the live world. It tests the steal flow, not replication.

`steps.two_player.detail.mode` says which mode ran (`b-cmdline`, `c-server-sim`, `not run`) and why
the earlier modes did not (`tried`).

## Report

`out\<sha>\<sha>.json`, and the same in `studio-reports/<sha>.json`:

```json
{
  "sha": "<40 hex>", "status": "pass | fail", "checked_at": "2026-10-16T09:44:58Z",
  "studio_version": "0.695.0.6950727 (version-4f087c32742644ab)",
  "notes": "limitations and rejections, '; '-joined",
  "duration_s": 312.4,
  "steps": {
    "build": {"status": "pass|fail|warn|skip", "seconds": 8.1, "detail": {...}},
    "launch": ..., "perf": ..., "play": ..., "onboarding": ..., "shop": ..., "esc": ...,
    "devices": {"detail": {"devices": {"desktop": {"target": [1920,1080], "viewport": [1900,1002], "exact": false,
                                                   "hud": {"offscreen": [], "missing": []}, "frame": {...}}}}},
    "two_player": {"detail": {"mode": "c-server-sim", "tried": [...], "assertion": "..."}},
    "shots": ...
  },
  "perf": {"mesh_slots": 324, "unique_meshes": 61, "budget": 400, "frame_time_ms": 16.7, "memory_mb": 1450.2,
           "parts": 1100, "play": {...}},
  "frames": ["<sha>-edit.png", "<sha>-desktop.png", "<sha>-phone-portrait.png", "<sha>-phone-landscape.png"],
  "input_methods": {"virtual_input_manager": "blocked: ...", "mcp_mouse:Hud.Shop": "works", "mcp_keyboard:Escape": "works"},
  "close": {...}, "watcher_version": "1.0.0"
}
```

`cloud-test.sh` reads only `sha`, `status`, `checked_at`, `studio_version` and `notes`.

## Sync route

PC to GitHub to box:

1. `reports\` is a git repo whose `origin` is the repo clone's origin. Each try runs `fetch origin studio-reports`, `checkout -f -B studio-reports FETCH_HEAD` (or a new orphan branch the first time), copies `out\<sha>` to `studio-reports/<sha>.json` plus `studio-reports/<sha>/`, commits as `pc-watcher`, and runs `push origin HEAD:refs/heads/studio-reports`. Frames are converted to JPEG q80 when Pillow is installed, else copied as PNG, and `frames` is rewritten to match. A failed push is retried 3 times (each try re-fetches and restages, so a moved remote head is never a conflict). After that the sha goes to `state\unsynced.json` and is retried at the start of each loop iteration. Auth is the PC's Git Credential Manager, with `GIT_TERMINAL_PROMPT=0` and `GCM_INTERACTIVE=never`, so a missing login fails fast instead of popping up a prompt.
2. Box: `tools/pipeline/pc-watcher/box-pull.sh [--loop 60]` fetches `studio-reports` into `/workspace/roblox/pipeline/.studio-reports-git` and copies `studio-reports/.` to `/workspace/roblox/pipeline/studio-reports/`. `PCW_URL`, `PCW_DEST` and `PCW_CLONE` override the defaults.
3. CI: pushes to `studio-reports` would start `cheap-gates.yml` (`on: push` with no filter). That fails on an orphan branch, which has no `games/`. The fix is `branches-ignore: [studio-reports]` under `push:`. It was reverted in 1a3c88f because the bot token lacks the `workflow` scope, so it still has to be applied with a token or account that has that scope.

## Install

```powershell
# from a checkout of this folder (for example C:\gate\pc-watcher\repo\tools\pipeline\pc-watcher)
powershell -ExecutionPolicy Bypass -File install.ps1      # copies app\, clones repo\ if missing, selftest, registers + starts the task
powershell -ExecutionPolicy Bypass -File uninstall.ps1    # stops + removes the task
```

You need Python 3.13 (`python` and `pythonw`, WindowsApps aliases are fine) and git with GCM logged in to
GitHub. rojo 7.7.1 goes in `bin\`. Studio must have its MCP server enabled (Studio > Assistant > Manage MCP Servers).
Pillow is optional (JPEG frames).

Bring-up, step by step: `python watcher.py tools` (with a Studio open), then `step build`,
`step launch`, `step perf`, `step play`, `step devices`, `step twoplayer`, `step close`, then `once --no-sync`.

## Limits

- **Unverified on the PC.** This was written on the box, where Studio, StudioMCP and Win32 are not available. The pure parts are covered by `selftest.py`; `step build` and `step sync` were run against a local clone and bare remote; every Luau body compiles under lune. The input action shapes are built from the tools' `inputSchema` (`mcp_client.build_action`) because the schemas were not available here. If Studio rejects them, set `input_overrides` in `config.json`, for example `{"mouse_down": {"type": "mouseButtonDown", "x": "$x", "y": "$y"}}`.
- Device sizes come from resizing the Studio window, not the device emulator, which is not scriptable (`StudioDeviceEmulatorService` is nil to execute_luau). So there is no touch input and no on-screen thumbstick (`Layout.TOUCH_CONTROLS_HEIGHT` is not exercised). Studio's minimum window size and the monitor size can stop a target from being reached exactly; the closest size is reported.
- Frame time is Studio play-mode on this PC (client and server in one process). Studio throttles an unfocused window, so treat it as a trend, not a device number. There is no triangle count from Luau; use `tools/pr-gate/budget.sh`.
- Tutorial advance (grab with E) needs a wild slime the starting cash can buy. It is reported, and never fails the run.
- Two-player mode b depends on undocumented Studio flags and on MCP seeing those processes. Mode c is a simulation on the server modules, not two real clients.
- One watcher Studio at a time. A user Studio with a place open blocks the run ("studio busy"); a user Studio on the start page is left alone.
