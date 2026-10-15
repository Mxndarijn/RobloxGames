# tools/livetest: let bots test the game without Studio

Full guide: `/guides/roblox-live-testing.md`.

| Command | What it does |
|---|---|
| `lune run tools/livetest/run <place.rbxlx\|.rbxl> [--seconds 60] [--player] [--mesh] [--verbose] [--patch Full.Name find replace]` | Boots the real `ServerScriptService.Server` from the place file in a fake runtime and runs N seconds of server time on a virtual clock. Then it reports PASS/FAIL for: wild slimes spawned, slimes on the ground, props placed, sign text, `[Server]` warnings and script errors. Exits 1 on any FAIL. |
| `lune run tools/livetest/session <place> [--verbose] [--json out.json]` | **Stand-in player session.** Boots the server on the in-memory store, joins one player with a character and plays through `Request` and the world prompts: Speed Coil (WalkSpeed before/after, carrying, respawn), dropped slime lands, lock / buy-pad prompts, full loop new player -> rebirth 6+ with `Server.TestHooks` (grant cash / skip time; refuses unless `DataStoreMode = "Memory"`, CONTRACT.md §8.12). |
| `python3 /workspace/roblox/live-testing/ci/run.py tools/livetest/cloud/session.luau --version N` | Cloud twin of the session (Luau Execution on Saved/published version N, real Roblox raycasts / Humanoids): coil, drop, lock/buy, loop to rebirth 8. Dry run: `lune run tools/livetest/cloud-local <place> tools/livetest/cloud/session.luau --seconds 200`. |
| `lune run tests` | Runs everything, including `tests/LiveBoot.spec.luau`, the same boot as a spec. |
| `lune run tools/livetest/zfight <place> [Workspace.Map] [eps]` | Lists coplanar overlapping Block faces, a static hint for z-fighting. |
| `lune run tools/livetest/cloud-local <place> [cloud/smoke.luau]` | Dry-runs an Open Cloud Luau Execution script locally. Like in the cloud, the place's own Scripts don't start. |
| `OUT=tools/livetest/results/boot-<ts>.json tools/livetest/cloud/run.sh tools/livetest/cloud/live.luau` | **Primary live check.** Luau Execution doesn't start place Scripts or physics, so `live.luau` requires the Server modules and replays the boot plus 60 s of the Heartbeat loop (memory DataStore). It then dumps JSON to `results/`: slimes, empty GUI texts, plot signs, unanchored/below-floor parts, volcano parts, attributes and errors. It shims the v10 SlimeMesh path if needed (`boot.shim`). |
| `ROBLOX_OPEN_CLOUD_API_KEY=… tools/livetest/cloud/run.sh [script] [version]` | Runs `cloud/smoke.luau` in a real Roblox server for the published place, polls it and prints the logs and the JSON report. Needs a key with `luau-execution-session` **write** for universe 10770917350. |

Files:
- `Runtime.luau` is the fake engine: scheduler, signals and API shims.
- `Checks.luau` holds the assertions.
- `cloud/` holds the Luau Execution script and its runner.

Lune can't override built-in Instance members, so the runtime rewrites two patterns in script sources at load time:
- `x.Position` reads become `CFrame.Position`;
- `game:GetService("CollectionService")` becomes a proxy.

Limits: no physics, rendering, replication or client LocalScripts.
