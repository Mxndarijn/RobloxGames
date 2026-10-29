# Exclusive Shop, perks and quick-buys: ideas

Status: **proposal, nothing built.** This is a menu for Merijn to choose from. No game code, prices or Config change with this doc. Every Robux price is a starting tier, not a decision.

The ideas come from what the game has today (main at #601): cash is the only currency, there is no Robux code at all (no `MarketplaceService`, no `ProcessReceipt`), the 16 Exclusive pet seats exist in `Config.PET_SEATS` with `unlock = { kind = "exclusive" }` and the Skins panel already says "Only in the Exclusive shop."

**Short version:** sell looks freely, sell time and comfort carefully, never sell safety from thieves or PvP power. The recommended first set is in [§6](#6-recommended-first-set).

---

## 1. Ground rules

### 1.1 Fairness rules for a stealing game

These follow from decisions already made (economy rework #561, PvP design, `docs/PVP.md`):

1. **Locks stay free and nobody buys their way out of being robbed.** No paid longer lock, no paid instant recall of a stolen slime, no theft-proof storage. Rich players being robbable is intended.
2. **No Robux in PvP.** `docs/PVP.md` principle 1: PvP items are cash plus rank. No paid weapons, cooldown skips, immunity or extra knockback. Cosmetic skins for a PvP item are fine if the hitbox, range and timing stay identical.
3. **No walk speed for Robux.** Speed decides both stealing and catching thieves.
4. **No rank bypass.** Rebirth gates (`CATCH_REBIRTHS`, `REBIRTH_TIERS[].merge`, `UPGRADES` gates, pad floors) stay earned.
5. **Paid boosts that help the whole server are preferred** over boosts that help one player, because they make the buyer popular instead of feared (the existing Luck Potion is already server-wide).
6. **Never "Coming soon".** An unsold item shows the "Exclusive" tag and where to get it.

Each idea below gets a fairness mark:

- ✅ **Fair**: cosmetic, or a comfort that gives no edge in a steal or a fight.
- ⚠️ **Careful**: speeds up progress or touches a shared resource. Fine with a limit, worth a second look.
- ❌ **Not recommended**: makes paying players hard to rob or hard to beat. Listed so the choice is explicit.

### 1.2 Roblox rules that apply

Checked on create.roblox.com (Developer Products, Passes, Paid random items policy, Subscriptions), October 2026.

| Rule | What it means here |
|---|---|
| **Game Pass = bought once, Developer Product = bought any number of times.** | Permanent perks (2x Income, VIP) are Game Passes. Boosts, skips and top-ups are Developer Products. Cosmetics can be either: see the note in §2.1. |
| **Developer Products need a correct `ProcessReceipt`.** Validate user, product id and status; grant; return `PurchaseGranted` only after the grant is saved; otherwise `NotProcessedYet` (Roblox retries on next join). Do not use `PromptProductPurchaseFinished` to grant. | One server-side receipt handler. The grant must land in the session-locked save before it answers `PurchaseGranted`, and a receipt id must never be granted twice (keep processed receipt ids in the save). Listed products can be bought outside the game (home page, search), so the handler must also work for a player who just joined. |
| **Paid random items must show every outcome and its odds** as percentages that add up to 100 %, before the purchase, behind a button with a word ("Details", "Odds"), not just an (i) icon. This covers capsules (hatch an egg), combination items (merging) and **probability modifiers (luck boosts, pity)**. A paid luck boost must explain its effect in numbers and the shown odds must update while it is active. | Anything Robux touches that changes a roll: a paid Luck Potion, a paid Slime Rain, a luck Game Pass, a paid egg. The Merge panel already shows "Random slime" + jump chance (`ui/Panels/Merge.luau`); a paid skip next to a random result needs the full odds. |
| **`PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted`.** Players where this is true must not buy random outcomes; the game must hide, block ("not available in your region") or offer a non-random path. | Every paid-random product needs a "restricted" branch. Easiest: don't sell random outcomes at all, and roll the result of a skippable timer **before** the purchase (see §4.1). |
| **Free random rewards need no odds.** | Free eggs, free merges and the free Luck Potion (cash only) need no disclosure, though showing odds is still friendly. |
| **Subscriptions**: monthly, at least 49 Robux, honour the benefits for the full term, distinct benefits per subscription (no Bronze/Silver/Gold tiers). | Optional "Slime Club" in §3. |

### 1.3 A correction to the brief

The brief says "a slime cap of 30". The code has no slime cap of 30: the cap is your pads (`PADS_START` 4 up to `PADS_MAX` 32, opened per rebirth) and saves keep at most 64 slimes. **30 is `MAX_REBIRTHS`.** The ideas below use the real pad and rebirth rules.

### 1.4 Robux tiers used below

| Tier | Robux | Typical use |
|---|---|---|
| XS | 15-49 | small skip, streak restore |
| S | 49-99 | short boost, small cosmetic |
| M | 99-249 | normal cosmetic, small perk |
| L | 249-499 | showpiece cosmetic, strong perk |
| XL | 499-1499 | bundles, VIP |

---

## 2. Exclusive Shop catalogue

The shop is the fairground carousel. Suggested **tabs for the shop UI** (one list for the UI session):

1. **Featured**: the current rotation and bundles (opens first).
2. **Clouds**: the 16 Exclusive pet clouds.
3. **Base**: Exclusive plot skins (and later base shapes).
4. **Style**: carry trails, deposit fanfares, lock-sign styles, Bat skins, name tags.
5. **Perks**: Game Passes (§3).
6. **Boosts**: server boosts and personal boosts (Developer Products from §4 that also make sense in a shop).

| # | Idea | Type | Tier | Fair |
|---|---|---|---|---|
| C1 | 16 Exclusive pet clouds | cosmetic (Dev Product, saved) | S-L | ✅ |
| C2 | Exclusive plot skins | cosmetic (Dev Product, saved) | M-L | ✅ |
| C3 | Carry trails | cosmetic | S-M | ✅ |
| C4 | Deposit fanfares | cosmetic | S | ✅ |
| C5 | Lock-sign and stopper styles | cosmetic | S | ✅ |
| C6 | Bat skins | cosmetic | S-M | ✅ |
| C7 | Slime hats (pad decorations) | cosmetic | S-M | ✅ |
| C8 | Bundles | Dev Product | L-XL | ✅ |
| C9 | Carousel rotation (weekly featured) | shop mechanic | – | ✅ |
| C10 | Seasonal limited items | cosmetic | M-L | ✅ |
| C11 | Gift an item to a player on the server | Dev Product | as item | ✅ |
| C12 | Exclusive base shapes | cosmetic | L | ✅ |
| C13 | Paid Mystery Egg | Dev Product | – | ❌ for now |

### C1. The 16 Exclusive pet clouds

- **What:** sell the 16 seats already modelled and listed in `Config.PET_SEATS`. Suggested price groups, by how showy the model is:
  - **S/M (79-149):** Leaf, Bubble, Lily Pad, Mushroom, Pancakes.
  - **M (149-249):** Storm, Sunset, Ice, Flame Cloud, Star Cushion, Crescent Moon, Clam Shell.
  - **L (299-499):** Magic Carpet, UFO, Royal Cushion, Hoverboard.
- **Where/when:** the Clouds tab of the carousel; the Skins panel's Cloud tab (an "Exclusive" seat gets a Buy button instead of only the tag); a "try it" preview that seats your pet on it for 10 s.
- **Type:** cosmetic. **Recommendation: Developer Product with ownership in the save**, not 16 Game Passes. Reasons: a single `ownedSeats` save field fits bundles, gifts and rotation; Game Passes can't be gifted or bundled. Cost: the receipt handler must save before granting (§1.2). A Game Pass per seat is the simpler alternative (Roblox stores ownership, no save risk) if bundles and gifts are not wanted.
- **Fairness:** ✅ cosmetic only. Pet passives (the pet's Lucky Charm chance) must not depend on the seat.
- **Code areas:** `Config.PET_SEATS` (unlock kind stays "exclusive", add product id), `shared/PlayerData.luau` + `shared/SaveData.luau` (owned seats, save migration), the pet-seat equip action in `server/Actions.luau`, `ui/Panels/Skins.luau` and `ui/PetSeatsView.luau` (Buy button), new receipt service (see §5).

### C2. Exclusive plot skins

- **What:** extra base themes beside the six Dex-earned ones (`PLOT_SKINS`: classic, garden, crystal, starlight, candy, mushroom). Ideas: **Fairground** (matches the carousel), **Haunted Ranch** (seasonal), **Beach Hut**, **Space Station**, **Winter Cabin**. The earned skins stay earned.
- **Where/when:** carousel Base tab; Skins panel Base tab, with the same "Exclusive" tag style as clouds.
- **Type:** cosmetic, Dev Product + save (same pattern as C1). **Tier:** M-L (199-399).
- **Fairness:** ✅. A skin must not hide pads, slimes or the lock sign, or change walk paths or collision (a skin that makes slimes hard to see would be a hidden defence). Review each skin against `docs/COLLISION.md`.
- **Code areas:** `Config.PLOT_SKINS` (new unlock kind "exclusive"), `server/PlotThemeView.luau`, `src/visuals` (Archer owns), Skins panel.

### C3. Carry trails

- **What:** a sparkle, goo-drip, rainbow or star trail behind you while you carry a slime (wild or stolen).
- **Where/when:** Style tab; shown in the Carry panel as "Your trail".
- **Type:** cosmetic, Dev Product + save. **Tier:** S-M (49-149).
- **Fairness:** ✅ and slightly good for PvP: a trail makes a thief easier to spot. Rule: a trail may never be transparent, tiny or hide the carried slime.
- **Code areas:** `server/Carry.luau` (carry start/stop already exists), a small client effect module hooked into the one client frame loop, Style save field.

### C4. Deposit fanfares

- **What:** the moment a slime lands on your pad: a confetti burst, a carousel jingle, a goo splash. Reuses the Lucky Charm show style (`server/LuckyShow.luau`).
- **Where/when:** Style tab. **Type:** cosmetic. **Tier:** S (49-99).
- **Fairness:** ✅. Mute-able, short (≤ 2 s), no screen cover for others.
- **Code areas:** deposit path in `shared/Steal.luau` / `server/Carry.luau`, `server/EffectsView.luau`.

### C5. Lock-sign and stopper styles

- **What:** a different look for the "LOCKED m:ss" sign and the stopper (candy bars, carousel ropes, a sleepy slime guard).
- **Type:** cosmetic. **Tier:** S.
- **Fairness:** ✅ only if the lock reads the same: the timer must stay readable from the same distance and the stopper keeps its collision.
- **Code areas:** `visuals/shared/PlotDecor.luau` (Archer), `server/WorldView.luau` (`LockUntil`), `server/PlotLockGuard.luau` (unchanged).

### C6. Bat skins

- **What:** the free Bat with another look (lollipop, fish, foam finger). Same reach (`SLAP_REACH`), cooldown and hitbox.
- **Type:** cosmetic. **Tier:** S-M.
- **Fairness:** ✅ if purely visual. Skins for paid-with-cash PvP items: same rule, later, after the PvP rework.
- **Code areas:** `server/BatTool.luau`, `server/PvpHeld.luau`, kit meshes.

### C7. Slime hats (pad decorations)

- **What:** a hat or bow shown on the slimes on your own pads (crowns, chef hats, flower crowns). The hat belongs to the pad, not the slime: a stolen slime arrives bare, so nobody loses a paid item.
- **Type:** cosmetic, new system. **Tier:** S-M (49-149, or a pack).
- **Fairness:** ✅. A hat must not make a slime look like a different rarity.
- **Code areas:** new; `server/HabitatPads.luau`, `server/SlimeLabelView.luau`, mesh kit. Biggest build of the cosmetics after C1.

### C8. Bundles

- **What:**
  - **Starter Bundle** (one per player, shown after the tutorial): one S cloud (e.g. Leaf) + a 15-min personal 2x income boost (B2) + a carry trail. ~99-149.
  - **Carousel Bundle**: Magic Carpet cloud + Fairground plot skin + a fanfare, about 25 % below the parts. ~599-799.
  - **Collector bundles** per theme (Sky: Storm/Sunset/Ice/Flame clouds).
- **Where/when:** Featured tab; Starter Bundle once in a welcome card after rebirth 1.
- **Type:** Dev Product (needs the C1 save pattern). **Tier:** L-XL.
- **Fairness:** ✅ as long as bundles hold only cosmetics and short boosts.
- **Code areas:** receipt service, catalogue table in `Config`.

### C9. Carousel rotation

- **What:** the carousel shows 4 "featured" items that change every week, the same on every server (computed from UTC time like `CONSUMABLES_RESTOCK_SECONDS` and `WeeklyEvents`). Items are always buyable in their tab too: the rotation is a spotlight with a small discount (10-20 %), not fake scarcity.
- **Where/when:** the carousel horses/seats physically carry the featured items; Featured tab.
- **Fairness:** ✅. Avoid countdown pressure on children; a quiet "Changes in 3 days" line is enough.
- **Code areas:** pure rotation module in `src/shared` (seeded by week number, like `shared/luau` seeded random), carousel model view, Featured tab.

### C10. Seasonal limited items

- **What:** one or two cosmetics per season (Halloween: Pumpkin cloud, Haunted Ranch skin; winter: Snowglobe cloud). Sold only during the event; they may return the next year.
- **Type:** cosmetic. **Tier:** M-L.
- **Fairness:** ✅. Say up front "returns next year" or "never returns" and keep that promise.
- **Code areas:** `server/WeeklyEventService.luau` (date windows), catalogue.

### C11. Gifting

- **What:** buy a cloud or skin for another player on the same server ("Gift" button on the item, then pick a player).
- **Type:** Dev Product granted to the recipient (the receipt is the buyer's; the grant goes to the target's save, or a pending-gift queue if they left). **Tier:** as the item.
- **Fairness:** ✅. Only cosmetics are giftable. Rate-limit and let the recipient decline (anti-spam).
- **Code areas:** receipt service, `server/Outbox.luau`-style pending queue, `server/Friends.luau` (friends first in the picker).

### C12. Exclusive base shapes

- **What:** `PLOT_BASES` (jar, factory, pagoda) is behind `FEATURES.BaseShapes = false`. When it ships, one or two extra shapes (Carousel Tent, Tree House) could be Exclusive.
- **Type:** cosmetic. **Tier:** L. **Fairness:** ✅ if the pad layout, paths and lock stopper match the jar exactly. **Code areas:** `server/BaseShapeSwap.luau`, `server/BaseFloors.luau`. Later, not in the first set.

### C13. Paid Mystery Egg (not recommended now)

- **What:** an Exclusive egg bought with Robux.
- **Why not:** it is a paid random item: full odds per species, the restricted-region branch, and odds that update with pity. It also sells slimes, which are the steal economy, and slimes feed rebirths. Free eggs stay free.

---

## 3. Perks / Game Passes

| # | Pass | Strength | Tier | Fair |
|---|---|---|---|---|
| P1 | VIP | low | XL (499-799) | ✅ |
| P2 | 2x Income | strong | L (399-499) | ⚠️ |
| P3 | 2x Offline Earnings | medium | M (149-249) | ✅ |
| P4 | Second Merge Vat | medium-strong | L (299-399) | ⚠️ |
| P5 | Fast Brew | medium | M (199-249) | ✅ |
| P6 | Warm Nest (eggs warm while away) | low | S-M (99-149) | ✅ |
| P7 | Lucky Charm+ | medium | M (199-299) | ⚠️ odds |
| P8 | Thief Radar | low | M (149) | ✅ |
| P9 | Slime Club (subscription) | low-medium | 99-149 / month | ✅ |
| ✗ | Longer lock, extra pads, vault, speed, PvP passes | – | – | ❌ |

### P1. VIP

- **What:** a VIP tag over your name and in chat, a gold name on leaderboards, a VIP seat ring on the carousel, one free VIP-only cloud recolour, **+10 % income**, and one free server Luck Potion per day (the potion helps everyone, so VIP buyers make servers happier).
- **Where:** Perks tab; a "VIP" chip on the HUD for owners.
- **Strength:** low. +10 % is below one friend-bonus step chain (`FRIEND_BONUS_CAP` 0.3).
- **Fairness:** ✅.
- **Code areas:** `shared/Perks.luau` (income multipliers), `server/Leaderboard*`, `server/ConsumableShop.luau` (free potion), chat tag in the client.

### P2. 2x Income

- **What:** permanent x2 on base income. The genre standard and likely the best seller.
- **Where:** Perks tab; a one-time tip in the Rebirth panel when cash is the missing item.
- **Strength:** strong: halves the time to every rebirth. It does not protect anything: a richer base is a juicier target, and locks are the same.
- **Fairness:** ⚠️. Fine for a PvP game because it gives no steal or fight edge, but check pacing: run the pacing sim (`lune run tools/livetest/pacing --seeds 1-20 --days 7`) with a 2x player to see how fast they hit `MAX_REBIRTHS`. Decide how it stacks with code boosts (`CODE_BOOST_MAX_MULT` 10) and MVP: suggest it multiplies into the same capped product.
- **Code areas:** `shared/Perks.luau`, `shared/Economy.luau`, `server/Income.luau`, pass check on join (`PlayerLifecycle`).

### P3. 2x Offline Earnings

- **What:** offline rate 25 % → 50 % and the offline cap +2 h (`OFFLINE_RATE`, `OFFLINE_CAP_SECONDS`; the OfflineCap upgrade still stacks).
- **Where:** Perks tab; on the Welcome-back card ("With 2x Offline you would have earned $X").
- **Strength:** medium for casual players, small for grinders. It builds on the 25 % decision instead of undoing it: free players stay at 25 %.
- **Fairness:** ✅. Offline players are already robbable the same way.
- **Code areas:** `shared/Economy.luau` (94-95), `shared/Perks.luau` (204), `ui/Panels/Welcome.luau`.

### P4. Second Merge Vat

- **What:** a second vat beside the first, so two brews run at once.
- **Where:** Perks tab; a "+ second vat" slot in the Merge panel while one is brewing.
- **Strength:** medium-strong: doubles merge throughput, which feeds the Dex, rebirth slimes and higher tiers.
- **Fairness:** ⚠️. Brewing slimes can't be stolen (`StealService` refuses "brewing"). A second vat lets a payer keep 6 instead of 3 slimes theft-proof. Fix: cap the vat count at 2 and keep it; or make brewing slimes stealable from a second vat. Decide before building.
- **Code areas:** `shared/VatState.luau` (single vat state today), `server/MergeVat.luau`, `server/VatView.luau`, Merge panel, base model (vat bay). Largest perk to build.

### P5. Fast Brew

- **What:** all brews 25 % faster, stacking with the Quick Brew upgrade (−15 %/level, 4 levels).
- **Where:** Perks tab; the Merge panel time line ("Fast Brew −25 %").
- **Strength:** medium. Inputs earn nothing while brewing, so faster brews mean more income too.
- **Fairness:** ✅ (shorter brew = slimes theft-proof for less time, which is the opposite of a defence).
- **Code areas:** `shared/VatState.luau` brew time, `Config.MERGE_BREW_SECONDS` stays the source.

### P6. Warm Nest

- **What:** Mystery Eggs on your pads hatch at the warm speed (`WARM_SPEED` 1.5) even when you are away from home.
- **Strength:** low. **Fairness:** ✅ (eggs on pads stay stealable).
- **Code areas:** `server/MysteryEgg.luau` (warm check), `shared/MysteryEgg.luau`.

### P7. Lucky Charm+

- **What:** +5 percentage points to the Lucky Charm promotion chance on deposit (today: Luck upgrade +3 %/level + pet passive).
- **Strength:** medium. **Fairness:** ⚠️ it is a **paid probability modifier**: the shop and the HUD must show the chance with and without the pass, as numbers, and update while it applies. Lucky Charm also promotes **stolen** slimes on deposit, which adds a small steal reward for payers; consider limiting it to wild catches.
- **Code areas:** `server/LuckyShow.luau`, `server/Carry.luau` (229-234), `shared/Upgrades.luau`, an odds line in the HUD/shop.

### P8. Thief Radar

- **What:** when your slime is stolen, an arrow and a map ping keep tracking the thief until they deposit or drop it (today the alert arrow is short, `STEAL_ALERT`). Information only: no slow, no recall.
- **Strength:** low. **Fairness:** ✅ (anyone can already chase a thief; this only helps find them). Check it doesn't make chases one-sided on a full server.
- **Code areas:** `Config.STEAL_ALERT`, the steal alert client view, `server/StealService.luau`.

### P9. Slime Club (optional subscription)

- **What:** monthly: a members-only cloud recolour that changes each month, a daily free server Luck Potion, +1 daily quest reroll, a Club badge.
- **Tier:** 99-149 Robux/month (minimum 49). **Fairness:** ✅. Benefits must not overlap VIP (Roblox asks for distinct benefits per subscription; VIP is a pass, so that's fine, but avoid "VIP but monthly").
- **Code areas:** subscription check on join, `shared/Progression.luau` (daily), `ConsumableShop`.

### Passes considered and not recommended (❌)

| Idea | Why not |
|---|---|
| **Longer Lock** (+60 s, or lock stacking) | Directly makes payers harder to rob. Merijn decided locks are free and the same for everyone (`LOCK_MAX_SECONDS` 240). |
| **Extra pads** beyond your rebirth | Pads open per rebirth and cost 25 % of the next rebirth by decision (#561); paid pads skip that. |
| **Theft-proof vault / storage** | A safe place for Secrets ends the stealing game for payers. |
| **Speed / Speed Coil+ / carry-slow reduction** | Faster grabs, faster getaways and faster thief chases. Strong Arms stays a cash upgrade. |
| **PvP item passes, cooldown cuts, immunity** | PvP is cash plus rank by design (`docs/PVP.md`). |
| **Higher catch rank** | Skips `CATCH_REBIRTHS`. |
| **Auto-collect** | Built later as the Auto Collect pass (Merijn, 2026-10-29): income now piles on cash pads, and only the owner can collect, so it is comfort. |

---

## 4. Contextual quick-buys (Developer Products)

Every timer, lock, cooldown and wait in the game, with a verdict. Found by reading `src/server`, `src/shared` and `Config` (file:line refs are into `src/`).

### 4.1 Before any paid skip: roll first

Two timers end in a random roll **at the end** today: the Mystery Egg rolls its species at hatch (`server/MysteryEgg.luau:52`, `SharedEgg.hatchEgg(..., world.eggRng)`) and the vat rolls its result at collect (`shared/VatState.luau:311`, `TripleMerge.apply`). A paid "Hatch now" or "Finish now" would then sell a random outcome, with the full odds disclosure and the restricted-region branch from §1.2.

**Proposal:** roll the result when the egg starts its clock / the brew starts, store it hidden, and reveal it at the end. The paid skip then only buys time. Keep showing the odds anyway (the Merge panel already does "Random slime" + jump chance), and hide the skip button for restricted players if legal review says a time skip on a random reward still counts.

### 4.2 The list

| # | Moment (file) | Who | Quick-buy | Type, tier | Fair | Verdict |
|---|---|---|---|---|---|---|
| Q1 | **Merge vat brewing**: goo bar with time left; `MERGE_BREW_SECONDS` 3-150 min by tier (`shared/VatState.luau`, `ui/Panels/Merge.luau`) | owner | **"Finish now"** button under the goo bar. Price by time left, e.g. ≤5 min 15, ≤30 min 35, ≤1 h 59, more 99. | Dev Product, XS-S | ✅ | **Build** (after §4.1) |
| Q2 | **Mystery Egg hatching**: "Hatches in m:ss" on the pad sign, `hatchSeconds` 180-900 (`shared/SlimeLabel.luau:117-123`, `shared/MysteryEgg.luau:94-120`) | owner | **"Hatch now"** on the egg's pad sign / HatchPrompt. Flat 25 (speckled) to 49 (cosmic). | Dev Product, XS | ✅ (eggs stay stealable until hatched) | **Build** (after §4.1) |
| Q3 | **Welcome-back card**: offline cash already paid (`ui/Panels/Welcome.luau`, `OFFLINE_RATE` 0.25) | owner | **"Double it"**: pay once to get the same offline amount again. Shown only on the card, one use per card. | Dev Product, S (scaled: 25-99 by amount bracket) | ✅ | **Build** |
| Q4 | **Luck Potion sold out**: "RestockTimer" chip, restock every 300 s, stock 1-4 (`server/ConsumableShop.luau`, `ui/Panels/WorldShop.luau:161,334`) | all | **"Server Luck Potion"**: buy one with Robux even when sold out; same effect (x2.5 tier 3+, +5 min, max 15 min, server-wide). Toast: "&lt;player&gt; gave the server a Luck Potion!" | Dev Product, S (49-79) | ✅ shared benefit; **odds rule applies** (paid probability modifier): show tier odds with/without | **Build**, plus add the missing potion HUD timer (today `potionUntil` only lives in `State.consumables`, no HUD) |
| Q5 | **Slime Rain countdown**: HUD timer, every 60 min for 3 min, luck x5 (`ui/RainTimer.luau`, `server/Spawner.luau:80`) | all | **"Start Slime Rain now"** for the whole server; at most once per 20 min per server, never during a boss. | Dev Product, M (149-199) | ✅ shared; odds rule applies | **Build** (good "hero moment") |
| Q6 | **Personal income boost**: codes give `boostMult`/`boostUntil` (`shared/PlayerData.luau:70,75`) | owner | **"2x income for 15 / 60 min"** in the Boosts tab and on the Rebirth panel when only cash is missing. Stacks into the existing capped boost. | Dev Product, S (49 / 129) | ⚠️ progression speed | Build later, with P2 |
| Q7 | **Daily streak broken**: "already claimed", streak cap 7 (`shared/Progression.luau:185`, `ui/Panels/DailyPopup.luau`) | owner | **"Keep my streak"** once when a day was missed. | Dev Product, XS (25) | ✅ | Optional |
| Q8 | **Weather Totem sold out** (`ConsumableShop.luau:83`) | all | Robux Weather Totem for the server. | Dev Product, S | ✅ | Optional, low demand |
| Q9 | **Boss arrives in N min**: `BOSS.FIRST_AT` 480, `INTERVAL` 1200 (`server/BossEvent.luau`) | all | "Summon the boss now" for the server, once per server per 20 min. | Dev Product, M | ⚠️ upsets the boss/Rain schedule and the MVP race | Later, maybe |
| Q10 | **Cash short**: "need $X" on a wild slime (`server/Carry.luau:124`), pad price (`Economy.luau:141-160`), upgrades, rebirth cash (`server/Rebirth.luau:23-33`) | owner | **Cash top-up** sized to the player's income ("+30 min of your income"), never a fixed sum (cash resets on rebirth and spans 15K-8.5T). | Dev Product, S-L | ⚠️ pay-to-progress; on a wild slime it also beats other players to a shared drop | Only as a shop item, **not** as a prompt on contested wild slimes |
| Q11 | **Slime growth** (+50 % over 12 h, `shared/Growth.luau:70,95`) | owner | "Growth Snack": one slime jumps 3 h of growth. | Dev Product, XS | ✅ small | Optional |
| Q12 | **Co-op ritual cooldown**: 10 min server and player (`shared/Ritual.luau:83,173-187`) | players | Skip your own ritual cooldown. | – | ✅ | Skip: needs 2 players anyway, low value |
| Q13 | **Plot full**: GrabBlockCard "plot full" (`ui/GrabBlockCard.luau`, `Carry.luau:115,215`) | both | ~~Buy a pad with Robux~~ | – | ❌ skips the per-rebirth pad decision | No. Offer a free "sell your cheapest slime" shortcut instead |
| Q14 | **Lock ended**: toast "Your base is unlocked!" (`server/StealService.luau:199`), lock already running (`shared/Steal.luau:90`) | owner | ~~Extend lock / lock again now~~ | – | ❌ paid defence | No. Relocking is already free |
| Q15 | **Base locked** (thief side, `Steal.luau:110`), breather lock 20 s (`SlimeGuard.luau:296`), join lock 120 s (`Steal.luau:72`) | thief | ~~Break the lock~~ | – | ❌ paid attack | No | Approved later (Merijn, 2026-10-29): built as the lock break, contract §11.
| Q16 | **Your slime is being stolen**: alarm toast + HUD banner (`StealService:100`, `ui/Hud.luau:11`) | owner | ~~Send it home now / protect~~ | – | ❌ | No. P8 Thief Radar is the fair version |
| Q17 | **Thief got bonked / pickup cooldown 1.5 s** (`StealService:136`, `Carry.luau:161`) | thief | ~~Skip cooldown~~ | – | ❌ | No |
| Q18 | **PvP cooldowns, control immunity, item rank gates** (`shared/PvpRules.luau:172-194,268-275,317`) | all | ~~Skip / unlock~~ | – | ❌ | No (`docs/PVP.md` principle 1) |
| Q19 | **Rank gates**: catch rarity, merge, egg kind, upgrades, PvP items (`shared/GrabBlock.luau:76`, `shared/MergeGate.luau`, `shared/EggKind.luau:64`, `shared/Upgrades.luau:60-72`) | owner | ~~Unlock early~~ | – | ❌ skips rank | No |
| Q20 | **Rebirth missing a slime**: "Bring these" checklist (`ui/Panels/Rebirth.luau`) | owner | ~~Buy the missing slime~~ | – | ❌ sells slimes, paid random if rolled | No |
| Q21 | **Wild slime despawning** (`shared/Fountain.luau:87-90`), fountain pity and guarantees | all | – | – | – | Nothing to sell |
| Q22 | **Tutorial steal skip 20 s, hold-to-confirm 0.8 s, action rate limits, Lucky Charm show** | – | – | – | – | Nothing to sell |

---

## 5. Code areas every option shares

Whatever is chosen, these pieces come first (one PR, before any product):

- **Receipt service** (`server/`): one `MarketplaceService.ProcessReceipt` callback; a table from product id to grant function; grant into the session-locked save, store the receipt id, then return `PurchaseGranted`; `NotProcessedYet` on any failure. Game Pass checks on join (`UserOwnsGamePassAsync`, cached) and on `PromptGamePassPurchaseFinished`. The ledger and "grant once per receipt id" logic has nothing game-specific in it: per `CLAUDE.md` it belongs in `shared/luau` as a pure core plus a thin Roblox adapter, with Lune specs.
- **Policy check**: `PolicyService:GetPolicyInfoForPlayerAsync` once per player, cached; hide paid-random products (Q4, Q5, P7) for restricted players or show "not available in your region".
- **Save fields + migration**: owned cosmetics, processed receipt ids, gifts pending (`shared/SaveData.luau`, new save version per `ARCHITECTURE.md`).
- **Contract first**: new Request actions (`BuyProduct`, `EquipCosmetic`, `GiftItem`) and State fields go into `CONTRACT.md` before code (owner rules in `games/steal-a-slime/CLAUDE.md`).
- **Product ids** in `Config` (one place), with a test fake so Lune specs and the memory-store live session can "buy" without Roblox. Never hit production DataStores while testing purchases.
- **Flag**: none; the shop ships on.

---

## 6. Recommended first set

Seven items that cover cosmetics, one strong pass and the best quick-buys, with no ❌ and only one ⚠️:

| # | Item | Why first |
|---|---|---|
| 1 | **C1 Exclusive pet clouds (16)** | Models exist, the UI already points at the shop, Merijn has decided they are Exclusive. Pure cosmetic. |
| 2 | **C8 Starter Bundle** | A cheap first purchase that converts new players; built on C1 plus Q6's boost. |
| 3 | **P2 2x Income** | The genre's best-selling pass; no steal or fight edge. Check pacing with the sim first (⚠️). |
| 4 | **P3 2x Offline Earnings** | Builds on the 25 % decision; pairs naturally with Q3. |
| 5 | **Q1 Finish brew now** | The longest waits in the game (up to 150 min), right where the player looks at them. Needs §4.1 (roll at start). |
| 6 | **Q3 Double offline earnings** | One card, one button, clearly fair. |
| 7 | **Q4 Server Luck Potion** | Social: the buyer helps the whole server. Reuses the existing potion. Needs the odds display and a potion HUD timer. |

Next wave: C2 plot skins, C3 trails, C9 carousel rotation, Q2 Hatch now, Q5 Start Slime Rain, P1 VIP, P5 Fast Brew.

Decisions for Merijn:

1. Cosmetics as Developer Products with saved ownership (bundles, gifts, rotation) or as Game Passes (simpler, no save risk)?
2. OK to move egg and vat rolls to the start of the timer (§4.1)?
3. P4 Second Vat: allowed, and if so, may slimes in it be stolen?
4. Show the "Exclusive" cloud Buy button in the Skins panel too, or only in the carousel?
