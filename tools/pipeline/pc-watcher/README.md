# PC watcher (MVP)

Runs on Merijn's Windows PC (`C:\gate\pc-watcher`). For every new `origin/main` sha it builds
Steal a Slime, opens it in Roblox Studio, plays it, measures it, takes screenshots and pushes a
report to the orphan branch `studio-reports`. Studio is driven only through StudioMCP (stdio
JSON-RPC, `mcp_client.py`) plus Win32 window capture (`win32.py`). Nothing is published.

## Commands

```
python watcher.py once [--sha SHA] [--no-sync]   # one full run (default: current origin/main)
python watcher.py loop                           # poll every 60s, run `once` on a new sha
python watcher.py shots-only [--sha TAG]         # shot list only, against a Studio already in play
```

`install.ps1` registers the Scheduled Task `StealASlime-PCWatcher` (at logon, interactive,
`pythonw watcher.py loop`); `install.ps1 -Uninstall` removes it. Log: `C:\gate\pc-watcher\logs\watcher.log`.

## Layout on the PC

| path | what |
|---|---|
| `repo\` | repo clone; checked out detached at the sha under test |
| `bin\rojo.exe` | rojo 7.7.1 |
| `builds\<sha>.rbxl` | last 5 builds |
| `reports\` | clone of branch `studio-reports` (`studio-reports\<sha>.json` + `studio-reports\<sha>\*.jpg`) |
| `last-sha`, `studio-pids.json`, `watcher.lock` | state |

## Flow (`once`, ~1-2 min)

1. `git fetch` + checkout sha, `rojo build` (<1s).
2. Fail "studio busy" if any Studio is running that we did not start. Launch Studio with the rbxl,
   wait until MCP lists `<sha>.rbxl` (~10s, timeout 120s).
3. `start_stop_play` start; wait for the Server datamodel.
4. Perf: Server `workspace` MeshParts / unique MeshIds / BaseParts (the world is generated at run time,
   so Edit has 0 meshes); budget MeshParts <= 400. Client: avg RenderStepped dt over 3s, `Stats` memory.
5. Devices: resize the Studio window to a 1920x1080 client area, HUD check + capture `pc`; restore; HUD
   check + capture `current`. HUD check = every visible GuiButton in `SlimeUI` fully inside the viewport.
6. Onboarding + shop: click visible buttons matching next/continue/ok/skip/got it/start (VirtualInputManager,
   centre + GuiInset), capture; click `shop`, expect a `*Shop*Panel` visible, capture; Escape closes it.
7. Shot list `shots.json` (below).
8. 2-player: stub, reported as not run (TODO).
9. Stop play, WM_CLOSE Studio, kill after 15s. Write report, commit + push `studio-reports` (3 tries, `pull --rebase`).

## Report `studio-reports/<sha>.json`

```
{sha, status: "pass"|"fail", checked_at, studio_version, notes: [..], duration_s,
 perf: {budget, mesh_parts, unique_meshes, base_parts, frame_time_ms, memory_mb, viewport},
 steps: {<name>: {ok, detail}}, frames: [{id, file, ok, method, w, h, stats, error?}]}
```

`status` is fail when a hard step fails: build, launch, play, mesh budget, HUD offenders, shop opening.
Frames are JPEG q80 `<sha>/<sha>-<id>.jpg`; a blank frame (`imaging.is_blank`) is recorded with `ok: false`.

## Shot list (`shots.json`) - bots: add your proof frames here in your PR

```
{"id": "06-fountain-centre", "kind": "world", "target": "FountainMesh"}       # name match in Server workspace
{"id": "06-map-top", "kind": "world", "pos": [0, 260, 1], "look": [0, 0, 0]}  # fixed camera
{"id": "03-shop-menu", "kind": "ui", "open": "shop"}                          # click button, capture, Escape
```

`target`: exact name first, else first case-insensitive substring match (Models and BaseParts). The
camera sits in front of the target's bounding box, raised, 1.6x its size back. Missing target or button
= note only, the run does not fail. Frame file: `<sha>-<id>.jpg`.

## Box side

`box-pull.sh [--loop 60]` fetches `studio-reports` and copies it to `/workspace/roblox/pipeline/studio-reports/`.
Pushes to `studio-reports` are ignored by `cheap-gates.yml`.

## Limits (MVP)

- Phone sizes are not driven: Studio's device emulator is not scriptable and its state persists
  (currently 844x390); the report records the viewport actually seen.
- 2-player test not run.
- Escape may open the Roblox menu when nothing consumes it; the watcher closes it again.
- One Studio at a time; a user's own Studio session makes the run fail with "studio busy".
