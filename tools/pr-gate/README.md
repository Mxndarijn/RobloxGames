# PR gate (Steal a Slime)

Four fast checks that every PR must pass. They run the same way locally and in CI, in about 20 s on the box.

```sh
tools/pr-gate/run.sh              # all four: per-check PASS/FAIL + seconds, exit 1 if any fail
tools/pr-gate/run.sh layout       # just one or two of them
tools/pr-gate/logic.sh            # each check on its own
tools/pr-gate/layout.sh [--lune-only|--rhr-only]
tools/pr-gate/budget.sh
tools/pr-gate/typecheck.sh        # luau-lsp type check; SKIPs if luau-lsp/rojo are missing
tools/pr-gate/selftest.sh         # proves each check fails on broken input, then passes on the clean tree
```

You need `lune` (`rokit install` in `games/steal-a-slime`) and `python3` (stdlib only). `rhr` is optional.

## The checks

| Check | What it runs | Fails on |
|---|---|---|
| `logic.sh` | `lune run tests` in `games/steal-a-slime`. This is the same step `pr-checks.yml` and `cheap-gates.yml` run, so it covers every `*.spec.luau`. | Any failing spec. |
| `layout.sh` (Lune, always gates) | `lune run tests/ui Layout ScrollLists`. That covers `LayoutAssert.spec`, `Layout.spec`, `ScrollLists.spec` and the new `LayoutGate.spec`, which checks 390x844, 844x390, 1024x768, 1366x768 and 1920x1080. Each viewport is checked raw and minus the 58 px top bar (the ScreenGui's real size), with the nav both collapsed and expanded. | A box off-screen, a nav button covered by an overlay (`navReachable`), overlaps between HUD/nav/cards, aspect-ratio distortion (`notSquashed`: one uniform UIScale, HUD items, nav buttons, the close X and Slap keep their design proportions), touch targets under 44 px, text that doesn't fit, negative sizes. |
| `layout.sh` (rhr render) | `rhr_hud.luau` writes one ScreenGui per viewport and nav state, built from `Layout.screen()` the way `init.client` applies it. `rhr_check.py` then makes one `rhr batch` call (layout + hitmap) and asserts on rhr's own rects. | A HUD/nav button off the viewport or under the top bar. A button that is covered: the centre click lands elsewhere, or a higher-z click-capturing node overlaps it. A squashed button (more than 3 % off its design aspect), or one under 44 px. |
| `budget.sh` | `budget_counts.luau` counts `WorldLayout.build()` with the same rules as `tests/WorldBudget.spec`. `budget_check.py` adds triangle counts read from `shared/modeling-kit/out/<mesh>.fbx` (a binary FBX reader, matching the kit's `stats.json` exactly). | Any limit exceeded (`budgets.json` + the shared `tools/pipeline/pc-watcher/budgets.json` for world triangles). A counted mesh with no FBX. A `WorldLayout.PART_BUDGET` / `BORDER_PART_BUDGET` constant raised above the gate's limit, or `MESH_SLOT_BUDGET` drifting from the shared `mesh_parts.warn`. MeshParts above 500 only warn. |
| `typecheck.sh` | `games/steal-a-slime/scripts/typecheck.sh` (luau-lsp against the Rojo sourcemap), the same as the CI types job. **When luau-lsp or rojo is not on PATH it prints `typecheck: SKIP (luau-lsp/rojo missing; CI types job covers it)` and exits 0**, so the CI `pr-gate` job passes without them. | Type errors in `src/server` and `src/shared`. |

### Budgets

**Single source: `tools/pipeline/pc-watcher/budgets.json`** (next to `watcher.py`, so the Studio watcher finds it through its `data_path` mechanism, repo checkout first and installed app copy as fallback). `watcher.py` (`DEFAULTS` are only the fallback; `selftest.py` keeps them equal), `runtime_budget.sh`/`.py`, `budget.sh`/`budget_check.py` and `tests/RuntimeParts.spec` all read it. Raising runtime parts to 3000 is a one-line JSON change.

| Budget | Limit | Verdict | Where counted | Current |
|---|---|---|---|---|
| Runtime parts (world BaseParts, as `perf_server.luau` counts them) | 3000 | FAIL above; WARN (non-blocking) above 2900. Fixed cap, no ratchet | `runtime_budget.sh` (CI) and Studio perf step | 2203 |
| World triangles | 500,000 | FAIL | **CI only**, `budget.sh`: build mesh slots x `shared/modeling-kit/out/<mesh>.fbx` triangles. Luau in Studio cannot compute triangles, so the Studio report keeps `triangles: null` (unknown, never a failure) | 311,672 |
| Unique meshes (distinct MeshId) | 120 | FAIL | `runtime_budget.sh` and Studio | 93 |
| MeshParts | 500 | SOFT: WARN only, never fails | `runtime_budget.sh`, `budget.sh`, Studio | 391 |

Build-time limits stay in `tools/pr-gate/budgets.json`:

| Budget | Limit | Source |
|---|---|---|
| Parts outside Map.Border | 1400 | THEME.md / CONTRACT §10, `WorldLayout.PART_BUDGET` |
| Map.Border parts | 700 | `WorldLayout.BORDER_PART_BUDGET` |
| Max triangles per mesh | 10,000 | THEME.md: the kit fails a mesh at 10k or more (Roblox's own limit is 20k); slime_fountain is the largest at 6,814 |

To change a limit, edit the right `budgets.json` and explain the change in its `rationale`. For experiments, `PR_GATE_BUDGETS`, `PR_GATE_SHARED_BUDGETS`, `PR_GATE_COUNTS` and `PR_GATE_FBX_DIR` override the inputs. `WorldLayout.MESH_SLOT_BUDGET` (500) mirrors `mesh_parts.warn`; `budget_check.py` fails if they differ. #80's hard per-category mesh split (fence / posts / border / decor / runtime = 400) was folded into these limits.

### Known findings (tolerated, must still occur)

There are real layout bugs on a portrait phone under the top bar (390x786 ScreenGui on a 390x844 screen). Both the Lune and the rhr check find them:

- The tutorial card that shows while carrying overlaps the bottom of the nav, which covers `Nav.Leaders`.
- With the nav expanded on a portrait phone, the banner column overlaps the labelled nav. Lune treats banners as reaching the bottom of the screen.

These are listed in `KNOWN` in `tests/ui/LayoutGate.spec.luau` and `rhr_check.py`. Any *new* problem fails the gate. A KNOWN entry that stops occurring also fails the gate, so fixing the bug forces its removal. The fix belongs in `Layout.screen` (Jolt).

### rhr notes

- Pinned to `roblox-headless-renderer==1.0.0rc1`, the same pin as `cheap-gates.yml` and `/guides/roblox-automated-tests.md`. On the box it is `~/.local/bin/rhr`. `PR_GATE_RHR` picks another binary.
- **When rhr is missing, the step prints `SKIP` (plus a `::notice` in Actions) and the Lune part still gates.** `PR_GATE_REQUIRE_RHR=1` turns a missing rhr into a failure. `PR_GATE_SKIP_RHR=1` skips the step.
- What rhr draws is a *replica* of the HUD and nav geometry, not the live SlimeUI. That UI is code-built and has no `*.story.luau`, so rhr can't draw it from the place. The replica still independently checks how UIScale, the top-bar inset, int-pixel offsets and ZIndex/click capture resolve.
- rhr 1.0.0rc1 ignores a UIScale parented directly to a ScreenGui. Roblox honours it. To work around this, the replica puts the UIScale on a design-size `Root` frame, which gives the same on-screen rects.

## Runtime budget (`runtime_budget.sh`)

The Studio perf step (`pc-watcher` `step_perf`, probe `tools/pipeline/pc-watcher/luau/perf_server.luau`) fails a build when
`runtime_parts > 3000` or `unique_meshes > 120`, and warns above 2900 parts / 500 MeshParts (limits: `budgets.json` above). The CI step runs
the same probe offline, so a PR that Studio would fail fails before merge.

- `runtime_count.luau` rojo-builds the place, boots it in the fake server (`tools/livetest/Runtime.luau`, `createMeshPart` shim that
  sets `MeshId`), steps 15 s at 30 Hz and **executes `perf_server.luau` itself** (`luau.load` with `game`/`workspace` of the fake world), so the
  exclusions (WildSlimes, DrainSplash, `Slimes` folders, player characters) are Studio's by construction.
  `tests/RuntimeParts.spec` uses the same counter and asserts its own breakdown equals it.
- `runtime_budget.luau` prints JSON: `runtime_parts` (Studio-equivalent = offline + 16), `runtime_parts_offline`, `offset`,
  `runtime_parts_transient`, `unique_meshes` (offline + 16), `unique_meshes_offline`, `mesh_slots` (max of build and runtime+offset),
  `mesh_slots_build` (`budget_counts.luau`, i.e. `WorldLayout.build()` + `RUNTIME_SLOT_ALLOWANCE`), `mesh_slots_runtime` (raw MeshParts in the fake runtime).
- `runtime_budget.sh` counts the working tree only (no base worktree and no base-delta rule: the caps are fixed) and hands the JSON
  plus `budgets.json` to `runtime_budget_check.py`.
- Verdict: parts FAIL > 3000, WARN > 2900; unique meshes FAIL > 120; MeshParts WARN > 500. Exit 0 on warn-only. World triangles are `budget.sh`'s.
  Example: `runtime-budget: parts 2203/3000 (warn 2900) unique meshes 93/120 mesh parts 391 (soft 500) -> PASS`, then one `WARN:` line per warning.
  Warnings go to `$GITHUB_STEP_SUMMARY` and `::warning::` annotations under GitHub Actions (`::error::` for fails).
- Runs in ~5 s. Opt-in locally as `run.sh runtime_budget`; CI runs it as its own step after `run.sh`.

**The 16.** The fake runtime builds 16 fewer parts, all MeshParts with 16 distinct MeshIds, than Studio: the same 16 as `WorldLayout.RUNTIME_SLOT_ALLOWANCE`
(`RuntimeCount.STUDIO_OFFSET` and `RuntimeCount.UNIQUE_MESH_OFFSET` read that constant). Most likely `PodiumRigs`: Studio builds a podium R15 rig with
`Players:CreateHumanoidModelFromDescriptionAsync` (15 R15 MeshParts + HumanoidRootPart + one accessory handle) in place of the
1-Part placeholder: +16 parts, +16 MeshParts, +16 unique meshes. The part and MeshPart fit is arithmetic; the unique-mesh fit is measured
against two Studio reports (below) and exact.

| sha | Studio parts / MeshParts / unique | offline raw parts / unique | CI parts / MeshParts / unique |
|---|---|---|---|
| d30d9dc | 2219 / 391 / 93 | 2203 / 77 | 2219 / 391 / 93 |
| 847128a8 | 2233 / 398 / 93 | 2217 / 77 | 2233 / 398 / 93 |
| 851bc9e0 | 2217 / 390 / n/a | 2201 | 2217 / 390 |
| de974c48 | 2217 / 390 / n/a | 2201 | 2217 / 390 |

If Studio's number moves relative to CI (a new Studio-only spawner), recalibrate `RUNTIME_SLOT_ALLOWANCE`.

## Timings (box, load ~9, 2026-10-16)

| Step | Seconds |
|---|---|
| logic | 16.8 |
| layout (Lune 0.3 + rhr ~1.4, incl. generation) | 2.1 |
| budget | 0.3 |
| **run.sh total** | **19.2** |
| selftest.sh (11 breakages + clean run) | 43 |

In CI, add Rokit setup (~10 s cached) and the optional rhr install (~30–60 s, capped at 2 min). The job should come in at 1–2 minutes.

## Selftest

`selftest.sh` copies `tools/pr-gate` and `games/steal-a-slime` into a temp dir (`shared/` is symlinked) and breaks the copy. It never touches the working tree:

- **logic**: a failing spec fixture (`fixtures/failing.spec.luau`).
- **layout**: three edits to `Layout.luau`, each of which must fail both the Lune part and the rhr part:
  - one nav column at 844x390, PR #60's off-screen Rebirth/Goals/Dex/Leaders;
  - nav buttons at 70 % height (squashed);
  - the carry card moved over the nav (covered).
- **runtime-budget** (counts fixtures, no boot): parts 2203 passes; parts 2450 passes with a WARN; parts 2501 fails; 121 unique meshes fails; 501 MeshParts passes with a WARN.
- **budget**:
  - 501 MeshParts (`fixtures/soft-meshparts-counts.json`): passes with a WARN;
  - a 300k triangle limit (`fixtures/tight-shared-budgets.json`): fails;
  - `MESH_SLOT_BUDGET = 450` in code (drifts from the shared `mesh_parts.warn`): fails;
  - a missing FBX folder.

Each case must fail *for the expected reason*: the selftest greps for the expected message. The last step runs `run.sh` on the real, unmodified tree, which must pass.

## CI: applying the workflow patch (SuperBottie)

Bot tokens can't push `.github/workflows`, so the change is shipped as `tools/pr-gate/workflow.patch` (validated with actionlint 1.7.7). It changes `.github/workflows/pr-checks.yml`:

- The existing **`pr-gate`** job keeps its name, which is the ruleset's required check. After the game-jobs check it now checks out, installs the Rokit toolchain, optionally installs rhr (`continue-on-error`), and runs `tools/pr-gate/run.sh`.
- A new **`automerge`** job runs after `pr-gate` is green, for same-repo non-draft PRs. It runs `gh pr merge --squash --auto "$PR_URL"` with `contents: write` and `pull-requests: write`.

To apply:

```sh
git switch -c ci/pr-gate origin/main
git apply tools/pr-gate/workflow.patch
actionlint .github/workflows/pr-checks.yml
git commit -am "ci: run tools/pr-gate in pr-gate, squash auto-merge when green"
# push with a token that has the `workflow` scope, open the PR
```

Also:

- Turn on **Settings → General → Allow auto-merge**. Without it, `gh pr merge --auto` fails.
- Keep "pr-gate" as the required check.
- A merge done by `GITHUB_TOKEN` does not trigger other workflows on the resulting push to `main`. If post-merge workflows must run, use the SuperBottie app token in the `automerge` job instead of `github.token`.
