# Roblox live testing from the Linux box

> **Restored 2026-10-15 from workspace notes after /guides loss; verify.** Sections 0–3, "Recommendation" and the three dated sections after it are the original text as of 2026-10-15 07:33Z, rebuilt by replaying Claude Code transcript edits. Sections 4–5 are new, written from `/workspace/roblox/live-testing/` (`ci/GUIDE-SECTION.md`, `ci/run.py`, `ci/cron.sh`, `ci/install-cron.sh`, `cc*.log`). Notes marked *[restore note]* were added during the restore.

Tested 2026-10-15 on Steal a Slime v10 (universe 10770917350, place 135787188192378). Work files: `/workspace/roblox/live-testing/` (`static-report.md`, `export.luau`, `render.py`, `annotate.py`, `renders/`).
Toolchain setup: `/guides/roblox-toolchain-linux.md`. Build and publish: `/guides/roblox-build-and-publish.md`.

Short version:
- The **headless boot test** (§0, Lune, about 1 s) works today. It runs the real server Script from the built place and catches server crashes, missing slimes and missing props.
- The **static render** (§1) works today.
- **Open Cloud Luau Execution** (§2) is the **primary runtime check** and works (scope granted 2026-10-15). It runs your script in a real Roblox server for the published place. Caveat: the place's own Scripts and physics do NOT run, so the task script boots the server modules itself (`tools/livetest/cloud/live.luau`).
- Running Studio or the Player on this box is not viable (§3).
- **24/7 CI** (§4): `ci/run.py` runs a Luau Execution playtest from cron at :07 and :37 every hour. It needs `install-cron.sh` re-run after every reboot.
- Graphics work: see §5 and `/workspace/roblox/graphics-strategy.md`.
- **Release gate without publishing** (§6): upload as **Saved**, then `run.py --version N` / `release-check.sh N` on that exact version. Only Merijn OKs a live publish.
- Final visual sign-off still needs Merijn to look at it.

## 0. Headless boot test (works, ~1 s, no network)

Repo: `steal-a-slime-b0/tools/livetest/` (README there). Added 2026-10-15 by Jolt/cc.

```bash
cd /workspace/roblox/steal-a-slime-b0 && export PATH=$HOME/.local/bin:$PATH
rojo build -o /tmp/build.rbxlx
lune run tools/livetest/run /tmp/build.rbxlx --seconds 60 [--player] [--mesh] [--verbose]
lune run tools/livetest/run steal-a-slime.rbxl          # the exact binary that was published
lune run tests                                          # includes tests/LiveBoot.spec.luau
```

`Runtime.luau` is a small fake Roblox server built on `@lune/roblox`:
- It loads the place and runs every `Script` under ServerScriptService from its `Source`, through `luau.load` with a Roblox-like environment: `game`, `workspace`, `script`, `require(instance)`, `task`, `warn`.
- A virtual clock drives `task.wait` / `spawn` / `delay`, `RunService.Heartbeat` and `GetServerTimeNow`, so 60 s of server time runs in under a second.
- It stubs the engine APIs Lune lacks: events, WaitForChild, PivotTo/GetPivot, Players, in-memory DataStores, HttpService, InsertService (fails by default, like a server without access to the asset), Debris, and an AABB Raycast.

`Checks.luau` then checks:
- slime models in `workspace.WildSlimes`, and that they are on the ground;
- the ShopStand, LeaderboardBoard and TutorialNpc props;
- empty TextLabels, and sign parts with no text;
- `[Server]` warnings and script errors.

Extra tools:
- `--patch <Full.Name> <find> <replace>` edits a script's Source **in memory only**, so you can test a fix hypothesis without touching `src/`.
- `lune run tools/livetest/zfight <place> [Workspace.Map] [eps]` lists coplanar overlapping faces, a static hint for z-fighting.
- `lune run tools/livetest/cloud-local <place> [cloud script]` dry-runs a Luau Execution script locally before you spend cloud quota.

What it found on v10 (and v9; the bug has been there since a52a4a9, 2026-10-14 23:26):
- `ServerScriptService.Server` **dies at boot**. The error is `Requested module experienced an error while loading: Server.WorldView: Server.SlimeMesh: Shared is not a valid member of ServerScriptService`.
- The cause is `src/server/SlimeMesh.luau:24-25`, which uses `script.Parent.Parent.Shared.Config`. SlimeMesh lives in `ServerScriptService.Server`, so `script.Parent.Parent` is ServerScriptService, but Shared is in ReplicatedStorage.
- Because `require(script.WorldView)` is at the top of `init.server.luau:46`, nothing after it runs: no Remotes, no spawner, no props, no DataStore loads.
- That explains **no slimes**. It also explains **empty signs**: no ShopStand "SHOP" sign and no leaderboard board get placed, and the 8 plot Signs never had any text, because no code writes any.
- The Lune unit tests missed it because under Lune `script` is nil, so they only exercise the `require("../shared/Config")` path.
- With `--patch ServerScriptService.Server.SlimeMesh script.Parent.Parent.Shared 'game:GetService("ReplicatedStorage").Shared'` everything passes except the plot signs: 18 slimes (the cap) in 90 s, all props present, 0 warnings.

Limits:
- No physics, replication, rendering or client LocalScripts.
- Engine behaviour is approximated (Raycast uses AABBs; LoadAsset is stubbed).
- A green run means "the server boots and does the right things to the DataModel", not "it looks right".
- Lune quirks the runtime works around:
  - `implementMethod` / `implementProperty` can't override a built-in member, and instance metatables are locked. So `x.Position` reads are rewritten to `CFrame.Position`, and `game:GetService("CollectionService")` is swapped for a proxy at load time.
  - Reflected properties without a default (JobId, Humanoid.Health) must be set before they are read.

## 1. Static render (works, ~25 s)

Build the place, dump it to JSON with Lune, then render the JSON in headless Blender.

```bash
cd /workspace/roblox/live-testing
export PATH=$HOME/.local/bin:$PATH
# v10src = `git archive e4f2ec6` of steal-a-slime-b0, plus the gitignored Packages/ copied in (needed for a byte-identical build)
(cd v10src && rojo build -o ../v10.rbxl)            # cmp-identical to the published steal-a-slime.rbxl
lune run export.luau v10.rbxl v10.json              # parts, GUI texts, Slime_* models, spawns, scripts
~/.local/bin/blender -b --python render.py -- v10.json renders   # Blender 4.5 Cycles, 24 samples, denoised, 1280x720
python3 annotate.py v10.json renders                # *_annotated.png: sign positions + text, HubSpawn, counts
```

Output: `renders/overview.png`, `spawn.png`, `volcano.png`, plus an `*_annotated.png` copy of each. The black band at the top of `overview.png` is distant sky, not missing geometry.

What it showed for v10:
- **All 8 plot Signs are blank.** The place has 0 SurfaceGui/BillboardGui TextLabels, and nothing in `src/` writes text onto a Sign at runtime. Runtime GUIs exist only on leaderboard boards and slime NameTags.
- **0 `Slime_*` models at load.** The server creates them later (`ModelFactory` → `Slime_<id>`).
- **Volcano:** 32 anchored parts at the origin. That's 5 Basalt cylinders up to y=40, a Neon crater, 10 rim blocks and 16 Neon lava slabs.
- **0 floating parts** in an AABB contact check, and every part is Anchored. There is 1 SpawnLocation (`HubSpawn`).

Limits:
- It shows the place file only. **No runtime scripts run**, so anything scripts create (slimes, sign text, leaderboards) is missing.
- No particles or effects.
- Lighting is only approximate. Materials are flat colours and Roblox lighting/post-processing isn't reproduced.
- **No client UI** (ScreenGuis, LocalScript output).

## 2. Open Cloud Luau Execution API (primary runtime check; works)

Docs: https://create.roblox.com/docs/cloud/reference/features/luau-execution and https://create.roblox.com/docs/cloud/reference/LuauExecutionSessionTask (checked 2026-10-15).

What the environment is:
- A headless **server** for one place version: the latest one, or `/versions/{v}/`.
- No players, no physics, no client.
- **The place's own Scripts do NOT start.** So you can't "wait for the Server bootstrap". The task script has to `require` the server modules and drive them itself.
- DataModel changes are thrown away when the task ends.
- **DataStores are real**, so never run code that saves.
- `task.wait` works within the time limit. It is not documented but is expected; the local dry run uses it.

Limits:
- Script up to 4 MB.
- Up to 5 min run time (the `timeout` field, default 5 min).
- Return value up to 4 MB as JSON.
- Logs up to 450 KB.
- At most 10 unfinished tasks per place (HTTP 429 beyond that).
- Rate limits: create 5/min, get 200/min, logs 45/min (per key owner).
- Tasks are kept for 24 h.

**The no-scripts / no-physics caveat (most important fact here).** A task gets the published DataModel, but `ServerScriptService.Server` never starts. Re-enabling it (`Enabled = false/true`) does nothing either (tried 2026-10-15). Physics doesn't step, so nothing falls or touches. `RunService.Heartbeat` *does* fire (~50/s) and `task.wait` works, and `InsertService:LoadAsset` works (SlimeLook came back `Mesh`). A task script that just waits and reads `workspace` therefore sees the static place (0 slimes, blank signs) whatever the game code does. It must `require` the server modules and drive them.

How to run (repo `tools/livetest/cloud/`; the primary script is `live.luau`):
```bash
cd /workspace/roblox/steal-a-slime-b0
# 1. dry run locally first (free, ~1 min). Any .rbxl/.rbxlx of the same version:
lune run tools/livetest/cloud-local /workspace/roblox/live-testing/v10.rbxl tools/livetest/cloud/live.luau --seconds 120
# 2. real server, latest published version (append a version number to pin one):
OUT=tools/livetest/results/boot-$(date +%Y%m%d-%H%M%S).json \
  tools/livetest/cloud/run.sh tools/livetest/cloud/live.luau
jq '.result.boot | {shim, requireErrors, steps, worldWild}' tools/livetest/results/boot-*.json
```
`ROBLOX_OPEN_CLOUD_API_KEY` must be set in the environment. Never echo it; `run.sh` passes it to curl on stdin.

What `live.luau` does (~75 s, all pcall'd, returns one JSON string that `run.sh` decodes into `.result`):
1. **passive** (10 s): waits for a self-boot (it never happens) and snapshots the static place.
2. **boot**: sets `workspace.DataStoreMode = "Memory"` (no real DataStore is ever touched) and `require`s every module under `ServerScriptService.Server`. Then it replays `init.server.luau` without players: `Remotes.setup`, `WorldView.setup` (runs WorldBuilder and SlimeMesh), `WorldProps.place` / `addShopPrompts` / `fillBoard`, `World.new`, a memory-mode leaderboard refresh, then 60 s of the Heartbeat body (`GameLoop.step`, rain attribute, `WorldView.reconcile` / `updatePlots`, `World.drain`) and one `Spawner.forceRain`.
   - If `WorldView` fails to require, it records the error and retries on a clone of `Server` with `ServerScriptService.Shared` present. That works around the v10 SlimeMesh path bug so the rest stays observable. `boot.shim = true` marks this; anything seen after the shim is "what the fixed build would do".
3. **snapshot** (after each phase): slimes (`CollectionService` tag `Slime`, `WildSlimes` and plot `Slimes` folders, pivot / radius / anchored for 25 wild ones). Every TextLabel/TextButton under a SurfaceGui/BillboardGui in workspace, with empty ones listed by path. Per-plot Sign label counts. Unanchored non-slime BaseParts, parts below the ground top, NaN/huge sizes. Every Volcano part (anchored, collide, material, size, position, effects), duplicates, and lava/chute/crater parts. Workspace attributes (`DataStoreStatus`, `SlimeLook`, `SlimeRain`, rain times), Remotes count, `ScriptContext.Error` and LogService errors.

There is also the older `smoke.luau` (a shorter PASS/FAIL variant: module sweep + 20 s spawner run).

What `smoke.luau` does:
1. `require`s every ModuleScript under Server / Shared / Visuals and reports load errors. This catches today's SlimeMesh crash.
2. Checks Map / Plots / HubSpawn, every TextLabel and every Sign part.
3. Runs `WorldView.setup` + `WorldProps.place` + a `World` driven by `GameLoop.step` / `WorldView.reconcile` for 20 s, then counts `workspace.WildSlimes`.

It never touches DataService. It returns a report table.

What `run.sh` does:
- Posts the task and polls the returned `path` every 3 s.
- Prints the logs (`GET <path>/logs`) and `output`.
- Exit codes: 0 = ok, 1 = checks failed, 2 = task failed or HTTP error.
- The key is read from `ROBLOX_OPEN_CLOUD_API_KEY` and reaches curl on stdin (`-H @-`): never in argv, never on disk, never echoed.

Raw API, for reference (the Luau Execution scope this uses is `universe.place.luau-execution-session:write` for universe 10770917350):
- Create: `POST https://apis.roblox.com/cloud/v2/universes/{u}/places/{p}[/versions/{v}]/luau-execution-session-tasks` with body `{"script": "...", "timeout": "300s"}`.
- Poll: `GET https://apis.roblox.com/cloud/v2/{path}` until `state` is `COMPLETE`, `FAILED` or `CANCELLED`.
- Read: `output.results` for the return values (exact shape not documented), and `GET {path}/logs`.

*[restore note] Superseded: the key got this scope on 2026-10-15 around 09:20, and v10/v11 tasks have run since then (see the dated sections and §4). The text below is kept as the reference for granting the scope to a new key.*

**Status before 2026-10-15 09:20: 403.** The key got
`PERMISSION_DENIED: required scope universe.place.luau-execution-session:10770917350:write is missing`.

**What Merijn needed to do** (the scope is `universe.place.luau-execution-session:write`; Get task and logs accept read or write):
1. Go to https://create.roblox.com/dashboard/credentials and open the **API Keys** tab.
2. Open the existing publish key and choose **Edit**. Or create a separate key with **Create API Key**, which is better for least privilege.
3. Under **Access Permissions**, open **Select API System** and add **luau-execution-sessions**. The label may read "Luau Execution Sessions".
4. Pick the experience **Steal a Slime (10770917350)**.
5. Under **Operations**, choose **Write**.
6. Under **Security → Accepted IP Addresses**, either add the box's egress IP or `0.0.0.0/0` for any IP.
7. Under **Expiration**, set a date or leave none. Keys unused for 60 days auto-expire.
8. Click **Save** (**Save & Generate key** for a new key).

Editing an existing key should not change its secret (from experience; the docs don't say). A new key has to be put into `ROBLOX_OPEN_CLOUD_API_KEY` on the box.

Caveats:
- `output` returns only what the script `return`s.
- `print` / `warn` go to logs.
- Errors from LogService history are not included automatically.
- Some users report occasional "WAF Blocked Request" responses on create; retry those.

## 3. Studio or Player on Linux (not viable here)

- **Roblox Player:** blocked by the Hyperion anticheat. Wine has been unsupported since 2023.
- **Sober:** runs the Android client via Flatpak. It needs a Roblox login and a GPU.
- **Vinegar:** runs Studio under Wine. It needs a Roblox login and a GUI/GPU.
- The box has no account, so none of these were attempted (per our constraints).
- *[restore note] Update, 2026-10-15 09:40 (Archer, from `/workspace/team/worklist.md`):* Vinegar and Sober were then installed as flatpaks. Both stopped at a first-run GUI dialog before any login: Vinegar at Configure, Sober at its EULA/ban-risk "Continue". The box has no GPU (llvmpipe only). The logs in `/workspace/roblox/live-testing/linux/` show the same picture:
  - `vinegar.log`: `DRM Devices cards=[]`, MESA "Could not get DRI3 device", and no D-Bus session bus.
  - `sober.log` / `sober2.log`: the same DRI3 warning, no session bus, and `fuse init failed` for the document portal.
  - Screenshots: `vinegar-welcome.png`, `sober-welcome.png`.
  - TODO: lost in reset. Archer's original detail text for this section.
- **Cloud CI screenshots:** there is no official Roblox screenshot API.
  - The thumbnails API (`thumbnails.roblox.com/v1/places/gameicons`, `/v1/games/multiget/thumbnails`) only returns uploaded or auto-generated images.
  - Luau Execution can't render.
  - There is no web player.
- **The only route to real screenshots with an account:** Studio, then the built-in **Studio MCP server** (`screen_capture`, `execute_luau`, `start_stop_play`, `get_console_output`), enabled under Assistant → Manage MCP Servers.
  - It's documented for Windows and macOS only. Under Vinegar on Linux it is untested.
  - `run-in-roblox` also needs a local Studio.

## Recommendation

- Run the **headless boot test** (`lune run tests`, which includes LiveBoot) **before every publish**. It would have stopped v9 and v10.
- Use the **static render** for layout and geometry checks (cheap, about 25 s).
- Run **Luau Execution** `live.luau` after each publish for runtime facts on the real engine: module loads, slimes spawned, sign text, physics/volcano state. A `boot.shim = true` or any `requireErrors` means the published server is dead.
- **Merijn's eyes** for final visuals (effects, lighting, client UI). Archer's checklist is in `/workspace/roblox/live-testing-notes-for-archer.md`.

## Luau Execution run on v10 (09:20)

The task ran once the key scope was fixed. Raw result: `/workspace/roblox/live-testing/runtime-v10.json`. Script: `rt.luau`.

- Task `347c2f7b-…` on place version 10: state **COMPLETE**, `error: null`. It ran 07:20:45Z–07:21:01Z UTC (09:20 local), about 16 s including `task.wait(15)`.
- **0 `Slime_*` models** in `workspace`.
- **All 8 plots (Plot_1..Plot_8) have a Sign, but none has any text.** Every `texts` is `[]`, so there are no TextLabel/TextButton descendants.
- LogService: **0 errors, 0 warnings**.
- `workspace` children: **HubSpawn, Map, Plots** only, plus the engine's Terrain/Camera. There's no WildSlimes folder and no runtime-created props.
- `ServerScriptService` has 1 child: the `Server` Script (`src/server/init.server.luau`), with the server ModuleScripts as its children.

**Do the place's own Scripts run in a task? No.** From the `LuauExecutionSessionTask` resource docs (https://create.roblox.com/docs/cloud/reference/features/luau-execution, raw markdown at https://create.roblox.com/docs/en-us/cloud/reference/features/luau-execution.md, checked 2026-10-15):
> "In a task, physics simulation does not run. Server and local scripts within the place also do not automatically run. The script may access and update the data model of the place, including invoking any module scripts. However, data model changes are local to the task and cannot be persisted."

What that means:
- The v10 result above is the **static place as published**. 0 slimes and empty signs are expected, not a bug: the Server bootstrap never ran.
- Clean logs only say that loading the place produced no errors. They say nothing about the game code.
- So Phoenix must bootstrap the game inside the task script. That means `require` the Server/Shared modules and call their init/start functions or `GameLoop.step` directly, as `tools/livetest/cloud/smoke.luau` does. Then assert on slimes and signs.
- `ServerScriptService.Server` is a `Script`, so it can't be `require`d. Its child ModuleScripts can. Keep `init.server.luau` thin, with startup in a ModuleScript (e.g. a `Boot.start()`), so the live server and the task call the same entry point.
- Physics doesn't run either, so anything that depends on falling or touching won't happen in a task.

## Live boot run on v10 (09:31, `live.luau`)

Result: `steal-a-slime-b0/tools/livetest/results/boot-20261015-093107.json`. Task `f2fd7537-…` on universe 10770917350, place 135787188192378, version 10. COMPLETE, 74 s. Earlier `live-20261015-092456.json` is the failed "re-enable the Script" attempt (proves it doesn't start).

- **Boot as published fails.** `Shared is not a valid member of ServerScriptService` at `Server.SlimeMesh` line 24, then `WorldView` line 37 fails. In a real server that kills `init.server.luau` at `require(script.WorldView)`. Result: no Remotes, no WildSlimes folder, no props, no spawner. This is Merijn's **"no slimes"** (fixed at HEAD 15e3fef, not published).
- **With the path shimmed** every boot step succeeds. 0 loop errors, 15 wild slimes after 60 s and 20 after a forced rain, all tagged and anchored on the ground in the 35–62 stud ring (one caught mid-drop from the crater). `SlimeLook = Mesh`, `SlimeRain = true` / `RainActive = true` during rain, 4 Remotes.
- **Signs.** 6 GUI labels in workspace after boot; 0 of them are on the 8 plot Signs (each has 0 labels). Empty labels: only `LeaderboardBoard…Row_1.Rank` and `.Value` (the "No entries yet" placeholder row, cosmetic). This is Merijn's **"empty signs"**: no code in v10 creates text on plot Signs (fixed at HEAD 4eb4dbc, not published). Before boot the whole place has 0 labels.
- **Physics.** 1052 parts, 0 unanchored non-slime parts, 0 below the floor, 0 NaN/huge.
- **Volcano.** One `Map.Volcano` model, 32 parts, all anchored, no duplicates, identical before and after boot, 0 coplanar faces (`zfight`). The server adds no emitters (only one PointLight on the Crater; the one Sparkles after boot is on a mutated slime body, ModelFactory). So the **volcano glitch is not server-side state**. It must be client-side: VisualsClient emitters / CraterGlow pulse / Neon + default Lighting bloom, or the Neon LavaFlow slabs overhanging the faceted cylinders. See the Archer notes. HEAD 100e25b already tones down the particle presets.
- The offline Lune PoC (`lune run tools/livetest/run v10.rbxl`) gives the same picture: FAIL boot error + 0 slimes + 8 blank signs. With `--patch` of the SlimeMesh path: 16 slimes, the same 6 labels / 2 empty / 8 blank signs. On HEAD: 0 blank signs.

## How bots could actually PLAY the game (research, 2026-10-15)

This is web research only: no accounts created, nothing bought. Prices are on-demand list prices as of Oct 2026 from third-party trackers. Check them before spending.

### (a) Cloud Windows GPU VMs

**Prices**
- **Azure NV6ads_A10_v5** (1/6 of an A10): about **$0.73/h** on Windows in East US ($0.454/h Linux). Only one source: https://www.economize.cloud/resources/azure/pricing/virtual-machine/nv6adsv5/, https://www.azurespeed.com/AzureVmPricing/Standard_NV6ads_A10_v5
- **Azure NVv3/NVv4:** retirement was scheduled for 30 Sep 2026, so don't plan on them. https://learn.microsoft.com/en-us/azure/virtual-machines/windows/n-series-driver-setup
- **AWS g4dn.xlarge** (T4): **$0.71/h** on Windows in us-east-1 ($0.526/h Linux). https://calculator.holori.com/aws/ec2/g4dn.xlarge/us-east-1?os=Windows
- **AWS g5.xlarge** (A10G): $1.006/h on Linux. https://calculator.holori.com/aws/ec2/g5.xlarge/us-east-1 . On Windows it's probably about $1.19/h, but that's an estimate; check the AWS calculator.
- **Paperspace (now DigitalOcean):** Windows templates aren't available to accounts created after 1 Jul 2024, and the GRID machines are retired. So it's effectively gone. https://docs.digitalocean.com/release-notes/machines/
- **Shadow PC:** a full Windows cloud PC. Neo about **$37.99/mo**, Power about $54.99/mo, plus "Lite" tiers capped at 120 h/mo. These are third-party figures: https://tech-insider.org/shadow-pc-vs-geforce-now-2026/

**Setup**
1. Create a VM from a Windows Server 2022/2025 or Windows 11 image.
2. Install the vendor GPU driver.
   - Azure: Microsoft's GRID build, license included, via the NVIDIA GPU Driver Extension. https://learn.microsoft.com/en-us/azure/virtual-machines/windows/n-series-driver-setup
   - AWS: GRID or gaming driver from the `ec2-windows-nvidia-drivers` bucket. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/install-nvidia-driver.html
3. Use Amazon DCV or Parsec instead of plain RDP so the GPU actually renders the display. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/nvidia-GRID-driver.html
4. Install the Roblox Player, log in with the alt, and deep-link into the place.

**Hyperion/Byfron and VMs**
- Reported failures:
  - Plain VPSes show **"Virtual machine detected"**. One reply quotes Roblox's help page as requiring a passed-through physical GPU (Jun 2024). https://devforum.roblox.com/t/running-roblox-in-a-vps/3029593
  - The Microsoft Store build used to slip through with software rendering at 1–3 FPS. By Jul 2024 it also closes after about 2 s.
  - Nested Hyper-V was "patched" (Feb 2024). https://devforum.roblox.com/t/how-can-i-run-roblox-on-a-vm/2813168
- Reported successes:
  - Proxmox with GPU passthrough works once a real GPU or display driver is detected (reports Dec 2025 and Aug 2026). https://forum.proxmox.com/threads/roblox-vm-detection-can-be-overcome.164635/
  - Shadow advertises Roblox support. That's a vendor claim: https://shadow.tech/gaming/roblox
- **There's no public report either way for Azure NV or AWS g4dn/g5.** They do expose a real GPU, so they might pass, but that's a guess. Budget a 1 h test (under $1) before relying on them.

### (b) Driving Merijn's own Windows PC

**Launch straight into the place**
- `roblox://placeId=<id>&launchData=<string>` (app) or `https://www.roblox.com/games/start?placeId=<id>` (via browser).
- Other parameters: `accessCode` / `linkCode` (private server), `gameInstanceId` (JobId), `launchData` (≤200 bytes, read with `Player:GetJoinData()`).
- Roblox marks this method **deprecated** in favour of share links, but it is still documented. https://create.roblox.com/docs/production/promotion/deeplinking
- From PowerShell: `Start-Process "roblox://placeId=135787188192378"`. This should work because Windows opens registered URI protocols, but it hasn't been tested here.

**Screenshots**
- PowerShell: `System.Windows.Forms.Screen` bounds plus `Graphics.CopyFromScreen`. https://www.pdq.com/blog/capturing-screenshots-with-powershell-and-net/
- Exclusive fullscreen can come out black, so run Roblox windowed. https://www.codeproject.com/Questions/1183057/answer
- Python **mss** is fast and has no dependencies. Import it before pyautogui to avoid DPI scaling issues. https://pypi.org/project/mss/

**Input**
- `SendKeys` only reaches the focused app and has timing problems. https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.sendkeys
- **pyautogui** sends virtual-key codes, which DirectX games often ignore.
- **pydirectinput** sends `SendInput` scan codes, which games do see. https://github.com/learncodebygaming/pydirectinput
  - There's a more complete fork, `pydirectinput-rgx`: https://pypi.org/project/pydirectinput-rgx

**What must stay running or approved**
- The Roblox client, logged in to the test alt and kept in focus.
- An **unlocked, visible desktop**. Screenshots come out black or blank on a locked screen, screensaver, display off, or minimised/disconnected RDP. https://qatools.knowledgebase.qt.io/squish/troubleshoot/lack-of-display-on-windows/
  - Input injection fails with "Access is denied" in inactive RDP sessions. https://community.ibm.com/community/user/discussion/send-keys-returns-access-is-denied-when-rdp-session-is-inactive-ibm-rpa
- The agent process, running at the **same or higher integrity level** as Roblox. UIPI blocks `SendInput` to higher-integrity apps without reporting an error. https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput
- Claude's own computer use is another option. It's a research preview in Claude Desktop on Windows/macOS, Pro/Max plans only, needs per-app approval each session, and is slow. https://code.claude.com/docs/en/desktop, https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork

**Better, official route on the same PC: Roblox Studio's built-in MCP server**
- Enable it under Assistant → … → Manage MCP Servers → "Enable Studio as MCP server".
- Claude Code and Claude Desktop can quick-connect. On Windows the command is `cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat`.
- Tools: `start_stop_play`, `screen_capture`, `get_console_output`, `execute_luau`, `character_navigation`, `user_keyboard_input`, `user_mouse_input`, `get_studio_state`, `list_roblox_studios`. https://create.roblox.com/docs/studio/mcp
- This plays the real game (server + client Scripts, physics, UI) inside Studio. There's no anticheat, no OS input hacks and no live-client ToS question.
- Known gap: during Play, `screen_capture` leaves out BillboardGuis, default ProximityPrompts and the top bar. https://devforum.roblox.com/t/mcp-screencapture-omits-billboardgui-default-proximityprompt-and-roblox-top-bar-ui-during-play-mode/4736693
  - That matters here, because the plot signs may be BillboardGuis.
- Studio's multi-client test simulates up to 8 clients. https://create.roblox.com/docs/studio/testing-modes

### (c) Cloud gaming

According to the cloudbase.gg tracker (https://cloudbase.gg/g/roblox):
- **GeForce NOW:** Roblox is not on it. Users keep asking: https://www.nvidia.com/en-us/geforce/forums/gfn-game-requests/44/374156/add-roblox-to-geforce-now/
  - Its terms forbid "botting or farming". https://www.nvidia.com/en-us/geforce-now/terms-of-use/
- **Xbox Cloud Gaming, Amazon Luna, PlayStation cloud:** not available.
- **now.gg:** its Roblox page no longer shows Roblox. Reports say it was removed in 2025, but there's no official statement. https://now.gg/apps/roblox-corporation/5349/roblox.html, https://aitrendytools.com/tool/now-gg-roblox-cloud-gaming-guide-2025-play-without-downloads
- **Boosteroid:** Roblox is available on the Ultra plans, about €9–15/mo. https://boosteroid.com/blog/2024/12/30/our-top-5-games-on-boosteroid-a-curated-list-by-cloudbase-gg/, https://shattered.io/boosteroid-vs-geforce-now/
  - It's a locked launcher, so deep-linking to a placeId is unlikely, and its automation terms weren't found.
- **Shadow:** see (a). It's a full desktop, so everything in (b) applies.

### Risks

> Superseded 2026-10-15 by `/workspace/guides/roblox-ai-testing-rules.md` (verified ToU/Community Standards quotes and verdicts per option).

- **Roblox Community Standards** prohibit:
  - "Using bots or other automation that is programmed to run disruptive tasks"
  - "Using or sharing exploits to help yourself or others gain an unfair advantage"
  - "Creating or using an account to avoid enforcement action"

  Source: https://about.roblox.com/community-standards. The wording targets *disruptive* automation, so a bot quietly testing your own private place is a grey area, not explicitly allowed.
- The **Terms of Use** update bans access via "robots, crawlers, scrapers or other automated data gathering and extraction tools" for AI/ML purposes. https://en.help.roblox.com/hc/en-us/articles/14663412502676-Roblox-is-Updating-our-Terms-of-Use . We couldn't read the full ToS (403).
- **Bot-account enforcement (Aug 2026):** Roblox says bot accounts break the Community Standards and ToS. It detects them by "activity patterns that don't match how real people use the platform", and lists no developer exemption. https://devforum.roblox.com/t/actioning-against-bot-accounts-on-roblox/4820656
  - **This is the main ban risk for any live-client bot.**
- **Hyperion and input macros:** no official word. Reports conflict: it targets memory tampering per https://ahkvault.com/blog/roblox-macro-safety-ban-risk-guide, but AHK gets flagged per https://www.vintageisthenewold.com/faq/does-roblox-ban-autohotkey .
- **Mitigations:**
  - Use a **dedicated alt** (one, not many). Bulk-created alts get mass-deleted. Alts linked to a banned account can be banned too: https://devforum.roblox.com/t/are-alt-accounts-against-roblox-tos/1877136, https://devforum.roblox.com/t/unbans-for-individuals-flagged-as-alternative-accounts/3132785
  - **Never** use Merijn's main or the group owner account.
  - **Never** inject or read client memory.
  - Keep the test place **private** (only the creator and Edit/Playtest users can join): https://create.roblox.com/docs/production/publishing/publish-experiences-and-places
  - Keep sessions short and human-paced.

### Ranked recommendation

| Rank | Option | Cost | Effort | Risk |
|---|---|---|---|---|
| 1 | Studio MCP server on Merijn's PC (Claude Code drives `start_stop_play` / input / `screen_capture` / `execute_luau`) | free | low (Studio toggle + `claude mcp add`) | very low: official tool, no live client; BillboardGuis missing from captures |
| 2 | Real Roblox client on Merijn's PC via `roblox://placeId=` + mss + pydirectinput, dedicated alt, private place | free | medium (script + unlocked desktop) | medium: bot-account sweep / grey-area ToS on the alt |
| 3 | Shadow PC with (2)'s setup | ≈$38–55/mo | medium | medium: same ToS risk; Roblox support claimed by the vendor only |
| 4 | Azure NV6ads_A10_v5 / AWS g4dn.xlarge Windows | ≈$0.71–0.73/h (+storage) | high (drivers, DCV/Parsec) | high: Hyperion VM check unverified on cloud GPUs |
| 5 | Boosteroid | ≈€9–15/mo | high (no placeId deep link) | high: unknown automation terms |
| 6 | GeForce NOW / Xbox Cloud / now.gg | n/a | n/a | not available |

Keep Luau Execution (with a bootstrap in the task script, see above) as the headless CI gate. #1 gives eyes and hands. #2 only if something has to be checked in the live client.

### Steps for Merijn (#1: Studio MCP)

1. Update Roblox Studio on the Windows PC and open the Steal a Slime place. Use the published place or a private copy, never a public one.
2. Open the Assistant panel → **…** → **Manage MCP Servers** → turn on **Enable Studio as MCP server**. https://create.roblox.com/docs/studio/mcp
3. Install Claude Code on the PC and register the server. Use the quick-connect button, or run `claude mcp add roblox-studio -- cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat`.
4. Check it: in Claude Code, `list_roblox_studios` should show the open place.
5. Leave Studio open with the place loaded and the PC awake. Studio may prompt you to approve the connection or each action; say yes.
6. Hand Phoenix's playtest script to Claude Code on the PC, from the repo checkout. It runs `start_stop_play` (start), waits, `get_console_output`, `screen_capture`, walks to a plot with `character_navigation`, presses keys with `user_keyboard_input`, inspects state with `execute_luau`, then `start_stop_play` (stop).
7. Copy the screenshots and console logs back into `/workspace/roblox/live-testing/` for Phoenix and Archer. Check BillboardGui text such as the signs through `execute_luau`, because `screen_capture` leaves BillboardGuis out.

## 4. 24/7 CI: Luau Execution playtest on cron (2026-10-15)

PoC by Archer-overflow (cc opus), in `/workspace/roblox/live-testing/ci/`: `run.py`, `playtest.luau`, `probe.luau`, `GUIDE-SECTION.md` (the full write-up), and `result-*.json`. Nothing was published, uploaded or bought.

### What it does
`run.py` is stdlib-only Python. It posts `playtest.luau` as a Luau Execution task against the latest **published** version of place 135787188192378, or `--version N`. It never uploads or publishes. It then polls the task and writes `result-<UTC ts>.json` with `ok`, `placeVersion`, `loopSeconds`, `assertions[]`, logs and the report. The key comes from `ROBLOX_OPEN_CLOUD_API_KEY` only and is sent only as the `x-api-key` header.

```bash
cd /workspace/roblox/live-testing/ci
python3 run.py                   # latest published version; exit 0 pass / 1 assertion fail / 2 task or HTTP error
python3 run.py --version 12      # a specific (e.g. Saved, gate.sh-uploaded) version
python3 run.py --shim            # diagnostic: patches the SlimeMesh `Shared` path in memory; never counts as a pass
python3 run.py probe.luau --out probe-result.json   # capability probe
```

The task script:
1. Copies `ServerScriptService.Server`'s source into a ModuleScript (`ModuleScript.Source` is writable from a task) and requires it with `DataStoreMode=Memory`, so the **real** boot and Heartbeat loop run.
2. Claims a plot for a fake player (`Sessions.join`, id -1001 "CI Bot") and puts an R15 rig from `CreateHumanoidModelFromDescription` on the plot spawn.
3. Waits 40 s, then asserts:
   - the server boots;
   - `Slime_*` count > 0;
   - the claimed sign shows "CI Bot", and all 8 signs have text;
   - grab → HomeZone → deposit puts a `Slime_*` on the plot;
   - there are no LogService or ScriptContext errors.

The whole loop takes about 45 s.

Probe facts (v11, `probe-result.json`):
- `loadstring` is unavailable.
- Heartbeat runs at 60 Hz and `task.wait` works.
- **No physics:** `RunService.Stepped` never fires, unanchored parts don't move, and `RunService:Run()` is refused ("lacking capability Plugin").
- A task has no players, and a real `Player` can't be created.

Limits:
- 5 min per task, 10 open tasks per place, 5 creates/min per key owner, 4 MB output, and the last 450 KB of logs.
- No clients, UI, replication or rendering.
- The fake player isn't in `Players`, so per-player server paths don't run for it.
- Only published or saved versions can be tested. Before a publish, use `gate.sh` (Saved upload) and then `run.py --version N`.

### Cron on this box
- `crontab.txt`: `7,37 * * * * /workspace/roblox/live-testing/ci/cron.sh >/dev/null 2>&1`, i.e. every hour at :07 and :37. (GUIDE-SECTION.md suggests `*/30`; the installed schedule is :07/:37.)
- `cron.sh` (no LLM involved):
  - Takes a `flock` on `runs/.lock`, sources `~/.config/roblox-ci.env` if it exists (never print it), and runs `timeout 300 python3 run.py`.
  - Writes `runs/run-<ts>.log` and moves the new result to `runs/result-<ts>.json`.
  - On exit 0 it writes `runs/LATEST-PASS` and removes `LATEST-FAIL`. Otherwise it writes `runs/LATEST-FAIL` (ts, rc, log and result paths) and removes `LATEST-PASS`.
  - It appends `<ts> rc=<n>` to `runs/history.txt` and deletes logs and results older than 7 days.
- **After every reboot, re-run `install-cron.sh`.** The box's root fs is reset on reboot, which wipes the cron package and its spool. `/workspace` and `/home` persist. The script:
  1. Installs `cron` with apt if it's missing.
  2. Starts `cron`.
  3. Loads `crontab.txt` and prints `crontab -l`.
  4. Recreates the `/guides -> /workspace/guides` symlink.
  ```bash
  /workspace/roblox/live-testing/ci/install-cron.sh
  cat /workspace/roblox/live-testing/ci/runs/LATEST-FAIL 2>/dev/null || cat /workspace/roblox/live-testing/ci/runs/LATEST-PASS
  ```
- Status at restore time (2026-10-15 ~10:20): the cron was installed and running. The first scheduled run, `20261015-101608`, ended with `rc=1` (`LATEST-FAIL`). The live server still dies at boot (`SlimeMesh`: "Shared is not a valid member of ServerScriptService"), so there are 0 slimes, no plot claim and 8 blank signs.

### Results on v11 (from GUIDE-SECTION.md)
- **Plain run (the gate):** `result-20261015-080943.json`, exit 1. Every failure is a real bug: the boot crash, fixed in 15e3fef, which is unpublished.
- **Shimmed run (diagnostic only):** `result-20261015-081051.json`.
  - Boot, slimes (10 wild after 40 s), grab→deposit and 0 errors all pass.
  - Both sign checks fail, because v11 has no PlotSigns. That fix, 4eb4dbc, is also unpublished.
- The unversioned endpoint resolved to **v11**, but `publish-response.json` still says 10. Who published v11: TODO, open question from GUIDE-SECTION.md.

### Ranking of 24/7 options (GUIDE-SECTION.md)
| # | Option | Cost | Checks |
|---|---|---|---|
| 1 | Open Cloud Luau Execution (`ci/run.py`) on cron here or a GitHub Actions `ubuntu-latest` schedule | $0 | Server gameplay; no physics, clients or visuals |
| 2 | Lune fake runtime (`tools/livetest/run`, `tests/LiveBoot.spec`) as a pre-publish gate | $0, ~1 s | Boot and logic; can drift from Roblox |
| 3 | Blender render pipeline (`render*.py`) | $0 | Static geometry and colours only |
| 4 | Windows VPS + alt account: Studio `--task RunScript` + `StudioTestService:ExecuteMultiplayerTestAsync` + MCP `screen_capture` | est. ~$40–80/mo CPU-only (unverified), ~$330–530/mo GPU | Full gameplay and visuals; login expiry and auto-update risk |
| 5 | Merijn's PC + Studio MCP | $0 | Full, but not 24/7 |
| 6 | GitHub Actions Windows runner + `.ROBLOSECURITY` cookie | – | **Don't** (ToS/account risk) |

`run-in-roblox` is dead (last release 2020), and TestEZ was archived in 2024 (use Jest-Lua via rocale-cli if needed).

## 5. Graphics

Strategy, licences, lighting values and the ranked plan are in **`/workspace/roblox/graphics-strategy.md`**. Asset sourcing and mesh upload are in `/guides/roblox-assets.md`.

Render tooling in `/workspace/roblox/live-testing/` (a Blender approximation, not the Roblox renderer):
- `render_graphics.py`: before/after renders using the palette from the strategy doc. Run `blender -b --python render_graphics.py -- v10.json renders [before|after|both]`. Env: `SAMPLES`, `RES_PCT`, `CAM`.
- `export_lighting.luau` + `render_quickwins.py`: renders driven by place data, with no hard-coded palette.
  ```bash
  lune run export_lighting.luau place.rbxl out.lighting.json
  blender -b --factory-startup --python render_quickwins.py -- parts.json lighting.json out.png
  ```
- Outputs: `renders/graphics_{before,after}.png`, `renders/quickwins_{before,after}.png`, `renders/v10-fix/`.
- Quick wins 1–3 (Future lighting, post effects, palette) were committed as `21a48b5` in steal-a-slime-b0 (per `cc5.log`), not pushed or published at that point. After any publish, check in Studio that `Lighting.Technology` is still Future.

## 6. Release gate: Saved upload → live check, never publish (2026-10-15)

The flow every release candidate goes through. Nothing in it publishes.

### Prerequisites
- **Key scope.** Luau Execution needs `universe.place.luau-execution-session:write` on universe 10770917350 (granted 2026-10-15; see §2 for how to add it). Without it, task creation returns 403 `PERMISSION_DENIED: required scope universe.place.luau-execution-session:10770917350:write is missing`. Uploads need the separate `universe-places:write` scope the publish key already had.
- `ROBLOX_OPEN_CLOUD_API_KEY` in the environment. Never echo, print or log it. All our tools send it as a header via stdin (curl `-H @-`) or `urllib` only.

### Boot the game yourself
In a Luau Execution task **the place's own Scripts don't run and physics doesn't step**. `ServerScriptService.Server` never starts, and toggling `Enabled` does nothing. A script that only waits and reads `workspace` sees the static place: 0 slimes and blank signs, whatever the code does. So the task script must boot the game itself:
- `ci/playtest.luau` (used by `run.py`) copies `Server.Source` into a ModuleScript (Source is writable in a task), clones Server's children under it, sets `workspace.DataStoreMode = "Memory"` and requires it. The real `init.server.luau` boot and Heartbeat loop then run.
- `tools/livetest/cloud/live.luau` (used by `gate.sh`) requires the Server modules and replays the boot steps, then emits `result.gate`.
- DataStores are real in a task, so always force memory mode. Anything that needs physics (falling, Touched) won't happen.

### Steps
```bash
cd /workspace/roblox/steal-a-slime-b0
# 1. local checks (stop on any failure)
lune run src/visuals/tools/build-map.luau && lune run src/visuals/tools/check-map.luau
rojo build -o /tmp/place.rbxl
lune run tests && selene src tests && stylua --check src tests
lune run scripts/check-place /tmp/place.rbxl
# 2. upload as Saved (does NOT go live); note versionNumber N from the JSON response
#    POST https://apis.roblox.com/universes/v1/10770917350/places/135787188192378/versions?versionType=Saved
#    tools/livetest/gate.sh does 1+2+live.luau in one go and stops after the gate (it has no publish step).
# 3. live checks on that exact version
cd /workspace/roblox/live-testing/ci
python3 run.py --version N            # never --shim for a gate; exit 0 pass / 1 assertion fail / 2 task or HTTP error
./release-check.sh N                   # same run, output kept in ci/releases/N-<ts>/{run.log,result.json}
```
`run.py` options: `[script.luau]` (default `playtest.luau`), `--version N` (default: latest *published*), `--timeout`, `--out`, and `--shim` (patches the old v10 SlimeMesh path in memory; diagnostic only, always `ok=false`). It writes `ci/result-<UTC ts>.json` with `ok`, `placeVersion`, `assertions[]`, logs and the report. Check that `placeVersion` equals N.

### Saved vs Published
- `versionType=Saved` creates a new place version that players don't get. Luau Execution can target it via `/versions/N/`, so you can test the exact bytes you'd ship.
- `versionType=Published` makes it live for new servers. **We never do this on our own: Merijn OKs every live publish.** Open Cloud can't promote a Saved version, so publishing means uploading the same file again with `versionType=Published`, after Merijn says yes.
- Studio can also create versions (v11 was a Studio save of v10, not ours). Fingerprint a version before trusting it (see memory notes / `probe.luau`).

### 409 "Server is busy"
On 2026-10-15 every Saved upload from ~10:14 CEST on got:
`HTTP 409 {"code":"Conflict","message":"Save failed. Server is busy and unable to process your upload request. Please try again in a couple minutes."}`
Luau Execution tasks kept working meanwhile. Likely cause: a Studio session holding the cloud place open (Team Create / an unsaved edit session). What to do:
- Back off and retry: 5, 10, 15, 15, 15 min (~1 h). Short retries (seconds) don't help.
- If it's still 409 after that, ask Merijn to close Studio on the cloud place, then retry.
- `gate.sh` and `run.py` retry 409/429/5xx themselves with short backoff; for a long outage wrap the upload in the schedule above.

### v10 baseline (why this gate exists)
`tools/livetest/results/baseline-v10-20261015-093546.json` = `live.luau` on published v10. The gate verdict was `ok: false`:
- **0 slimes** (the 20 seen only appeared with the shim, so they don't count);
- **8/8 plot signs empty** (Plot_1..Plot_8);
- **4 boot errors**: `require Server.SlimeMesh` and `require Server.WorldView` ("Requested module experienced an error while loading"), plus script errors `SlimeMesh: Shared is not a valid member of ServerScriptService` and `WorldView: Requested module experienced an error while loading`.

That matches Merijn's report (no slimes, empty signs). Fixed in 15e3fef (SlimeMesh path) and 4eb4dbc (PlotSigns); `tests/RequirePaths.spec` and `tests/UniqueNames.spec` (duplicate sibling names, e.g. the PromptHide LocalScript/ModuleScript clash fixed in 1a7e818) guard the built place locally.


### v12 live results (15 Oct 2026, 11:17 CEST)
- **Publish:** commit da0aa1b published as live **version 12** via Open Cloud `versionType=Published`. HTTP 200 on the first try once Merijn had closed Studio, which confirms the earlier 409s were a Studio lock.
- **Check:** `python3 run.py --version 12` (no `--shim`) was COMPLETE in 44 s with **all 6 checks PASS**: server boots, 10 wild slimes spawned, the claimed plot sign shows the owner, 8/8 signs filled, grab→deposit works, 0 LogService/ScriptContext errors. Result: `/workspace/roblox/live-testing/ci/result-20261015-091738.json`.
- **Compared with the v10 baseline:** 0 → 10 slimes, 8/8 empty → 8/8 filled signs, 4 → 0 boot errors.
- **Open:** the plot-1 sign text in the result shows the owner text twice (`CI Bot's Plot | ... | CI Bot's Plot | ...`). The checker is probably joining the front and back labels. Check it visually.
