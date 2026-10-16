# PC watcher (Steal a Slime Studio check)

Runs on Merijn's Windows PC (`C:\gate\pc-watcher`). For every new `origin/main` sha it builds the
game, opens it in Roblox Studio, plays it, checks perf, input, menus and HUD layout at three
viewport sizes, tries a 2-player test, and pushes a JSON report plus frames to the orphan branch
`studio-reports`. The box copies those reports to `/workspace/roblox/pipeline/studio-reports/`,
where `games/steal-a-slime/tools/pipeline/cloud-test.sh` reads them (`gate_ready` needs `pass`).

Studio is driven **only** through Roblox's `StudioMCP.exe` (stdio JSON-RPC, `mcp_client.py`). Win32
(ctypes, `win32.py`) is used only to place and size the window off-screen and to capture it. Nothing is
saved, published or uploaded, and the test build runs on the in-memory DataStore.

## Runs in the background

Hard requirement: the watcher runs while Merijn uses the PC. It never steals focus and never touches
the real mouse or keyboard.

1. **Launch, minimized and not active.** `win32.launch_background` starts Studio with
   `subprocess.Popen` and a `STARTUPINFO` with `dwFlags = STARTF_USESHOWWINDOW` and
   `wShowWindow = 7` (`SW_SHOWMINNOACTIVE`). Verified on the PC: the foreground window did not change
   during launch.
2. **Moved off-screen, without activating.** `win32.studio_main_window` enumerates every top-level
   window of the pids we started (`EnumWindows` by pid, visible or not, minimized/iconic included) and
   judges size by the restored rect (`rcNormalPosition`), because an iconic window's `GetWindowRect` is a
   small caption at -32000. If no window has a title yet it falls back to any unowned window of the pid,
   like .NET's `Process.MainWindowHandle`. `win32.place_offscreen` then does `GetWindowPlacement`, sets
   `rcNormalPosition` left of every monitor (x = `GetSystemMetrics(SM_XVIRTUALSCREEN)` - window width - 100,
   y = `SM_YVIRTUALSCREEN`), sets `showCmd = SW_SHOWNOACTIVATE` (4) and calls `SetWindowPlacement`. This
   runs while the launch step waits for MCP, and again once the main window is final. Verified on the PC:
   un-minimized, client 1920x1080 at x=-3000, `PrintWindow(PW_RENDERFULLCONTENT)` captured the 3D viewport,
   focus unchanged.
3. **Device sizes stay off-screen.** `win32.set_client_size` uses `SetWindowPos` with
   `SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER` and recomputes x from the new width, so the window
   stays left of all monitors at every size. If the window is ever minimized or maximized again, it is
   re-placed with step 2 (`SetWindowPlacement`, `SW_SHOWNOACTIVATE`). The watcher never maximizes or
   restores.
4. **No foreground calls, one capture method.** `bring_to_front`, `SetForegroundWindow`,
   `BringWindowToTop`, `ShowWindow` (maximize / restore), `keybd_event` (the old Alt tap) and the
   `bitblt` / `screen` (BitBlt from the screen DC) capture methods are gone. Capture is
   `PrintWindow(hwnd, dc, PW_RENDERFULLCONTENT)` (flag 2) of the whole window, cropped to the client
   area. The window draws itself into the watcher's bitmap, so it works off-screen and unfocused.
   `selftest.py` fails if any of those names come back into `win32.py`, `watcher.py` or `mcp_client.py`.
5. **No real input.** The only input is in-engine: StudioMCP `user_mouse_input` and
   `user_keyboard_input` (shop click, Escape, E, panel clicks) inject into the engine, not through OS
   `SendInput`. Each call is guarded (`Run._mcp_input`): `GetCursorPos` before and after. If the OS cursor
   moved, MCP input is off for the rest of the run, the report notes `mcp input moved OS cursor`, and the
   steps fall back to setting `Visible` (`luau/panel_visible`): onboarding hides `TutorialOverlay`, shop
   opens `ShopPanel`, esc closes it, shots open and close panels. Those steps then end `warn` (input not
   tested), not `pass`. The Escape press is kept because it goes through `user_keyboard_input` too. A
   real mouse move by Merijn during the call also trips the guard; that only costs input coverage. The
   fallback stays, and the guard now logs the delta: the note and `background.cursor_events` (`call`,
   `before`, `after`, `delta`, `dist_px`) show how far the cursor moved, so a ~14 px nudge (probably the
   user's own mouse) can be told from a real injected-input jump.
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

## Flow per sha (budget about 10 min, `run_budget_s` 600)

| # | Step | What | Hard fail on | Typical |
|---|---|---|---|---|
| 1 | build | `git fetch`, `checkout --detach --force <sha>`, `clean -ffdx`, then `rojo build` of `default.project.json` plus Workspace `$attributes {DataStoreMode: "Memory"}` (temp `.pcwatcher.project.json`) to `builds\<sha>.rbxl`. `world/*.rbxmx` are tracked. `scripts/gen-world` and `src/visuals/static` are not in the Rojo tree, so nothing else is needed. | git/rojo error | 5-30 s |
| 2 | launch | Kill Studio pids from an earlier watcher run. If any other Studio window has a place open (title `<place> - Roblox Studio`), the run fails with **"studio busy"** and that Studio is never touched. Otherwise start `RobloxStudioBeta.exe <rbxl>` minimized and not active from the newest `Versions\<ver>` that has `StudioMCP.exe`, and move its main window off-screen (see Runs in the background, 1-2). Track it and its child pids. Wait until `list_roblox_studios` lists `<sha>.rbxl` and `get_studio_state` answers (120 s). Edit check: DataStoreMode is Memory (set it in-session if not; never saved). Also save the MCP `screen_capture` edit frame. | not listed in 120 s | 15-40 s |
| 3 | play | `start_stop_play true`, wait for the Client (LocalPlayer, character, `SlimeUI`, `TutorialStepId`; 90 s). Then Heartbeat dt over 5 s (avg / p95 / max / fps), `Stats:GetTotalMemoryUsageMb()`, `InstanceCount`, part counts. | client not up | 20-40 s |
| 4 | perf | Server datamodel: MeshParts in Workspace (wild slimes and characters excluded) and unique MeshIds, polled until three equal counts (max 45 s). Budget is 400. The tracked world has **0** MeshParts: `src/server/MeshSwap` creates them at run time, so the Edit count is info only. | > 400, or 0 | 10-15 s |
| 4b | geometry | Server datamodel, `luau/geometry` driven by `checks.json`; raw numbers, verdict in `watcher.geometry_verdict`. **Front convention (#75, `MeshAssets.IMPORT_YAW` = 180):** the front is `LookVector` of the `Mesh` child MeshSwap parents under a slot (a Part slot's kit front is local +Z and its Mesh is turned 180; a WorldProps Model skin is not turned and its front is -Z; both give Mesh `LookVector`); without a Mesh it falls back to -`LookVector` (Part) / pivot `LookVector` (Model) and says so in `front_src`. Checks: `bench_faces_campfire` (each `CampBench` vs nearest `Campfire`, dot of front and unit(campfire - bench) on XZ >= 0.9), `shops_face_centre` (`ShopStand` + each `BuyStand`, toward plaza centre (0,0), >= 0.9), `silo_centred` (`FountainMesh` Part position + silo offset (-6.52, -7.75) = silo axis, XZ distance to the origin <= 0.05; the raw bbox centre is reported too), `plot_signs` (each `Plots.Plot_n.Sign` SurfaceGui: face normal vs unit(sign - plot Base) >= 0.9, vs the Gate mesh front >= 0.9, frame not mirrored (right x up = back), text per label). Missing instances fail with a message. Result in `report.geometry = {check: {pass, items, errors}}`. | any check fails | 1-5 s |
| 5 | onboarding | The tutorial card (`SlimeUI.TutorialOverlay`) must show for the fresh memory profile. Click its `Hide`; the card must hide. Later (soft): teleport next to the cheapest wild slime, press **E** through `user_keyboard_input`, and record whether `TutorialStepId` moved past `Grab`. | card missing / Hide no effect | 5 s |
| 6 | shop | `VirtualInputManager` is not used: on the PC, execute_luau gets "lacking capability RobloxScript" for `SendMouseButtonEvent` and `SendKeyEvent`. Clicks use `user_mouse_input` (down, 120 ms, up, `mouse_button: "left"`) at the centre of `Hud.Shop` (then `Nav.Shop`): AbsolutePosition + AbsoluteSize/2 + GuiInset. If that has no effect, the click is retried without the GuiInset. `ShopPanel` must become visible. Every attempt's coordinates and MCP results are logged and go in `input_methods`. | shop not opened | 5 s |
| 7 | esc | `user_keyboard_input` Escape (always with `datamodel_type: Client`, else the tool rejects it); `ShopPanel` must close (game binds Esc via ContextActionService, `src/ui/MenuClose`). | still open | 2 s |
| 8 | devices | Resize the off-screen Studio main window (SetWindowPos with SWP_NOACTIVATE, DPI-aware) until Client `CurrentCamera.ViewportSize` is 1920x1080, 390x844 and 844x390. The first guess is target + (client - viewport). Then secant steps, up to 5 tries. When Studio or Windows clamps the size, the closest size reached is kept and noted. At each size: HUD + nav buttons (`Hud.*`, `Nav.*` by name) must be inside the ScreenGui rect (viewport minus top bar, 1 px), then one frame is captured. The window goes back to its off-screen rect afterwards. Inside this loop, at each size, the **menus** and **phone_perf** steps below run. | an element off-screen or missing | 60-90 s |
| 8a | menus | Runs in the devices loop, at every size. For each panel in `menu_panels` (plot, merge, shop, rebirth, goals, dex, leaders, guide: `allPanels` in `src/ui/init.client`) `open_panel` opens it (MCP click on `Nav.<Key>` if the cursor guard allows, else `luau/panel_visible`; Guide has no nav button, so it is always the Visible path). `luau/menu_measure` reads AbsoluteSize / ViewportSize, whether the panel is shown and inside the ScreenGui rect (1 px), and whether its `Close` button exists, is shown and is on screen. A cropped frame `<sha>-menu-<panel>-<device>` is captured with the other panels hidden, then the panel is closed (Esc, `Close`, `Visible=false`). **Pass = every panel on screen with a visible close button at every size.** Since #76 the menus are content-sized cards, so `frac_w` / `frac_h` are only reported; a non-full-window panel never fails (a note says so). | any panel off-screen, not openable, or no visible close button | 40-80 s |
| 8b | phone_perf | Runs in the devices loop at the phone sizes (device names starting `phone`). `luau/slime_fill` (Server) counts tagged wild/pad slimes within 70 studs of the character and clones existing ones into a ring around it until there are `phone_min_slimes + 4` (clones carry `PcwFill` and a unique `SlimeId`, because SlimeLife keys on it; the live `World` is a local of `src/server`, so `Spawner.spawnOne` is not reachable from execute_luau). `luau/phone_perf` (Client) waits up to 8 s for 16 slimes with a `LifeRoot` (the #71 `SlimeLifeRunner` rig; `SlimeLife.MAX_ACTIVE` = 16), then measures `stats_seconds` of RenderStepped dt: avg / p95 / max ms, FPS, memory MB, animating count, slimes within 80 studs. Frame `<sha>-phone-perf-<device>`. The clones are removed after the loop. **Fail if avg FPS < `phone_min_fps` (30).** Fewer than 16 animating is a note, not a failure. Studio on the PC is not phone hardware. | avg FPS < 30 | 25-40 s |
| 9 | shots (soft) | `shots.json` proof frames (a world shot with `habitat` + `wait` morphs the target pad on the Client first: `luau/habitat_set`, HABITATS.md), cropped to the game viewport (see Frames). `ui`: open `<Key>Panel` by an MCP click on the text-less nav icon `Nav.<Key>` (then `Hud.<Key>`). If no click opens it, set `Visible` directly (`luau/panel_visible`; the UI has no open hook, so contents may be stale). The method goes in the frame entry. The tutorial card, popups and every other `*Panel` are hidden for the capture (`luau/ui_isolate`) and shown again after. Capture, then close with Esc, else `<Key>Panel.Close`, else `Visible=false`. A `ui` entry with `press` (e.g. `"press": "Escape", "expect": "closed"`) presses that key after opening and asserts the panel closed instead of capturing a frame (`warn` if it was opened by the Visible fallback). `world`: the Server finds the target (exact name, else substring) and its bounding box. The Client hides every PlayerGui ScreenGui, the CoreGui and every BillboardGui and ProximityPrompt, moves the character behind the camera and anchors it, and locks a Scriptable camera with `BindToRenderStep` at `RenderPriority.Last + 1` (after the default camera scripts) on the target's front side: 35 degrees down, `max(extent)*1.8+15` studs away. Entries can set `index` (nth exact-name match by full name), `from` (`front` = along the #75 front, `look` = raw LookVector, `back`, `centre` = towards the plaza centre, `behind` = away from `aim`), `dist`, `height` and `aim` (second target to look at). `shot_camera_reset` unbinds and restores all of it. Missing targets are frame entries with status `missing`. | never | 0-90 s |
| 10 | two_player | See below (mode c only). | mode c assertion false | 30-40 s |
| 11 | close | Save the console output, stop play, `taskkill /T /F` the tracked pids (no WM_CLOSE, so no save prompt), then verify no watcher Studio process is left and kill leftovers. | - | 5-20 s |
| 12 | report + sync | Write `out\<sha>\<sha>.json`, then commit to `studio-reports` and push. | - | 5 s |

A step that is skipped because an earlier step failed, or because the run budget ran out, also
fails the run. Exceptions: `shots`, and `two_player` reporting "not run".

### Frames

`<sha>-<device>.png` holds the client area of the Studio window (`PrintWindow` with
`PW_RENDERFULLCONTENT`, the only method; the window is off-screen). Device frames are full-window, so they
include Studio's panels. Shot frames (`<sha>-shot-<id>.png`) are cropped to the game viewport. To
find it, `luau/viewport_probe` shows a full-screen magenta ScreenGui above everything. The watcher
captures the window and takes the magenta bounding box (exact colour, else within 12). The rect is
cached per window size and recorded in `steps.shots.detail.viewport_rect`, with `scale` = capture px
per ViewportSize px. If the probe is not found, frames stay full-window and a note says so. A frame
is **rejected** (kept as `*-rejected.png`, listed in `notes`, frame entry status `blank` or
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
    {"id": "desktop", "file": "<sha>-desktop.png", "status": "captured", "todo": null, "kind": "device", "method": "printwindow", "size": [1920, 1080], "crop": null},
    {"id": "shot-02-dex-menu", "file": "<sha>-shot-02-dex-menu.png", "status": "captured", "todo": "2", "kind": "shot", "crop": [312, 96, 1280, 720], "open_method": "mcp_click:Nav.Dex"},
    {"id": "shot-11-signpost", "file": null, "status": "missing", "todo": "11", "kind": "shot", "error": "target 'Signpost' not found"}
  ],
  "input_methods": {"virtual_input_manager": "not tried: ...", "mcp_mouse:Hud.Shop": "works", "mcp_keyboard:Escape": "works"},
  "background": {"foreground_at_start": [131330, 8812], "focus_stolen": [], "mcp_input": true, "cursor_events": []},
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

- **Unverified on the PC.** This was written on the box, where Studio, StudioMCP and Win32 are not available. The pure parts are covered by `selftest.py`; `step build` and `step sync` were run against a local clone and bare remote; every Luau body compiles under lune. The input action shapes are built from the tools' `inputSchema` (`mcp_client.build_action`) because the schemas were not available here. If Studio rejects them, set `input_overrides` in `config.json`, for example `{"mouse_down": {"type": "mouseButtonDown", "x": "$x", "y": "$y"}}`.
- Device sizes come from resizing the Studio window, not the device emulator, which is not scriptable (`StudioDeviceEmulatorService` is nil to execute_luau). So there is no touch input and no on-screen thumbstick (`Layout.TOUCH_CONTROLS_HEIGHT` is not exercised). Studio's minimum window size and the monitor size can stop a target from being reached exactly; the closest size is reported.
- Frame time is Studio play-mode on this PC (client and server in one process). The window is always unfocused and off-screen, and Studio throttles that, so treat it as a trend, not a device number. There is no triangle count from Luau; use `tools/pr-gate/budget.sh`.
- Tutorial advance (grab with E) needs a wild slime the starting cash can buy. It is reported, and never fails the run.
- Two players is mode c only: a simulation on the server modules, not two real clients (mode b opened visible windows).
- Background behaviour depends on Studio honouring `SW_SHOWNOACTIVATE` and not activating itself . The watcher cannot prevent that; the focus guard reports it as `FOCUS STOLEN at step X` and fails the run.
- One watcher Studio at a time. A user Studio with a place open blocks the run ("studio busy"); a user Studio on the start page is left alone.
