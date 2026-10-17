# Roblox usability playtest: scripted playthrough + funnel comparison

Date: 2026-10-15. Status: draft. Merijn decides the open items.

Two halves:

1. **Before release:** a scripted playthrough in Studio that drives the client with VirtualInput and saves one frame per step.
2. **After release:** compare the funnel against the previous version.

Builds on: Studio MCP playtest and the visual/client gate in [roblox-release-process.md](roblox-release-process.md); cloud stand-in session in [roblox-live-testing.md](roblox-live-testing.md) §4; screenshot tiers in [roblox-screenshots.md](roblox-screenshots.md); funnel sources in [roblox-planning.md](roblox-planning.md). Allowed routes: [roblox-ai-testing-rules.md](roblox-ai-testing-rules.md) (Studio = allowed; driving the real client on the live platform = don't).

## 1. VirtualInput playthrough, a frame per step

Runs in **Studio on Merijn's PC** (play mode, local place file, memory store). Not on the live platform, not with alt accounts.

Script = a list of steps. Each step: one input, a wait for a state condition, one frame, one assertion.

```lua
-- playthrough.luau (sketch; runs in Studio play mode, client side)
local STEPS = {
	{ id = "01-spawn",       act = nil,                         waitFor = "SlimeUI visible" },
	{ id = "02-tutorial",    act = { tap = "Tutorial/Hide" },   waitFor = "tutorial hidden" },
	{ id = "03-open-shop",   act = { tap = "Nav/Shop" },        waitFor = "Panel.Shop visible" },
	{ id = "04-buy-lock",    act = { tap = "Shop/Lock/Buy" },   waitFor = "State.lockUntil > now" },
	{ id = "05-catch-slime", act = { walkTo = "WildSlimes/1" }, waitFor = "carrying" },
	{ id = "06-drop-home",   act = { walkTo = "MyPlot" },       waitFor = "slime on pad" },
}
-- for each step: do act via VirtualInputManager (tap at the element's AbsolutePosition
-- centre / key presses), wait with a timeout, capture a frame "<id>-<W>x<H>.png",
-- log { id, ok, ms, error } to results.json.
```

- Taps go to the **centre of the element's AbsolutePosition/AbsoluteSize**, so a tap that misses means a real player would miss too (a blocked or off-screen button fails the step).
- Run at the release-process sizes: 1920x1080, 1366x768, 1024x768, 844x390 (device emulator for the phone).
- Record time per step: a step that needs a long wait is a usability finding even when it passes.
- Memory store only: `DataStoreMode = "Memory"`; cash/time shortcuts only through `TestHooks` (guarded).
- Output: `/workspace/roblox/usability/v<N>-playthrough/` (frames + `results.json`), linked in the PR.

**Caveats:**

- **RunScript may need a small plugin for StudioTestService / VirtualInput.** `VirtualInputManager` and starting play mode through `StudioTestService` are plugin-level APIs; a plain script passed to Studio's `RunScript` task may not be allowed to call them. Plan for a tiny local plugin (not published, installed on Merijn's PC only) that starts the test, runs `playthrough.luau` on the client, and ends the test. Verify on Merijn's PC before relying on it.
- **Confirm frame capture under CLI Studio** (same open question as [roblox-screenshots.md](roblox-screenshots.md) tier 2). If frames can't be saved unattended, fall back to the Studio MCP route with someone at the PC.
- Use `--localPlaceFile` + `--quitAfterExecution` so Studio never holds a lock on the cloud place (409 on upload).
- Pre-check on the bot box first (free): `rhr hitmap <story or place> --at X,Y` tells which element a tap at a pixel hits, so a step's target can be validated before Studio runs.

## 2. Funnel comparison after release

The playthrough proves a path *can* be done. Players show whether they *do* it.

1. Funnel steps are `AnalyticsService` funnel events (tutorial steps, first catch, first sale, first rebirth). Keep step names stable across versions or the comparison breaks.
2. Read Creator Dashboard → Analytics → Funnels for the new version and the previous one over the same length of time (e.g. 48 h after each release, same weekdays if possible).
3. Compare **conversion per step**, not totals. Flag any step that drops more than a few points; tie it to the playthrough frame of that step.
4. Write the result into the release note to SuperBottie and feed it to planning ([roblox-planning.md](roblox-planning.md), Gojo).
5. Small player counts are noisy: say how many players each number is based on.

## Checklist (per release candidate)

- [ ] Steps updated for any new UI in this release
- [ ] Playthrough green at all 4 sizes, frames attached
- [ ] Slow steps (time) listed in the PR
- [ ] After release: funnel comparison posted with player counts
