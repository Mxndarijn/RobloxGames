# Roblox automated tests (Lune + rhr layout checks)

Date: 2026-10-15. Status: draft. Games: steal-a-slime (jolt/v23-ui), speed-escape.

This guide covers what runs **on every commit without Studio**: pure-logic tests in Lune and static UI layout checks with `rhr`. It does not repeat:

- Headless boot, Luau Execution, cron CI, Saved gate: [roblox-live-testing.md](roblox-live-testing.md) §0, §2, §4, §6
- Release order and the visual/client gate: [roblox-release-process.md](roblox-release-process.md)
- What automation Roblox allows: [roblox-ai-testing-rules.md](roblox-ai-testing-rules.md)
- Toolchain install: [roblox-toolchain-linux.md](roblox-toolchain-linux.md)
- Screenshots: [roblox-screenshots.md](roblox-screenshots.md). Scripted playthroughs: [roblox-usability-playtest.md](roblox-usability-playtest.md)
- rhr install and first results: `/workspace/roblox/rhr-first-run.md`

## Layers

| Layer | Tool | Catches | Cost |
|---|---|---|---|
| 1. Pure logic | `lune run tests` | Config maths, Format, Layout rects, LayoutAssert rules, TestHooks guard, place safety | ~seconds, every commit |
| 2. Server boot | `lune run tools/livetest/...` | Server crashes at boot, missing props/slimes | ~1 s, every commit ([live-testing §0](roblox-live-testing.md)) |
| 3. Static UI layout | `rhr check --devices all` | Text overflow, off-screen, tiny/blocked buttons, low contrast, per device | ~seconds, every commit |
| 4. Runtime server | Luau Execution on a Saved version | Real-engine module behaviour | per release candidate ([live-testing §2/§6](roblox-live-testing.md)) |
| 5. Client / visual | Studio run, then players | Anything a renderer or a real client shows | per RC / after release |

Layers 1-3 are the subject here.

## 1. Lune: pure logic on every commit

From the game repo root (steal-a-slime: see the repo's `CLAUDE.md`):

```sh
rojo build -o build.rbxlx
lune run tests                                 # unit + LiveBoot + RequirePaths + Members specs
selene src tests && stylua --check src tests
lune run scripts/check-place.luau build.rbxlx  # place safety
scripts/typecheck.sh
```

- Keep logic in pure modules (the `if script then require(script.Parent.X) else require("./X")` pattern) so Lune can run it.
- UI layout is already testable without a renderer: `tests/ui/LayoutAssert.luau` checks `Layout.screen()` rects on every GATE viewport (390x844, 844x390, 1024x768, 1366x768, 1920x1080), each raw and minus `Layout.TOPBAR_INSET` (58). That is the strongest UI check we have today. rhr does **not** replace it; it checks the drawn instances instead of our own model of them.
- Tests run on the memory store only (`DataStoreMode = "Memory"`). Never touch production DataStores.

## 2. rhr check: static layout per device

`rhr` (PyPI `roblox-headless-renderer`) lays out ScreenGuis the way Roblox does and reports findings as JSON (`schema: rhr.check/1`). Exit codes: 0 ok, 1 an `error` finding, 2 nothing to work on / failed.

```sh
rhr check build.rbxlx --devices all --out rhr-check.json          # phone, tablet, console, desktop...
rhr check build.rbxlx --devices all --min-severity info           # also "often intended" patterns
rhr check src/ui/Hud.story.luau --devices phone,tablet            # code-built UI: one story per screen
rhr check build.rbxlx --only StarterGui/Shop --devices all        # one screen that code opens
```

- rhr's default top bar is 58 px, the same as `Layout.TOPBAR_INSET`, so its numbers line up with LayoutAssert's "usable" viewports.
- Fix `error`; weigh `warning`; `info` is advisory. An element we deliberately leave alone gets an `RhrIgnore` string attribute ("all" or check ids, comma-separated). Don't sprinkle it to make CI green.
- For numbers rather than findings: `rhr layout <target> --path <screen>` (rects in px), `rhr hitmap <target> --at X,Y` (who gets the tap).

## 3. rhr check --baseline: only report new problems

Branches should fail on what *they* added, not on old debt:

```sh
# on the base branch (or the last released commit), once:
rhr check build.rbxlx --devices all --out /workspace/roblox/rhr-baseline-<game>.json
# on the branch:
rhr check build.rbxlx --devices all --baseline /workspace/roblox/rhr-baseline-<game>.json --out rhr-new.json
```

- Refresh the baseline when a release ships, not when a branch is red.
- Keep the baseline next to the build it came from (commit sha in the name); a baseline from a different rhr version can make every finding look new.

## Caveats (read before trusting a green run)

- **rhr is a community release candidate.** Pin exactly `roblox-headless-renderer==1.0.0rc1` (installed at `/home/box/.local/share/rhr-venv`, wrapper `~/.local/bin/rhr`). Don't let pip upgrade it silently. **Spot-check** its output against Studio on each RC: compare a few `rhr layout` rects and one `rhr ui` PNG with a Studio screenshot at the same size. Its own docs claim rects within 2 px of Studio; we have not verified that on our game yet.
- **Code-built UI is invisible to rhr unless it has stories.** Steal a Slime builds `SlimeUI` at runtime (`src/ui/init.client.luau`), so `rhr check` on the place finds no ScreenGui and reports 0 findings. That is "nothing checked", not "all good". Each screen needs a `*.story.luau` (UI Labs, Hoarcekat or Flipbook form) that rhr runs in the Rojo project. Stories are marked experimental in rhr 1.0; they run our code, so only run stories from our own branches.
- **rhr does not run game scripts, physics or animation.** Tweens end at their goal, nothing is clicked.
- **Studio frame capture is separate.** rhr pictures are approximations. A real-engine frame needs Studio; **confirm frame capture works under CLI (unattended) Studio** before relying on it in a pipeline. See [roblox-screenshots.md](roblox-screenshots.md) tier 2.
- Missing assets (images, meshes, sky) draw as stand-ins without a Studio login or `RHR_ROBLOX_API_KEY` (Open Cloud user key with `legacy-asset:manage`, from secrets, never committed). Check `missingAssets` / `fallbacks` in the JSON before judging a picture.

## Suggested per-commit order

1. `rojo build`
2. `lune run tests` (+ selene, stylua, check-place, typecheck)
3. Headless boot ([live-testing §0](roblox-live-testing.md))
4. `rhr check --devices all --baseline ...` (stories + place)

Draft wrapper with device presets: `/workspace/roblox/RobloxGames/shared/release/release_check.luau` (not a gate; Phoenix owns the release gate).
