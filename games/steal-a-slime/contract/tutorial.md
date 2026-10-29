# 49. Tutorial: the loop and the places to come back to

**Status:** always on (no flag). Replaces the step list of §2 Tutorial, §8.3 (v13-additions.md) and the Steal rules of §9.2 (v16-additions.md). Server-authoritative; the tutorial pays nothing.

## Steps

`TutorialProgress.STEPS = { "Grab", "Deposit", "Lock", "Leaderboard", "Guide", "BuyPad", "Merge", "BuyItem" }`. Only the current step's action finishes it; after any action every step the save shows as done is skipped (`TutorialProgress.isDone`).

| Step | Finished by | Done in the save when |
|---|---|---|
| `Grab` | grabbing or buying a wild slime (`Carry`) | `stats.caught > 0` |
| `Deposit` | bringing a carried slime home (`Carry`) | `stats.caught > 0` |
| `Lock` | a lock from the lock pad or the HUD Lock button (`StealService.buyLock`) | `stats.locks > 0` |
| `Leaderboard` | standing within `Config.TUTORIAL_LEADERBOARD_RADIUS` studs (flat) of `Map.LeaderboardBoard` (`TutorialService.tick`, once a second) | never |
| `Guide` | triggering the TutorialNpc's `GuidePrompt` (`TutorialService.talkedToGuide`; the server listens to `Triggered`) | never |
| `BuyPad` | `Request("BuyPad")` or the `BuyPadPrompt` | `padsUnlocked > PADS_START` |
| `Merge` | collecting a merge from the vat (`MergeVat`) | `stats.merges > 0` |
| `BuyItem` | any successful `BuyConsumable`, `BuyPvpItem` or `BuyUpgrade` (directly or through `ShopBuy`) | owns an upgrade level, a held consumable or a PvP item |

Finishing the last step sends Notify "Tutorial complete! You're a slime tycoon now." (`"good"`, no sound). Nothing is paid.

## Skip

`Request("SkipTutorial")` (no arguments, rate 1 s): ends the tutorial (`tutorialStep = 0`); refused when it is already over. The Guide panel offers it as a hold button while the tutorial runs.

## State and attributes

Unchanged names: `State.tutorialStep` (1..8, nil = done), `State.tutorialStepId` (the step name, nil = done), Player attributes `TutorialStep` / `TutorialStepId`. Clients read the names, never the numbers.

## Save (v12)

`SAVE_VERSION = 12`. `SaveData.migrateV11` maps a saved v11 `tutorialStep` (Grab, Deposit, Lock, BuyPad, Merge, Steal, Rebirth) onto the new list: 0..3 stay, BuyPad (4) resumes at Leaderboard (4), Merge (5) at Merge (7), Steal and Rebirth (6, 7) are done (0). A save from before v3 first moves its Merge / Steal / Rebirth (4..6) up one for the old BuyPad step.

## Client

- **Card (`ui/TutorialCard`):** a Gold notice card in the top banner stack under the steal cards: step icon, title, one hint line naming the device's control (`ui/Tutorial`), "3/8". Tapping it shrinks it to its icon. A mint card shows what was just done; after the last step "Tutorial done" with a ring round Goals (`ui/Hint`). No bottom card.
- **Trail (`visuals/client/TutorialArrow`, shared `guide/GuideView`):** Leaderboard → `Map.LeaderboardBoard`, Guide → `Map.TutorialNpc`, BuyItem → the closer of `ItemShopStand` / `UpgradeShopStand`; the own-plot and slime targets as before. Routes end next to solid targets (or on the pad / zone the player must stand on) and are never drawn straight through walls.
