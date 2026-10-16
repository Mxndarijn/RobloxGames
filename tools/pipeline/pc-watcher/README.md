# PC watcher (Steal a Slime Studio check)

Runs on Merijn's Windows PC (`C:\gate\pc-watcher`). For every new `origin/main` sha it builds the
game, opens it in Roblox Studio, plays it, checks perf, input, menus and HUD layout at three
viewport sizes, tries a 2-player test, and pushes a JSON report plus frames to the orphan branch
`studio-reports`. The box copies those reports to `/workspace/roblox/pipeline/studio-reports/`,
where `games/steal-a-slime/tools/pipeline/cloud-test.sh` reads them (`gate_ready` needs `pass`).

Studio is driven **only** through Roblox's `StudioMCP.exe` (stdio JSON-RPC, `mcp_client.py`). Win32
(ctypes, `win32.py`) is used only to start Studio on its own desktop and to size its window. Nothing is
saved, published or uploaded, and the test build runs on the in-memory DataStore.

## Runs in the background

Hard requirement: the watcher runs while Merijn uses the PC. It never steals focus and never touches
the real mouse or keyboard (no MCP input tool is used, see 5).

1. **Separate desktop.** `win32.create_desktop` makes the Win32 desktop `pcw-studio` (`CreateDesktopW`,
   `GENERIC_ALL`); `win32.launch_on_desktop` starts Studio with `CreateProcessW` and
   `STARTUPINFOW.lpDesktop = "pcw-studio"`. Studio and its windows live there, so they can never take the
   foreground on Merijn's desktop. Verified on the PC: MCP sees Studio after ~10 s, play runs at 60 fps.
2. **Window ops on a desktop thread.** `win32.DesktopWorker` is a dedicated thread that does
   `SetThreadDesktop(OpenDesktopW("pcw-studio"))`; `studio_main_window` finds the largest top-level window
   of our pids with `EnumDesktopWindows` (iconic ones judged by `rcNormalPosition`). There is no
   off-screen parking and no taskbar-button hiding any more.
3. **Device sizes.** `win32.set_client_size` (run on the worker) uses
   `SetWindowPos(SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER)`; the viewport follows (verified).
   The watcher never maximizes, restores or shows windows.
4. **No foreground calls, one capture method.** `bring_to_front`, `SetForegroundWindow`,
   `BringWindowToTop`, `ShowWindow`, `keybd_event`, BitBlt and `PrintWindow` (blank viewport on the hidden
   desktop) are gone; `selftest.py` fails if they come back into `win32.py`, `watcher.py` or `mcp_client.py`.
   Frames come from StudioMCP `screen_capture` (see Frames).
5. **No input at all.** StudioMCP `user_mouse_input` warped the real OS cursor (run 9673a60: cursor_events
   (1410,1139) -> (1280,707)) and `user_keyboard_input` opened Roblox's own Esc menu, and neither can be proven
   not to be OS-level, so neither tool is ever called (`mcp_client` has no click/key helpers; `selftest.py` bans
   the names). Everything is in-engine through `execute_luau`: panels open/close with the Studio-only SlimeUI
   attribute `PcwOpen` (`src/ui/init.client`, `luau/panel_visible`; fallback `Visible`); the Esc test sets the Studio-only SlimeUI attribute `PcwPress='Escape'` (`src/ui/init.client`, `luau/cas_close`, method
   `pcw_press_hook`): the hook runs the game's `CloseMenu` action handler, or answers `PcwPressResult='not_bound'` when
   `Layout.CLOSE_WITH_ESCAPE` is off. It tests the close logic, not real key routing (`CAS:CallFunction` lacks
   capability RobloxScript in `execute_luau`). Onboarding hides the card the same way and reports
   `hide_method`; the shop reports `open_method` in `input_methods`. A panel opened by the `Visible` fallback gives
   `warn` (the game's menu state is not open). Report `background.mcp_input` is always `false`.
6. **Focus guard.** At run start the watcher records `GetForegroundWindow` (report
   `background.foreground_at_start`). After every step it checks whether the foreground window belongs to
   a Studio pid the watcher started. If so, the report notes `FOCUS STOLEN at step X`, lists it in
   `background.focus_stolen`, and the run status is `fail`. It never calls anything to change the focus
   back (that would be one more focus change).
7. **Two players: mode c only.** Mode b (extra `-task StartServer` / `-task StartClient` Studio
   processes) is removed: it opened visible windows. Only mode c (the server simulation in the watcher's
   own play session) runs; `tried` says why b is gone.
8. **Close, never save.** No WM_CLOSE (it would raise the "Save changes?" dialog). After stop play the watcher
   terminates its own Studio process trees (`taskkill /T /F` = TerminateProcess: no dialog, no activation), the
   build .rbxl is a throwaway. It then verifies nothing is left: none of its pids, and no RobloxStudioBeta whose
   command line points into the watcher home; leftovers are killed and, if any survive, the close step fails.

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
python watcher.py step devices                  #   starts play if needed  # also runs menus + phone_perf
python watcher.py step shots
python watcher.py step twoplayer
python watcher.py step close
python watcher.py step sync [--sha SHA]
python watcher.py tools                         # dump StudioMCP tool input schemas
python watcher.py mcp get_studio_state '{"studio_id": "$studio"}'   # one raw tool call
python watcher.py capture [--out f.jpg]         # MCP screen_capture of the watcher's Studio viewport
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
| `out\<sha>\` | `<sha>.json`, `<sha>-<device>.jpg`, `<sha>-console.txt`, `*-rejected.png` |
| `reports\` | git clone on branch `studio-reports` (sync only) |
| `state\` | `last-sha.json`, `pids.json` (Studio pids the watcher started), `current.json`, `run.lock`, `loop.lock`, `unsynced.json`, `mcp-tools.json` |
| `logs\watcher.log` | rotating log, 5 x 5 MB |
| `config.json` | optional overrides of `watcher.DEFAULTS` (budget, devices, input templates, 2-player args, ...) |

## Flow per sha (budget about 10 min, `run_budget_s` 600)

| # | Step | What | Hard fail on | Typical |
|---|---|---|---|---|
| 1 | build | `git fetch`, `checkout --detach --force <sha>`, `clean -ffdx`, then `rojo build` of `default.project.json` plus Workspace `$attributes {DataStoreMode: "Memory"}` (temp `.pcwatcher.project.json`) to `builds\<sha>.rbxl`. `world/*.rbxmx` are tracked. `scripts/gen-world` and `src/visuals/static` are not in the Rojo tree, so nothing else is needed. | git/rojo error | 5-30 s |
| 2 | launch | Kill Studio pids from an earlier watcher run. If any other Studio window has a place open (title `<place> - Roblox Studio`), the run fails with **"studio busy"** and that Studio is never touched. Otherwise start `RobloxStudioBeta.exe <rbxl>` minimized and not active from the newest `Versions\<ver>` that has `StudioMCP.exe`, and move its main window off-screen (see Runs in the background, 1-2). Track it and its child pids. Wait until `list_roblox_studios` lists `<sha>.rbxl` and `get_studio_state` answers (120 s). Edit check: DataStoreMode is Memory (set it in-session if not; never saved). Also save the MCP `screen_capture` edit frame. | not listed in 120 s | 15-40 s |
| 3 | play | `start_stop_play true`, wait for the Client (LocalPlayer, character, `SlimeUI`, `TutorialStepId`; 90 s). Then Heartbeat dt over 5 s (avg / p95 / max / fps), `Stats:GetTotalMemoryUsageMb()`, `InstanceCount`, part counts. | client not up | 20-40 s |
| 4 | perf | Server datamodel: MeshParts in Workspace (wild slimes and characters excluded) and unique MeshIds, polled until three equal counts (max 45 s). Budget is 400. The tracked world has **0** MeshParts: `src/server/MeshSwap` creates them at run time, so the Edit count is info only. | > 400, or 0 | 10-15 s |
| 4b | geometry | Server datamodel, `luau/geometry` driven by `checks.json`; raw numbers, verdict in `watcher.geometry_verdict`. **Front convention (#75, `MeshAssets.IMPORT_YAW` = 180):** the front is `LookVector` of the `Mesh` child MeshSwap parents under a slot (a Part slot's kit front is local +Z and its Mesh is turned 180; a WorldProps Model skin is not turned and its front is -Z; both give Mesh `LookVector`); without a Mesh it falls back to -`LookVector` (Part) / pivot `LookVector` (Model) and says so in `front_src`. Checks: `bench_faces_campfire` (each `CampBench` vs nearest `Campfire`, dot of front and unit(campfire - bench) on XZ >= 0.9), `shops_face_centre` (`ShopStand` + each `BuyStand`, toward plaza centre (0,0), >= 0.9), `silo_centred` (`FountainMesh` Part position + silo offset (-6.52, -7.75) = silo axis, XZ distance to the origin <= 0.05; the raw bbox centre is reported too), `plot_signs` (each `Plots.Plot_n.Sign` SurfaceGui: face normal vs unit(sign - plot Base) >= 0.9, vs the Gate mesh front >= 0.9, frame not mirrored (right x up = back), text per label). Missing instances fail with a message. Result in `report.geometry = {check: {pass, items, errors}}`. | any check fails | 1-5 s |
| 5 | onboarding | The tutorial card (`SlimeUI.TutorialOverlay`) must show for the fresh memory profile. Hide it in-engine (`PcwOpen=""`, else `Visible=false`; method in `hide_method`); the card must hide. | card missing / cannot hide | 5 s |
| 6 | shop | No injected input (`VirtualInputManager` lacks capability RobloxScript in execute_luau; `user_mouse_input` moves the OS cursor). `luau/panel_visible` sets `PcwOpen="Shop"`; `ShopPanel` must become visible. Method (`pcw_open_hook`, else `visible_fallback` = `warn`) goes in `input_methods`. | shop not opened | 5 s |
| 7 | esc | `luau/cas_close`: sets SlimeUI `PcwPress="Escape"` in the Client datamodel; the Studio-only hook runs the `CloseMenu` action handler (`src/ui/MenuClose`); `ShopPanel` must close. Method `pcw_press_hook` (close logic, not key routing); `not_bound` or no answer fails the step. | still open / call error | 2 s |
| 8 | devices | Resize the Studio main window on the `pcw-studio` desktop (SetWindowPos with SWP_NOACTIVATE, DPI-aware) until Client `CurrentCamera.ViewportSize` is 1920x1080, 390x844 and 844x390. The first guess is target + (client - viewport). Then secant steps, up to 5 tries. When Studio or Windows clamps the size, the closest size reached is kept and noted. At each size: HUD + nav buttons (`Hud.*`, `Nav.*` by name) must be inside the ScreenGui rect (viewport minus top bar, 1 px), then every panel is closed (`PcwOpen=""`, nothing else hidden) and one idle frame is captured, before the menus loop. The window goes back to its off-screen rect afterwards. Inside this loop, at each size, the **menus** and **phone_perf** steps below run. | an element off-screen or missing | 60-90 s |
| 8a | menus | Runs in the devices loop, at every size. For each panel in `menu_panels` (plot, merge, shop, rebirth, goals, dex, leaders, guide: `allPanels` in `src/ui/init.client`) `open_panel` opens it (`luau/panel_visible`: `PcwOpen` hook, else `Visible`). `luau/menu_measure` reads AbsoluteSize / ViewportSize, whether the panel is shown and inside the ScreenGui rect (1 px), and whether its `Close` button exists, is shown and is on screen. A cropped frame `<sha>-menu-<panel>-<device>` is captured with the other panels hidden, then the panel is closed (`PcwOpen=""`, else `Visible=false`). **Pass = every panel on screen with a visible close button at every size.** Since #76 the menus are content-sized cards, so `frac_w` / `frac_h` are only reported; a non-full-window panel never fails (a note says so). | any panel off-screen, not openable, or no visible close button | 40-80 s |
| 8b | phone_perf | Runs in the devices loop at the phone sizes (device names starting `phone`). `luau/slime_fill` (Server) counts tagged wild/pad slimes within 70 studs of the character and clones existing ones into a ring around it until there are `phone_min_slimes + 4` (clones carry `PcwFill` and a unique `SlimeId`, because SlimeLife keys on it; the live `World` is a local of `src/server`, so `Spawner.spawnOne` is not reachable from execute_luau). `luau/phone_perf` (Client) waits up to 8 s for 16 slimes with a `LifeRoot` or the client-only `LifeAnimating` attribute (animated rig; the #71 `SlimeLifeRunner` rig; `SlimeLife.MAX_ACTIVE` = 16), then measures `stats_seconds` of RenderStepped dt: avg / p95 / max ms, FPS, memory MB, animating count, slimes within 80 studs. Frame `<sha>-phone-perf-<device>`. The clones are removed after the loop. **Fail if avg FPS < `phone_min_fps` (30).** Fewer than 16 animating is a note, not a failure. Studio on the PC is not phone hardware. | avg FPS < 30 | 25-40 s |
| 9 | shots (soft) | `shots.json` proof frames (a world shot with `seat` first seats a slime on the pad (`luau/slime_seat`, Server: reuses or clones one; reports `gap` = slime bottom - pad top; the clones are removed at the end); a world shot with `motion` (`Idle` / `Hop` / `LookLeft` / `LookRight`) + `wait` makes the Client slime play it through SlimeLifeRunner's procedural SlimeMotor and compares the FaceRoot Transform / Mesh size before and `wait` s later (`luau/slime_motion`: `mode` must be set, `moved` > 0, plus the animating count; a frozen slime logs a note); a world shot with `habitat` + `wait` morphs the target pad on the Client first: `luau/habitat_set`, HABITATS.md), cropped to the game viewport (see Frames). `ui`: open `<Key>Panel` with the `PcwOpen` hook (`luau/panel_visible`; if that fails, set `Visible` directly and contents may be stale). The method goes in the frame entry. The tutorial card, popups and every other `*Panel` are hidden for the capture (`luau/ui_isolate`) and shown again after, then the panel is closed (`PcwOpen=""`, else `Visible=false`). A `ui` entry with `press` (e.g. `"press": "Escape", "expect": "closed"`) runs the in-engine `CloseMenu` call (`cas_callfunction`; the key name is only a label) after opening, asserts the panel closed (`warn` if it was opened by the Visible fallback) and captures the frame after the call. `world`: the Server finds the target (exact name, else substring) and its bounding box. The Client hides every PlayerGui ScreenGui, the CoreGui and every BillboardGui and ProximityPrompt, moves the character behind the camera and anchors it, and locks a Scriptable camera with `BindToRenderStep` at `RenderPriority.Last + 1` (after the default camera scripts) on the target's front side: 35 degrees down, `max(extent)*1.8+15` studs away. Entries can set `index` (nth exact-name match by full name), `from` (`front` = along the #75 front, `look` = raw LookVector, `back`, `centre` = towards the plaza centre, `behind` = away from `aim`), `dist`, `height` and `aim` (second target to look at). A world shot with `slide_walk` (B6) first runs `luau/slide_walk` on the Server: free balls dropped 4 studs onto the start / middle / end of every `SlideFloor<i>` collider, head to mouth, must never sink under a slab's top face (failure = a note and the step warns). `shot_camera_reset` unbinds and restores all of it. Missing targets are frame entries with status `missing`. | never | 0-90 s |
| 10 | two_player | See below (mode c only). | mode c assertion false | 30-40 s |
| 11 | close | Save the console output, stop play, `taskkill /T /F` the tracked pids (no WM_CLOSE, so no save prompt), then verify no watcher Studio process is left and kill leftovers. | - | 5-20 s |
| 12 | report + sync | Write `out\<sha>\<sha>.json`, then commit to `studio-reports` and push. | - | 5 s |

A step that is skipped because an earlier step failed, or because the run budget ran out, also
fails the run. Exceptions: `shots`, and `two_player` reporting "not run".

### Frames

`<sha>-<device>.jpg` is the StudioMCP `screen_capture` of the game viewport (GUI included, play mode too; unique
`capture_id` per call, base64 `image/jpeg`), exactly the viewport, so no cropping or magenta probe is needed.
PrintWindow gives a blank viewport on the hidden desktop and is not used. A frame is **rejected** (kept as `*-rejected.png`, listed in `notes`, frame entry status `blank` or
`missing`) when it is blank (luma variance < 40 or < 12
colours on a 64x64 sample grid) or when the window title is not Studio's.

### Two players

Studio's "Start Server + N players" is not an MCP tool. Tried in this order:

- **a**: probes `StudioTestService` / `TestService` from Edit for a multi-client API. It only reads; none is known, so it always falls through.
- **b**: removed. It started extra `RobloxStudioBeta.exe -task StartServer` / `-task StartClient` processes, which opened visible Studio windows (see Runs in the background, 7). The `twoplayer_*` config keys are gone.
- **c**: starts one play session and runs `luau/server_steal_sim.luau` in the Server datamodel. On a fresh pure `World` built with the real server modules (`World`, `Sessions`, `Carry`), two stand-in sessions join and get distinct plots. The victim's slime is grabbed and deposited by the thief, and must move. This needs no real second client and no DataStore, and does not touch the live world. It tests the steal flow, not replication.

`steps.two_player.detail.mode` says which mode ran (`c-server-sim`, `not run`) and why
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
    "menus": {"detail": {"panels": [...], "devices": [...]}}, "phone_perf": {"detail": {...}},
    "devices": {"detail": {"devices": {"desktop": {"target": [1920,1080], "viewport": [1900,1002], "exact": false,
                                                   "hud": {"offscreen": [], "missing": []}, "frame": {...}}}}},
    "two_player": {"detail": {"mode": "c-server-sim", "tried": [...], "assertion": "..."}},
    "shots": ...
  },
  "perf": {"mesh_slots": 324, "unique_meshes": 61, "budget": 400, "frame_time_ms": 16.7, "memory_mb": 1450.2,
           "parts": 1100, "play": {...},
           "phone": {"phone-portrait": {"avg_ms": 9.8, "p95_ms": 14.1, "max_ms": 31.0, "fps": 102.0, "memory_mb": 1460.0,
                                        "animating": 16, "slimes_near": 22, "fill": {...}, "pass": true,
                                        "frame": "<sha>-phone-perf-phone-portrait.jpg"}}},
  "menus": {"phone-portrait": {"shop": {"frac_w": 0.82, "frac_h": 0.61, "on_screen": true, "close_button": true,
                                          "frame": "<sha>-menu-shop-phone-portrait.jpg"}}},
  "frames": [
    {"id": "desktop", "file": "<sha>-desktop.jpg", "status": "captured", "todo": null, "kind": "device", "method": "mcp_screen_capture", "size": [1920, 1080], "crop": null},
    {"id": "shot-02-dex-menu", "file": "<sha>-shot-02-dex-menu.png", "status": "captured", "todo": "2", "kind": "shot", "crop": [312, 96, 1280, 720], "open_method": "pcw_open_hook"},
    {"id": "shot-11-signpost", "file": null, "status": "missing", "todo": "11", "kind": "shot", "error": "target 'Signpost' not found"}
  ],
  "input_methods": {"virtual_input_manager": "not tried: ...", "open": "pcw_open_hook", "esc": "pcw_press_hook: closed"},
  "background": {"foreground_at_start": [131330, 8812], "focus_stolen": [], "mcp_input": false},
  "close": {...}, "watcher_version": "1.0.0"
}
```

`frames[].status` is `captured`, `missing` (no target or button, capture failed, run budget) or `blank`.
`todo` is the shot's TODO item (shots.json `todo`, else the `TODO n:` prefix of its `note`). The
sync rewrites `file` to the `.jpg` name when it converts.

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

- **Unverified on the PC.** This was written on the box, where Studio, StudioMCP and Win32 are not available. The pure parts are covered by `selftest.py`; `step build` and `step sync` were run against a local clone and bare remote; every Luau body compiles under lune.
- Device sizes come from resizing the Studio window, not the device emulator, which is not scriptable (`StudioDeviceEmulatorService` is nil to execute_luau). So there is no touch input and no on-screen thumbstick (`Layout.TOUCH_CONTROLS_HEIGHT` is not exercised). Studio's minimum window size and the monitor size can stop a target from being reached exactly; the closest size is reported.
- Frame time is Studio play-mode on this PC (client and server in one process). Studio runs on a hidden desktop, unfocused, and Windows may throttle that, so treat it as a trend, not a device number. There is no triangle count from Luau; use `tools/pr-gate/budget.sh`.
- Tutorial advance (grab with E) needs a wild slime the starting cash can buy. It is reported, and never fails the run.
- Two players is mode c only: a simulation on the server modules, not two real clients (mode b opened visible windows).
- Background behaviour depends on Studio honouring `SW_SHOWNOACTIVATE` and not activating itself . The watcher cannot prevent that; the focus guard reports it as `FOCUS STOLEN at step X` and fails the run.
- One watcher Studio at a time. A user Studio with a place open blocks the run ("studio busy"); a user Studio on the start page is left alone.
