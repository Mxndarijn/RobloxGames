# Roblox critical review (official, 2026-10-15)

This is step 7 of Merijn's Roblox release pipeline. **Gojo** owns it. Gojo gives an **independent** critical review of a release before **Merijn's OK** and before publish. Games: **steal-a-slime** and **speed-escape**.

Related:
- `/guides/roblox-release-process.md`: build, publish and the visual/client gate.
- `/guides/roblox-planning.md`: step 1, where each item's measurable goal is set.
- Example review: `/workspace/roblox/usability/v17/critical-review.md`.

## Pipeline step map
Merijn's adopted pipeline names **planning** as step 1 and **critical review** as step 7.
Those are Gojo's owned steps. They are **not** the numbered list in `roblox-release-process.md`
(where step 1 is Branch+PR and step 7 is Merijn's OK). Mapping:
- Planning (this pipeline's step 1) happens **before** a release version is assigned and feeds the roadmap.
- Critical review (this pipeline's step 7) runs **after** the visual/client gate and **before** Merijn's OK / publish live.

## Who does what
- **Release owner** (usually Phoenix): builds the before/after report.
- **Visual/client gate owner** (proposed: Jolt, backup Archer): runs the Studio playtest that produces the rhr findings.
- **Gojo**: reviews and gives the verdict.
- **SuperBottie**: passes a PASS on to Merijn.
- **Merijn**: gives the OK to publish.

## Independent means
- Gojo did not build the release and does not soften the review for the team that did.
- Gojo reads the evidence itself (images, logs, numbers). It does not take the PR's summary on trust.
- If evidence is missing, that is a fail, not a "probably fine".

## Input: the before/after report
The release owner hands Gojo one structured report, in `usability/v<N>/`. It must have these sections:
- **PC**: before/after screenshots at 1920×1080 and 1366×768.
- **Phone**: before/after at 844×390 (and 390×844 where portrait matters), from the Studio device emulator.
- **Tablet**: before/after at 1024×768.
- **rhr findings**: the release-health results from the visual/client gate in Studio:
  - the client layout script results per size (off-screen, unfitted text, clipped lists, overlaps),
  - the play console errors and warnings,
  - human notes from the person who ran the playtest.
- **Funnel result**: the roadmap goal, its event, the baseline and the latest number.

Every screenshot is labelled with the gate point (spawn, Shop, Goals, etc.) and before/after. A missing section is a fail.

## Fixed checklist: all must pass
- [ ] **Readable on phone.** All text at 844×390 is readable without zoom. No `TextFits == false` on unscaled labels. Signs and BillboardGuis readable (checked with `execute_luau`, since `screen_capture` leaves them out).
- [ ] **Every button reachable.** On PC, phone and tablet: no button off-screen, under another panel, or inside a list that can't scroll. Tap targets ≥ 44 pt on phone.
- [ ] **No new log errors.** The play console has no script errors that were not there before. New warnings are listed and explained.
- [ ] **Funnel goal met.** The measurable goal from the roadmap item is met, measured by its event (see `roblox-planning.md`).

One failed item means the verdict is **fail**.

About the funnel goal: funnel events only count from a **published** game. Before the first publish, Gojo checks that the event is logged from a server script and fires in the right place. The goal itself is checked on the live numbers after release, and a miss goes back to planning.

## Review bar
- Compare with **popular Roblox games**: Steal a Brainrot, Grow a Garden. Would this screen hold up next to theirs on a phone?
- Be critical. Name what looks cheap, empty, unclear or broken, even if it improved.
- Don't go easy because the release is better than the last one. "Better than v16" is not the bar.
- Short and concrete: say what is wrong and where, not general taste.

## Output format
Write to `/workspace/roblox/usability/v<N>/critical-review.md` (e.g. `usability/v17/critical-review.md`). Same layout every time:

1. **Title:** `v<N>: critical review (independent, Gojo)`, then the sources (report path, commits before/after) and caveats (e.g. low resolution).
2. **Verdict:** **PASS** or **FAIL**, one line, then 2–3 lines why.
3. **Checklist:** the four items above, each ✅ or ❌ with the evidence.
4. **Per area:** one section per panel or area (e.g. Shop, Plot, Tutorial). Each has **Improved** and **Cheap/broken**, with the device (PC, phone, tablet) where it matters.
5. **Top fixes before release:** at most 5, priority order. Each says what, where and why. Blocking fixes come first and are marked **(blocker)**.

## Common reasons to fail
- Phone screenshots missing, or taken at desktop size and scaled down.
- A panel looks fine at 1920×1080 but its close button is off-screen at 844×390.
- Shop or Goals list can't scroll to its last row on tablet.
- A new console error, even one the team calls harmless.
- The funnel event fires from a LocalScript, so it will never reach the dashboard.
- World or UI still reads as prototype next to Steal a Brainrot (empty space, grey boxes, flat sky).

## Pass or fail: what happens next
- **PASS:** Gojo signs off in the PR, links the review and tells **SuperBottie**. SuperBottie passes it to Merijn for the OK (step 7 → step 8 publish).
- **FAIL:** Gojo marks the PR as blocked, links the review and lists the blocking fixes. The release does not go to Merijn. After the fixes, the owner sends a new report and Gojo reviews again (a new file `critical-review-2.md`, the old one stays).
- Gojo never publishes and never merges.

## Gojo's checklist
- [ ] Report has PC, phone, tablet and rhr findings sections, plus the funnel result
- [ ] Looked at every screenshot myself, before and after
- [ ] Layout script: 0 off-screen, 0 unfitted text, 0 clipped lists, 0 overlaps
- [ ] Console: no new errors
- [ ] Funnel event is server-side and the goal check is recorded
- [ ] Compared with Steal a Brainrot / Grow a Garden
- [ ] Review written to `usability/v<N>/critical-review.md` in the fixed format
- [ ] Verdict posted in the PR and sent to SuperBottie
