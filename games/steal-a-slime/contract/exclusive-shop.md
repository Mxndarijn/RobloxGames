# 47. Exclusive Shop: Robux purchases, the carousel, quick-buys (2026-10-28)

**Status:** behind `Config.FEATURES.ExclusiveShop` (default off; Studio review via `PcwFlag_ExclusiveShop`). Approved
by Merijn: the carousel model (`shared/modeling-kit/models/ranch_exclusive_carousel.py`), the UI direction A with B's
stage (`docs/exclusive-shop-ui-mockup.html`) and the first set from `docs/exclusive-shop-ideas.md` §6.

**Fairness rules (from the ideas doc §1.1, binding):** sell looks freely, time and comfort carefully, never safety from
thieves or PvP power. No paid lock, no paid lock break ("open a locked door"), no paid pads, speed, PvP, rank skips,
no paid random outcomes. A paid timer skip only buys time: the outcome is fixed when the timer starts.

## 1. Catalogue (`Config.EXCLUSIVE_SHOP`, the one source of truth)

Every Robux product lives in one frozen table. `productId` / `passId` are Roblox ids; **`0` = not created yet** (Merijn
creates them on the Creator Dashboard). A product with id 0 shows in the UI with its price but its Buy button is
disabled with "Not on sale yet" (never "Coming soon"); Studio can still grant it through `StudioHooks`.

- `products` (Developer Products, keyed by a permanent product key):
  - `Seat_<seatId>` for the 16 Exclusive seats, `grant = { kind = "seat", seat = <seatId> }`, `robux` by tier:
    99 (leaf, bubble, lily_pad, mushroom, pancakes), 199 (storm_cloud, sunset_cloud, ice_cloud, flame_cloud,
    star_cushion, crescent_moon, clam_shell), 399 (magic_carpet, ufo, royal_cushion, hoverboard).
  - `StarterBundle` 149: `{ kind = "bundle", seats = { "leaf" }, boostMult = 2, boostSeconds = 900 }`, once per player
    (`data.starterBundle`; the UI stops offering it once claimed; a repeat receipt still adds the boost).
  - `FinishBrew_1..4`: `{ kind = "finishBrew" }`, robux 15 / 35 / 59 / 99 for time left <= 5 min / 30 min / 60 min / more
    (`Config.EXCLUSIVE_SHOP.finishBrewBrackets = { 300, 1800, 3600, math.huge }`).
  - `HatchNow_<eggKind>`: `{ kind = "hatchNow" }`, robux 25 / 35 / 45 / 49 by egg kind (speckled → cosmic).
  - `DoubleOffline`: `{ kind = "doubleOffline" }`, robux 49.
  - `ServerLuckPotion`: `{ kind = "serverPotion" }`, robux 79. A paid probability modifier: odds disclosure + policy (§5).
- `passes` (Game Passes, keyed by pass key): `Income2x` 449 (`incomeMult = 2`), `Offline2x` 199 (`offlineRate = 0.5`).
- `tabs`: `{ "Featured", "Clouds", "Perks", "Boosts" }` in this order. Featured = StarterBundle (while unclaimed) +
  the 4 rotation seats (§6). Clouds = the 16 seats. Perks = passes. Boosts = ServerLuckPotion (and the quick-buys'
  explanation rows; they are bought where they appear).

## 2. Save (version 10, `SaveData.migrateV9`)

New fields on `PlayerData.Data`, all cleaned on load:
- `ownedSeats: { string }`: Exclusive seat ids bought (unknown / non-exclusive ids dropped, deduped).
- `receipts: { string }`: processed `PurchaseId`s, newest last, capped at `Config.EXCLUSIVE_SHOP.receiptMemory` (200).
- `starterBundle: boolean`: claimed.
- `credits: { brew: number, hatch: number }`: a paid skip that arrived when there was nothing to skip (0..99 each).
- `offlineDouble: { cash: number, at: number, used: boolean }?`: the last welcome-back payout, so a "Double it" receipt
  retried on a later join still pays the right amount.
- `vat.seed: number?` and `slime.egg.seed: number?`: the roll seed fixed when a brew / incubation starts (§4).
Game Pass ownership is **not** saved: checked on join (`UserOwnsGamePassAsync`, cached in `session.passes`) and on
`PromptGamePassPurchaseFinished`.

## 3. Server

- **`server/Purchases.luau` (pure):** `grant(world, session, productKey, now, ctx) -> (ok, reason)` applies one grant
  by `grant.kind`; `applyPasses(session, passes)` sets the runtime multipliers. Never errors.
- **`server/PurchaseService.luau`:** `service(options)` (backend + save injected, Lune-tested) and `start(service)`
  (Roblox wiring, only with the flag on): the only `MarketplaceService.ProcessReceipt`. For a receipt:
  player not in this server or data not loaded → `NotProcessedYet`; `PurchaseId` already in `data.receipts` →
  `PurchaseGranted`; else `Purchases.grant`, append the receipt, **save now** (`Persistence` save, session-locked);
  only a successful save answers `PurchaseGranted`, anything else `NotProcessedYet` (`Persistence.save` returns
  whether it wrote). A PurchaseId granted in memory whose save failed is saved again on the retry before it counts.
  The receipt-ledger core is game-agnostic: `shared/luau/src/data/ReceiptLedger.luau` (`clean`, `seen`, `record`,
  `process`). `join` (once the session exists) checks each pass with a non-zero `passId` and the policy (below).
- **Pet seats:** `PetSeats.unlocked` treats kind `exclusive` as `table.find(data.ownedSeats, id) ~= nil`.
- **Passes:** `Income2x` multiplies into `Perks.bonusMultiplier` (one more factor, runtime `data.passIncomeMult`);
  `Offline2x` sets the rate passed to `Economy.offlineIncome` (`OFFLINE_RATE` 0.25 → 0.5; runtime
  `data.passOfflineRate`). The pass check finishes after the join's payout, so `applyPasses` pays the difference
  then (and adds it to `offlineDouble.cash` and the welcome card). Free players are unchanged.
- **Quick-buy grants:** `finishBrew` sets the vat's `endsAt = now` while brewing, else `credits.brew += 1`;
  `hatchNow` (`HatchNow_<eggKind>`) hatches-ready the player's incubating pad egg of that kind closest to ready
  (`hatchAt = now`; a receipt names no slime), else `credits.hatch += 1`;
  `doubleOffline` pays `offlineDouble.cash` once (`used = true`), else nothing to pay → `NotProcessedYet` never: it
  grants 0 and records the receipt (the UI only offers it while `offlineDouble` is unused); `serverPotion` calls
  `Consumables.extendPotion` server-wide and notifies everyone "<name> gave the server a Luck Potion!".
- **Requests (Remotes.ACTIONS / Validate.ACTIONS):** `AimHatch(slimeId: string)` 0.5 s: the incubating pad egg the next
  `HatchNow_<kind>` receipt is for (a receipt can't name it); the grant uses it when it still fits the paid kind, else
  that kind's egg closest to ready, then forgets it. The client sends it just before the Roblox prompt.
   `UseCredit(kind: string, slimeId: string?)` 0.5 s: spends a
  brew credit on the running brew or a hatch credit on that egg (`slimeId` nil = the egg closest to ready); flag off
  → "the Exclusive Shop is off". No action prompts purchases: the client calls
  `MarketplaceService:PromptProductPurchase` / `PromptGamePassPurchase` itself with ids from Config.
- **Studio:** `StudioHooks.grantProduct(userId, productKey)` / `setPass(userId, passKey, owned)` /
  `setPaidRandomAllowed(userId, allowed)` run the same PurchaseService paths (receipt id `studio-<guid>`, grant,
  save; Studio + memory store only, no remote). They set player attributes (`PcwGrantProduct`, `PcwPass` =
  `"<key>=true|false"`, `PcwPaidRandom`) the server applies, so Studio MCP `execute_luau` can call them
  (`require(game.ServerScriptService.Server.StudioHooks)`).

## 4. Roll first (vat and eggs)

`VatState.start` stores `vat.seed` (from `world.rng`); `VatState.collect` rolls with a fresh `Rng` seeded by it.
`SharedEgg.startIncubating` stores `egg.seed` (server: from `world.eggRng`); `hatchEgg` rolls with an `Rng` from it
(the slime inside an egg is rolled when it spawns; the seed fixes the lucky-meter reroll). Seeds are whole numbers
in 1..`Rng.SEED_MAX`; Cancel clears the vat's. Old saves without a seed roll as today. The outcome is therefore fixed when the clock starts; "Finish now" / "Hatch now" only change time.

## 5. State

`State.exclusiveShop = { enabled, owned = { [seatId]: true }, passes = { [passKey]: boolean }, starterClaimed,
credits = { brew, hatch }, offlineDouble = { cash, available }?, paidRandomAllowed, featured = { seatId x4 } }`
(`Types.ExclusiveShopView`).
`paidRandomAllowed` comes from `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` (cached
per player, default false while unknown). When false the UI hides `ServerLuckPotion`. Its card shows the potion odds
with and without the potion (tier 3+ weights x `LUCK_POTION_MULT`) behind a "Details" button.
`State.petSeats[].unlocked` is true for owned Exclusives; rows gain `productKey` (`"Seat_<id>"`) for unowned
Exclusives (`Types.PetSeatView.productKey: string?`). `offlineDouble.available` = not used yet.

## 6. Featured rotation

`shared/ExclusiveRotation.luau` (pure): `featured(weekIndex) -> { seatId x4 }`, seeded by the UTC week number, the
same on every server; 4 distinct Exclusive seats. No discount in this first version. The carousel riders show them.

## 7. World: the carousel

`WorldLayout.EXCLUSIVE_CAROUSEL` / prop spot: see §7.1 (placement). Two meshes:
`ranch_exclusive_carousel_spin` (deck, drum, poles, saddles: the `ExclusiveCarouselSpin` part, spins about its centre
line at `Config.EXCLUSIVE_SHOP.spinRpm`) and `ranch_exclusive_carousel_static` (skirt, canopy, trophy slime, crest
sign, ticket kiosk, queue rope; the kiosk's `Counter` part carries the `ShopPrompt`, stand attribute
`ShopId = "ExclusiveShop"`; an invisible flat `DeckCollider` is the floor players stand on). The client spins the carousel in the one frame loop (culled by distance)
and seats the 4 featured seat templates from `ReplicatedStorage.PetCloudMeshes` on the 8 poles (featured x2),
bobbing ±0.6 studs out of phase. Without a mesh asset (not uploaded) a simple fallback (cylinder + cone) stands in.
The prompt opens the `ExclusiveShop` panel on Featured.

### 7.1 Placement

`ExclusiveShopStand` at **bearing 112.5** (the plot 3 / plot 4 bisector), r ~94, front to the fountain, scale **0.9**
(a full-size carousel crosses the plot fronts at r 100). It completes the market row on the east ring: Upgrade Shop
34.5, Item Shop 67.5, Exclusive Shop 112.5. The Well and WellPump that stood there move to a free lawn found with
`PropClearance.conflicts`. The spot gets its `PropClearance` circle (radius from the scaled carousel), a minimap pin
(`MinimapData.SHOP_PINS`) and a `world-shops.md` §27.2 row. The kiosk sits on the carousel's front-right, angled to
the fountain, so the riders stay in view from the ring path.

## 8. UI

`ui/Panels/ExclusiveShop.luau`: direction A (tabs, card grid, detail pane; phone: bottom sheet) with B's carousel
stage behind the preview. Opens from the carousel prompt, the Skins panel's gold "Exclusive shop" well (on that seat),
and a HUD shop button. Quick-buy buttons live where the wait is: Merge panel ("Finish now", or "Use credit"), egg pad
sign / hatch prompt area ("Hatch now"), Welcome card ("Double it"), WorldShop Luck Potion row ("Buy for the server").
Buy buttons call `MarketplaceService` prompts; the panel never grants anything.
