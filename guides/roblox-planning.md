# Roblox planning: funnel data to roadmap (official, 2026-10-15)

This is step 1 of Merijn's Roblox release pipeline. **Gojo** owns it. Gojo turns funnel data into version goals for the roadmap. Games: **steal-a-slime** and **speed-escape**.

Related:
- `/guides/roblox-release-process.md`: build, publish and gates.
- `/guides/roblox-critical-review.md`: step 7, where the goal set here is checked.
- `/workspace/roblox/roadmap-v17-v22.md`: the current roadmap.
- `/workspace/roblox/competitor-gaps.md`: the idea list.

## Pipeline step map
Merijn's adopted pipeline names **planning** as step 1 and **critical review** as step 7.
Those are Gojo's owned steps. They are **not** the numbered list in `roblox-release-process.md`
(where step 1 is Branch+PR and step 7 is Merijn's OK). Mapping:
- Planning (this pipeline's step 1) happens **before** a release version is assigned and feeds the roadmap.
- Critical review (this pipeline's step 7) runs **after** the visual/client gate and **before** Merijn's OK / publish live.

## Who does what
- **Gojo** reads the funnels, finds the biggest drop-offs and proposes version goals.
- **SuperBottie** checks the proposal and passes it to Merijn.
- **Merijn** accepts or rejects the version.
- **Phoenix, Archer, Jolt** build it (see Roles in `roblox-release-process.md`).

## Funnel data sources
Both come from `AnalyticsService` and show up in the **Creator Dashboard** (Analytics → Funnels).
- **Onboarding funnel:** `AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)`. One funnel per game. Steps are the first-session path, e.g. spawn → claim plot → first slime → first sale → first upgrade.
- **Shop funnel:** `AnalyticsService:LogFunnelStepEvent(player, "Shop", sessionId, step, stepName)`. Steps are e.g. open shop → view item → click buy → purchase done. Use a new `sessionId` for each shop visit.

Keep step numbers and names fixed once they ship. Renaming or renumbering a step breaks the comparison with older versions.

Note: no game code logs funnel events yet (checked 2026-10-15). Adding them is the first roadmap item for each game. Until then, planning has no funnel data and must say so.

## Hard rule: server scripts only
Funnel events are logged from **server scripts only**. Roblox drops them when sent from:
- a **client** (LocalScript, or any code under `StarterPlayerScripts`/`PlayerGui`),
- **Studio** (playtests send nothing; only **published** games count).

Roblox warning: https://create.roblox.com/docs/production/analytics/funnel-events

So:
- If the client sees the step first (e.g. "opened shop"), it fires a RemoteEvent, and the server logs the step. The server checks the step makes sense for that player before logging.
- Never judge funnel numbers from a Studio session. Read them from the dashboard after a published version has run for a while.
- A PR that calls either API from a client script is rejected in review.

## From funnel gap to version goal
1. Pick a window: the current live version, at least 7 days or 1,000 players in the first step, whichever comes later.
2. For each funnel, write down the conversion of every step (players at step N ÷ players at step N−1).
3. Find the **biggest drop-off**. That is the version's main target. At most one second target.
4. Write a measurable goal: *step, from, to, by when.*
   Example: "Onboarding step 3 → 4 (first slime → first sale) from 41 % to 55 % within 7 days of release."
5. Find the likely cause (usability notes, Studio screenshots, playtest notes). Then pick the fix.
6. Only now look at ideas, including competitor ideas, that could move that step.

## Every roadmap item must have
- [ ] A **measurable goal**: a number, a direction and a time window.
- [ ] The **event that measures it**: funnel name, step number and step name (e.g. `Onboarding` step 4 `FirstSale`).
- [ ] The baseline number from the current live version.
- [ ] Proof the event is logged from a server script (file and line).

An item without these four is not a roadmap item. It goes in the parked list.

## Competitors give ideas, analytics decides
- `competitor-gaps.md` is a list of **ideas**. It never decides what ships.
- A competitor idea gets onto the roadmap only if it targets a funnel step we measured as weak.
- "Steal a Brainrot has it" is not a reason. "Our first-sale step loses 59 % and this fixes the cause" is.

## Accept / reject criteria
**Accept** when all are true:
- It targets one of the two weakest steps in a funnel.
- It has a measurable goal and a server-logged event (see above).
- The effort fits one release (S or M in `competitor-gaps.md` terms).
- It fits the version's one focus.

**Reject or park** when any is true:
- No funnel step it would move, or no way to measure it.
- The step it targets already converts well (top half of the funnel).
- It adds a new parallel system where an existing one could be extended.
- It needs paid RNG or anything against Roblox rules.

## What goes in the roadmap file
**In:** per version: focus, lead, items, each item's goal + event + baseline, testing, "done when", blockers. A short changelog at the top.

**Not in:** raw dashboard exports, competitor research (link `competitor-gaps.md` instead), implementation details, long discussions, unmeasurable ideas (parked list only).

## Gojo's checklist before proposing a version
- [ ] Funnel window read from the Creator Dashboard (published game, not Studio)
- [ ] Conversion per step written down, biggest drop-off named
- [ ] Every item has goal + event + baseline + server-script proof
- [ ] Competitor ideas only where they target a weak step
- [ ] One focus, effort fits one release
- [ ] Roadmap file updated, changelog line added, date set
- [ ] Proposal sent to SuperBottie (not Merijn directly)

## How this feeds the release process
- The goal and event go into the PR description at step 1 of `roblox-release-process.md`.
- At step 7 (critical review), Gojo checks the result against this goal. See `roblox-critical-review.md`.
- After publish, the funnel is read again for the next planning round. A goal that was missed goes back on the roadmap with the new baseline.
