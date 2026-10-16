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
| `budget.sh` | `budget_counts.luau` counts `WorldLayout.build()` with the same rules as `tests/WorldBudget.spec`. `budget_check.py` adds triangle counts read from `shared/modeling-kit/out/<mesh>.fbx` (a binary FBX reader, matching the kit's `stats.json` exactly). | Any limit in `budgets.json` exceeded. A counted mesh with no FBX. A `WorldLayout.*_BUDGET` constant raised above the gate's limit. |
| `typecheck.sh` | `games/steal-a-slime/scripts/typecheck.sh` (luau-lsp against the Rojo sourcemap), the same as the CI types job. **When luau-lsp or rojo is not on PATH it prints `typecheck: SKIP (luau-lsp/rojo missing; CI types job covers it)` and exits 0**, so the CI `pr-gate` job passes without them. | Type errors in `src/server` and `src/shared`. |

### Budgets (`budgets.json`)

| Budget | Limit | Current | Source |
|---|---|---|---|
| Mesh slots (MeshParts) | 400 | 324 | THEME.md, `WorldLayout.MESH_SLOT_BUDGET` (PR #56) |
| Parts outside Map.Border | 1200 | 956 | THEME.md / CONTRACT §10, `WorldLayout.PART_BUDGET` |
| Map.Border parts | 700 | 92 | `WorldLayout.BORDER_PART_BUDGET` |
| World triangles | 500,000 | 390,730 | **Proposed**: 400 slots × 1250 tris (the midpoint of THEME's 500–2000 per-prop target). This is about the scene size low-end phones handle, and leaves ~28 % headroom. |
| Max triangles per mesh | 10,000 | 6,814 (slime_fountain) | THEME.md: the kit fails a mesh at 10k or more. Roblox's own limit is 20k. |

To change a limit, edit `budgets.json` and explain the change in its `rationale`. For experiments, `PR_GATE_BUDGETS`, `PR_GATE_COUNTS` and `PR_GATE_FBX_DIR` override the inputs.

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
- **budget**:
  - 401 mesh slots (`fixtures/over-budget-counts.json`);
  - a 300k triangle limit (`fixtures/tight-budgets.json`);
  - `MESH_SLOT_BUDGET = 450` in code;
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
