# Roblox screenshots: three tiers

Date: 2026-10-15. Status: draft. Merijn decides the open items.

Until now screenshots were spread over [roblox-live-testing.md](roblox-live-testing.md) §1 (Blender static render), [roblox-critical-review.md](roblox-critical-review.md) (before/after per device) and the Studio MCP screenshot gate in [roblox-release-process.md](roblox-release-process.md). This guide puts them in three tiers by cost and trust.

| Tier | When | Tool | Where it runs | Trust |
|---|---|---|---|---|
| 1 | Every commit | `rhr ui` / `rhr scene` | Bot server (this Linux box) | Approximation |
| 2 | Once per release candidate | Unattended Studio CLI run | Merijn's Windows/Mac PC (Studio is not on Linux) | Real engine |
| 3 | After release | Real players | Live | Final judge |

Related: tests in [roblox-automated-tests.md](roblox-automated-tests.md), scripted playthroughs in [roblox-usability-playtest.md](roblox-usability-playtest.md), allowed automation in [roblox-ai-testing-rules.md](roblox-ai-testing-rules.md).

## Tier 1: rhr on the bot server, every commit

No Studio, no login, no network needed once rhr has its tools cached. Install and pin: `/workspace/roblox/rhr-first-run.md`.

```sh
rojo build -o /tmp/build.rbxlx
# UI (needs stories for code-built UI like SlimeUI)
rhr ui src/ui/Hud.story.luau --device phone --out shots/hud-phone.png --json
rhr ui /tmp/build.rbxlx --only StarterGui/Shop --fit --max-size 800 --out shots/shop.png
# 3D world, several sides in one build
rhr scene /tmp/build.rbxlx --views iso,front,top --max-size 800 --out shots/world.png --json
# world + in-world UI + screen UI together
rhr preview /tmp/build.rbxlx --view iso --out shots/preview.png --json
# did a change move geometry or only colours?
rhr compare before.png after.png
```

- Sizes: use the same GATE set as LayoutAssert (390x844, 844x390, 1024x768, 1366x768, 1920x1080) via `--viewport WxH`, plus `--device phone|tablet|console` for notches and touch controls.
- Always read the `--json` report: `missingAssets`, `fallbacks` (meshes drawn as boxes), `experimental`, `notes`. On v23-ui, 148 MeshParts fall back and 6 sky textures are missing without a Studio login or `RHR_ROBLOX_API_KEY`, so tier-1 sky and mesh shots are not evidence.
- Pin `roblox-headless-renderer==1.0.0rc1` and spot-check against tier 2 on each RC (community release candidate).
- Replaces the Blender static render (live-testing §1) for quick looks; keep Blender for geometry renders that need Cycles.

## Tier 2: one unattended Studio CLI run per release candidate

One run per RC on Merijn's PC, against the **exact gate file** (`/workspace/roblox/gate-out/steal-a-slime-<sha>.rbxl`), not against the live place.

Shape of the command (Windows; check the exact flag spelling against the installed Studio build before scripting it):

```bat
RobloxStudioBeta.exe --localPlaceFile C:\gate\steal-a-slime-<sha>.rbxl ^
  --task RunScript --script C:\gate\capture.luau --quitAfterExecution
```

- `--localPlaceFile` opens a local file, so Studio holds **no lock on the cloud place** and the Saved/Published upload never gets HTTP 409 (see release-process "409 Server is busy").
- `--quitAfterExecution` closes Studio when the script ends, so nothing lingers and holds a session.
- `capture.luau` walks the same fixed points as the release-process screenshot gate (spawn, nav, Shop, Goals, Upgrades, Rebirth, Dex, carrying + tutorial, Legendary banner, FREE PLOT, day and night) at 1920x1080, 1366x768, 1024x768 and 844x390, and saves to `usability/v<N>-studio/`.
- Use the memory store: set `DataStoreMode = "Memory"` before booting the server modules.

**Caveats (unverified as of 2026-10-15):**

- **Confirm frame capture under CLI Studio.** We have not proven that an unattended, script-driven Studio session can save rendered frames (Studio MCP `screen_capture` works interactively; CLI mode may have no visible viewport). Do one manual trial run on Merijn's PC and record the result here before making tier 2 part of the gate.
- Driving play mode or input from `RunScript` may need a small local plugin for `StudioTestService` / `VirtualInput` (plugin-level APIs). See [roblox-usability-playtest.md](roblox-usability-playtest.md).
- `screen_capture` leaves out BillboardGuis and prompts; read their text with Luau as well.

## Tier 3: real players

Players on real devices are the final judge: phones with notches, low-end GPUs, odd aspect ratios and languages. Compare funnels before and after a release ([roblox-usability-playtest.md](roblox-usability-playtest.md) "Funnel comparison", [roblox-planning.md](roblox-planning.md)). No bot accounts on the live platform ([roblox-ai-testing-rules.md](roblox-ai-testing-rules.md) option c).

## Storage

- Tier 1: CI artifacts / `shots/` per commit, not committed.
- Tier 2: `/workspace/roblox/usability/v<N>-studio/` and attached to the PR.
- Name files `<point>-<W>x<H>.png` so tiers 1 and 2 can be diffed with `rhr compare`.
