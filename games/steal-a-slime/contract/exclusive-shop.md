# 47. Exclusive Shop: Robux purchases, the Golden Jar Boutique, quick-buys (2026-10-28)

**Status:** live, no feature flag. Approved
by Merijn: the jar shop model (`shared/modeling-kit/models/exclusive_jar_boutique.py`), the UI direction A with B's
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
- `passes` (Game Passes, keyed by pass key, shown by `order`): `VIP`, `Income2x` 449 (`incomeMult = 2`), `Offline2x` 199
  (`offlineRate = 0.5`), `FastBrew`, `WarmNest`, `LuckyCharmPlus`, `ThiefRadar` (§13). `subscriptions`: `SlimeClub` (§13).
  Server boosts and comforts: §14.
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
   `UseCredit(kind: string, target: (string | number)?)` 0.5 s: spends a
  brew credit on the running brew, a hatch credit on egg `target` (nil = the egg closest to ready) or a lock break
  credit on plot `target` (§11); flag off
  → "the Exclusive Shop is off". No action prompts purchases: the client calls
  `MarketplaceService:PromptProductPurchase` / `PromptGamePassPurchase` itself with ids from Config.
- **Studio:** `StudioHooks.grantProduct(userId, productKey)` / `setPass(userId, passKey, owned)` /
  `setPaidRandomAllowed(userId, allowed)` run the same PurchaseService paths (receipt id `studio-<guid>`, grant,
  save; Studio + memory store only, no remote). They set player attributes (`PcwGrantProduct`, `PcwPass` =
  `"<key>=true|false"`, `PcwPaidRandom`) the server applies, so Studio MCP `execute_luau` can call them
  (`require(game.ServerScriptService.Server.StudioHooks)`). `grantProduct` takes every product key (`Trail_*`,
  `BatSkin_*`, `LockBreak`, `Gift_*`); `lockBreak(userId, plotIndex)` (`PcwLockBreak`) and `gift(userId, itemKey,
  targetUserId)` (`PcwGift` = `"<itemKey>@<targetUserId>"`) aim first, then grant the same way.

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
same on every server; 4 distinct Exclusive seats. No discount in this first version. The jar shop shows the first 3 (§7).

## 7. World: the Golden Jar Boutique

`WorldLayout.EXCLUSIVE_JAR` (placement: §7.1), built by `Props.exclusiveJar`, placed by `server/WorldProps` only with
the flag on. The shop is the game's own goo jar made premium (`shared/modeling-kit/models/exclusive_jar_boutique.py`):
a glass jar with gold bands on a wooden plinth ringed with goo, a goo dome with a gold lid and the trophy slime, three
goo pedestals inside, and a wooden shop front built into the jar's front (counter, striped lilac / butter awning, the
"EXCLUSIVE" sign). Two kit meshes, each in a `MeshAsset` slot of the `ExclusiveShopStand` Model:
- `exclusive_jar_boutique` (`Shop`): everything solid. Decor (no `MeshAssets.COLLISION` entry): the stand-in plinth,
  glass, counter and frame posts stay solid under it.
- `exclusive_jar_boutique_glass` (`Glass`): the jar wall, worn like the goo jar tower's glass (`MeshMaterial` =
  `WorldLayout.JAR_GLASS_MATERIAL`, `MeshTransparency` = `WorldLayout.JAR_GLASS_MESH_TRANSPARENCY`, no shadow).

The kit's points (`out/exclusive_jar_boutique_layout.json`: glass origin, the 3 display spots, counter top and size,
sign face centre and size, footprint radius, the ground over the mesh bottom) live once in `WorldLayout.EXCLUSIVE_JAR`;
`WorldLayout.jarPoint` turns one into the stand's frame (front -Z, origin on the ground). The `Counter` (PrimaryPart,
solid, its top the kit's counter top) carries the `ShopPrompt`; the stand has `ShopId = "ExclusiveShop"`
(`Constants.EXCLUSIVE_SHOP_ID`, `ShopGuard.PANEL_SHOPS`). The prompt opens the `ExclusiveShop` panel on Featured. The
`Sign` part just in front of the kit's sign face carries the lilac "EXCLUSIVE" jelly sign (`Props.standSign`,
`Props.JAR_SIGN`).

Until the meshes are uploaded a primitive jar stands in (`MeshStandIn`, hidden by `server/MeshSwap` once its mesh
loads), SmoothPlastic only, in the kit's colours (`Props.JAR_COLORS`): wood plinth with a mint goo top, light mint
glass (`Props.JAR_GLASS_TRANSPARENCY`), two gold bands, a mint goo dome, a gold lid and a butter slime, the wooden
counter with a lilac band and a gold medal, two posts and a beam, the striped awning with scallops, the gold sign board
with its lilac face, and two lanterns.

**Displays:** the client (`visuals/client/ShopDisplayFx`, in the one frame loop, culled at
`Config.EXCLUSIVE_SHOP.drawDistance`) floats a clone of each of the week's first 3 featured seat templates
(`ReplicatedStorage.PetCloudMeshes`, `ExclusiveRotation.featured`) over the 3 pedestals, scaled to
`EXCLUSIVE_JAR.displayWidth`, each slowly turning (`displayRpm`) and bobbing up to `displayBob` studs over
`displayBobSeconds`, a third of a cycle apart, on the server clock (pure pose maths: `visuals/shared/ShopDisplay`). A
seat without a template shows a small lilac cloud until its template arrives.

### 7.1 Placement

`ExclusiveShopStand` at **bearing 112.5** (the plot 3 / plot 4 bisector), **r 93.3**, front to the fountain, **scale
1**: at full size its footprint clears the ring path and both plot fronts for r 92.3-94.35 (`PropClearance.conflicts`);
93.3 is the middle. It completes the market row on the east ring: Upgrade Shop 34.5, Item Shop 67.5, Exclusive Shop
112.5. The Well and WellPump stand by the Upcoming Events board (`RanchProps`, 211.75 / 92 and 216.25 / 93). The spot's `PropClearance`
circle is the kit's footprint radius at the stand's scale; it has a minimap pin (`MinimapData.SHOP_PINS`, 👑, only with
the flag on) and a `world-shops.md` §27.2 row.

## 8. UI

`ui/Panels/ExclusiveShop.luau`: direction A (tabs, card grid, detail pane; phone: bottom sheet) with B's carousel
stage behind the preview. Opens from the jar shop's prompt, the Skins panel's gold "Exclusive shop" well (on that seat),
and a HUD shop button. Quick-buy buttons live where the wait is: Merge panel ("Finish now", or "Use credit"), egg pad
sign / hatch prompt area ("Hatch now"), Welcome card ("Double it"), WorldShop Luck Potion row ("Buy for the server").
Buy buttons call `MarketplaceService` prompts; the panel never grants anything.

## 9. Carry trails

`Config.EXCLUSIVE_SHOP.trails`: five trails (`sparkle`, `goo_drip`, `hearts`, `starfall`, `rainbow`), each sold as
`Trail_<id>` (grant kind `trail`). Save: `ownedTrails: { string }`, `trail: string?` (equipped; cleaned on load: unknown /
unowned ids dropped). Request `EquipTrail(trailId: string)` ("" = none), 0.5 s. Player attribute `CarryTrail` = the
equipped id while the flag is on. The client draws it behind the player **only while they carry a slime** (wild or stolen):
a Roblox `Trail` plus particles in the trail's colours and style, in the one frame loop, culled by distance. Rule: a trail
is never transparent, tiny or in front of the carried slime (it makes a thief easier to spot, never harder).

## 10. Bat skins

`Config.EXCLUSIVE_SHOP.batSkins`: four skins (`lollipop`, `fish`, `foam_finger`, `golden`), sold as `BatSkin_<id>`.
Save: `ownedBatSkins: { string }`, `batSkin: string?`. Request `EquipBatSkin(skinId: string)` ("" = default Bat).
`BatTool.give` reads the equipped skin: the Handle wears that skin's mesh (`MeshAssets` `bat_skin_<id>`); everything that
decides a hit (reach `SLAP_REACH`, cooldown, `BatRules.pickTarget`, knockback) is unchanged and never reads the skin.
A skin without an uploaded mesh shows the default Bat. Player attribute `BatSkin` = the equipped id while the flag is on;
when it changes the server gives the player a fresh Bat with that look (held again if it was held).

## 11. Open locked door (lock break)

`LockBreak` (499 R$, grant kind `lockBreak`). The thief aims first: `AimLockBreak(plotIndex: number)` (0.5 s), refused
unless that plot is someone else's, locked now, not in its breather lock (`SLIME_GUARD.BREATHER_SECONDS`) and the owner is
not the buyer's friend-guest. The grant gives the buyer a pass for `lockBreak.seconds` (60): they pass that plot's
LockBarrier like a guest (`PlotLockGuard` / `PlotGuests` path), only them, only that plot, only until it ends. The lock
itself stays up for everyone else and its timer is unchanged; the owner is notified "<name> broke into your base!".
Stealing inside still goes through every SlimeGuard check. A grant whose aimed lock has ended (or no aim) becomes
`lockBreakCredits += 1`, spent with `UseCredit("lockBreak", plotIndex)`. Save: `lockBreakCredits: number` (0..creditMax).
The pass itself is runtime only; it pauses while the base is in a breather lock and ends early if the plot changes owner.
A buyer still inside when it ends or pauses is let out like a former guest and is never a locked-base intruder. The
stopper pair, the plot's `Guests` attribute and the Steal prompts' `GuestsOnly` list include the buyer while it runs. UI: on a locked base's door a thief sees "Open locked door · R$499" (or "Use lock break").

## 12. Gifts

Every cosmetic (`Seat_*`, `Trail_*`, `BatSkin_*`) also sells as `Gift_<key>` (same price, grant kind `gift`). The buyer
picks a player in the server: `AimGift(itemKey: string, targetUserId: number)` (0.5 s; refused for yourself, a player not
in the server, or one who already owns it). The grant gives the item to the aimed target (their save, then their own save
now) and notifies both ("<name> gave you <item>!"). If the target left or already owns it by then, the buyer keeps a gift
credit (`giftCredits: { string }`, item keys, at most `gift.creditMax`), sent later with `SendGift(itemKey, targetUserId)`.
The target's save goes through the receipt's own save (`Persistence.save`, session-locked) before the gift counts; a
failed save takes the item back and leaves the credit. With the credits full the receipt is not processed yet.
Passes, boosts, quick-buys and lock breaks are never giftable. UI: a "Gift" button next to Buy on every cosmetic opens a
player picker (friends first).

State (`ExclusiveShopView`): `trails`, `trail`, `batSkins`, `batSkin`, `lockBreak`, `lockBreakCredits`, `giftCredits`.
Save version 11 (`SaveData.migrateV10`).

## 13. More passes and the Slime Club

Each pass field is one effect (`Config.ExclusivePass`), applied by `Purchases.applyPasses` into runtime `data.pass*`
fields (never saved):
- `VIP` 599: `incomeMult = 1.1` (multiplies with Income2x), a gold VIP tag over the head and in chat, and once per UTC
  day a free server Luck Potion: Request `ClaimPerk("vipPotion")` (1 s; refused for non-VIPs and where paid random
  items are restricted). Save: `perkDays.vipPotion` (UTC day number; no version bump).
- `FastBrew` 249: `brewFactor = 0.5`, every merge brews in half the time (`Perks.brewFactor`, stacks with Quick Brew).
- `WarmNest` 129: pad eggs incubate at `WARM_SPEED` while the owner is away from home too (`MysteryEgg.step`).
- `LuckyCharmPlus` 249: `luckBonus = 0.05` on the Lucky Charm (wild deposits only, as before). A paid probability
  modifier: hidden where paid random items are restricted; its pane shows the player's chance with and without it
  (`State.exclusiveShop.luck = { base, bonus }`).
- `ThiefRadar` 149: `server/ThiefRadar` reads SlimeGuard's plot visits once a second; `State.exclusiveShop.radar` lists
  the userIds inside your base (friends the base lets in left out, at most `radar.maxShown`). An away owner is told
  once per visit. The client gives them an "IN YOUR BASE" ping and, with no theft running, a "Visitor" arrow. Information only.
- `SlimeClub` subscription (`subscriptions.SlimeClub`, `subscriptionId` "EXP-..." or "" = not created, 99 R$/month):
  checked on join and on `Players.UserSubscriptionStatusChanged` (`GetUserSubscriptionStatusAsync`, server), prompted
  with `PromptSubscriptionPurchase`. Benefits: a CLUB tag, and once per UTC day +1 brew and +1 hatch credit
  (`Purchases.stepDaily`, `perkDays.club`). Studio: `StudioHooks.setSubscription(userId, key, active)` (`PcwSubscription`).
- Player attribute `Member` (`Constants.MEMBER_ATTRIBUTE`): "vip" / "club" (VIP wins); `ui/MemberTags` draws the chip
  (and the chat prefix with TextChatService); `server/MemberChatTags` sets the legacy chat's speaker "Tags" (the game
  runs LegacyChatService). Studio: SlimeUI `PcwOpen` = "ExclusiveShop:<Tab>" opens the shop on that tab. State: `subscriptions`, `vipPotion`, `luck`, `radar`.

## 14. Server boosts and comforts

Developer Products; a grant that can't apply now is kept as a credit (`data.credits.rain|boss|totem|snack`, 0..creditMax,
no version bump), spent with `UseCredit(kind, target?)` or the shop's "Use credit".
- `SlimeRain` 179: `Spawner.forceRain` for the server; refused during rain or a boss and within
  `serverBoosts.rainCooldown` (20 min) of the last paid rain (`world.paidRainAt`). Paid probability modifier: hidden where restricted.
- `SummonBoss` 199: `nextBossAt = now + BOSS.WARNING_SECONDS`; refused with a boss on, one already due, rain in the way
  (`BossEvent.rainBlocks`) or within `summonCooldown` (`world.summonedAt`).
- `WeatherTotem` 59: the Item shop totem's weather is next (`ctx.requestWeather`); hidden where restricted.
- `IncomeBoost15` 49 / `IncomeBoost60` 129: x2 into the capped code boost (`Codes.addBoost`).
- `KeepStreak` 25: while `State.exclusiveShop.streakKeepable` (streak >= 2, last claim before yesterday) sets
  `daily.lastDay` to yesterday so today's claim continues the streak. Sold on the Daily reward card.
- `GrowthSnack` 19: one slime grows `growthSnackSeconds` (3 h). `AimSnack(slimeId)` (0.5 s) names it before the prompt,
  else the least grown pad slime. Sold on the slime's pad card (the hatch key: an egg never grows).
State: `credits` (all six kinds), `serverBoosts = { rain, boss }` (could start now), `streakKeepable`.

## 15. Base skins, lock styles, fanfares, hats, seasons and bundles

Cosmetics only; each also sells as a gift (`Gift_<key>`). Save (no version bump): `ownedStyles = { [kind]: { id } }`
and `wornStyles = { [kind]: id }` for kinds `fanfare`, `lockStyle`, `hat` (worn) and `plotSkin` (owned; worn as
`plotSkin`). `deserialize` drops unknown ids and worn ids that are not owned; owned styles load before the plot skin.
Request `EquipStyle(kind, id)` (0.5 s; "" = take off). State: `exclusiveShop.styles`, `worn`, `seasons`.
- **Base skins** (`Skin_<id>`, `Config.PLOT_SKINS[].exclusive`): Fairground 299, Beach Hut 249, Space Station 399,
  Winter Cabin 249, Haunted Ranch 299 (Halloween). `PlotSkins.unlocked` = owned; equipped with `EquipPlotSkin`. The
  tower meshes are kit themes (`models/_goo_jar_themes.py`, `goo_jar_*@<id>`, uploaded; MeshAssets block from
  `tools/goo_jar_theme_assets.py`). The Skins menu shows an unowned one with a gold "Exclusive" and
  "Only in the Exclusive shop.".
- **Lock styles** (`LockStyle_<id>`, `EXCLUSIVE_SHOP.lockStyles`, kit `lock_stopper_<id>`, the classic stopper's box):
  the owner's worn style is Plot attribute `LockStyle`; MeshSwap shows its stopper on `StopperShut` only (the door
  parked open keeps the classic plug, so the style's red reads "locked" only when locked). Collision is unchanged.
- **Fanfares** (`Fanfare_<id>`, `EXCLUSIVE_SHOP.fanfares`): on every deposit (wild, stolen, boss) `Carry.fanfare`
  emits the worn one's `Effect` (`Effects.BURSTS.Fanfare_<id>`, ≤ 2 s) on the slime.
- **Slime hats** (`Hat_<id>`, `EXCLUSIVE_SHOP.hats`, kit `slime_hat_<id>`): Plot attribute `SlimeHat`; the client
  (`ui/SlimeHatsFx`) welds the template from `ReplicatedStorage.SlimeHatMeshes` (`MeshSwap.publishHatTemplates`) on
  top of the visible `Mesh` of every non-egg slime in State "Pad" of that owner. The hat belongs to the pad: a carried or stolen slime has none.
- **Seasons** (`EXCLUSIVE_SHOP.seasons`, `shared/Seasons`, UTC month-day windows): halloween 10-15..11-07 (Pumpkin
  seat, Haunted Ranch, Witch Hat), winter 12-01..01-07 (Snow Globe seat). Out of season an unowned seasonal item is
  not shown (shop, Skins menu, `PetSeats.view` / `PlotSkins.view` with `now`) and never featured; owners keep it.
- **Bundles** (grant kind `pack`, owned items skipped): `BoutiqueBundle` 549 (Magic Carpet, Fairground, Confetti),
  `SkyBundle` 599 (Storm, Sunset, Ice, Flame clouds). Shown in Featured; "Owned" once everything is.
