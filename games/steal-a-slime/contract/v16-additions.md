# 9. v16 additions (2026-10-15, Phoenix)

**Status:** contract first; the server commits that follow implement it. Driven by the v15 Studio playtest (`/workspace/roblox/usability/v15-findings.md`). New fields are optional for readers. Where this section and §1-§8 disagree, this section wins.

## 9.1 No "claim free plot" (removed in v30 C6)

Plots are **auto-assigned on join** (`Sessions.join`, lowest free plot) and freed on leave. The v16 `ClaimPrompt` on a free plot's `BuyStand`, `PlotClaim.luau`, `Constants.CLAIM_PROMPT_NAME`, `world.claims` and the per-plot `BuyStand` model are gone. `ranch_shop_stand` is used only by the plaza `ShopStand`.

## 9.2 Tutorial: no skipping steps you haven't done (finding #8)

Replaces the "finishes that step and every step before it" rule of §2 / §8.3. `TutorialProgress.complete(data, name)`:

- The **current** step's action finishes it. A **later** step's action no longer jumps ahead (buying a pad at step 1 used to skip Deposit and Lock); an earlier step's action still does nothing.
- After any action the server **skips every step the player has already done**, judged from saved data (`TutorialProgress.isDone`): Grab / Deposit `stats.caught > 0`, Lock `stats.locks > 0`, BuyPad `padsUnlocked > PADS_START`, Merge `stats.merges > 0`, Steal `totalStolen > 0` or `rebirths > 0` (solo servers can't steal: `StealService.tickTutorial` skips Steal after `TUTORIAL_STEAL_SKIP_SECONDS` = 20 s with no other player's pad slime), Rebirth `rebirths > 0`.
- So a player sees every step they haven't done yet, in order. Save format, step names and `State.tutorialStep` / `tutorialStepId` are unchanged.

## 9.3 `State.lockStartedAt` (finding "lock bar scaled to 300 s")

```luau
lockStartedAt: number,  -- server time the current lock began (join lock or a purchase while open); extending keeps it
```

The HUD lock bar can show `(lockUntil - now) / (lockUntil - lockStartedAt)`, so a fresh 60 s lock reads full instead of 18 % of `LOCK_MAX_REMAINING`. In every snapshot.

## 9.4 Findings that are not server work (owners)

- **Jolt (src/ui):** scroll lists `VerticalAlignment` (#1), carry panel under tutorial card (#2), Speed Coil description in `ShopCatalog` (#4, see §8.10: it works while carrying), boss banner width (#5), rebirth disclaimer clip (#6), `UIScale` (#7), tutorial copy "hold" -> "press E" and free-vs-paid (#8; `GrabPrompt.HoldDuration` is 0), Daily modal vs tutorial on spawn (#9), lock bar via §9.3, cash format, rebirth double-click, dex badge.
- **Archer (src/visuals):** tutorial arrow texture (#10), Sky / night, pad colours, LockButton colour should follow the plot `Locked` attribute, plot signs at night, the plot Sign + BuyStand duplication.
