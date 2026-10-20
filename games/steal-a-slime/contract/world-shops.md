# 27. World shops: Item Shop and Upgrade Shop (`FEATURES.WorldShops`, default `true`; server + world implemented 2026-10-17, client UI pending)

**Status:** server + world side implemented (`Shared.Shops`, `server/ShopGuard`, `Actions`, `WorldProps`); the client UI is Glitch's. Merijn's HUD design (2026-10-17) drops the HUD Shop button for two in-world shops. Phoenix builds the server and world side against this section; Glitch builds the client UI. Names below are final; change them here first. Server-authoritative: the client calls `Request`, renders `State` and `ShopEvent`, never decides an outcome.

## 27.1 Split (ids are save keys / action args, never renamed; names are the exact current strings)

| Shop | Id | Name | Bought with (existing logic, reused) |
|---|---|---|---|
| ItemShop | `Lock` | "Lock base" | `Request("Lock")` (`StealService.buyLock`) |
| ItemShop | `SpeedCoil` | "Speed Coil" (once; **moved here from the Upgrade Shop 2026-10-18, Merijn: it is an item because it works while held**; still a `SpeedCoil` Tool in the Backpack, so it has a hotbar slot and shows in the inventory panel) | `BuySpeedCoil` |
| ItemShop | `LuckPotion` / `WeatherTotem` | "Luck Potion" / "Weather Totem" (`FEATURES.Consumables`, restocking; bought into a held stack, used later with `UseConsumable`, see restocking-shop.md) | `BuyConsumable(itemId, slimeId?)` (`slimeId` ignored) |
| ItemShop | `Config.PVP_TOOLS` ids | per `PVP_TOOLS[id].name` (`FEATURES.PvP`, default off; listed only when on) | `BuyPvpItem(itemId)` |
| UpgradeShop | `LockUpgrade` | "Longer locks" (5 levels) | `BuyLockUpgrade` |
| UpgradeShop | `Income` / `CarrySpeed` / `OfflineCap` / `Luck` | "Slime Snacks" / "Strong Arms" / "Night Shift" / "Lucky Charm" (`Config.UPGRADES`, rank-gated by `requires`) | `BuyUpgrade(id)` |

Rule (Speed Coil: Merijn 2026-10-18, an item because it works while held, so it counts as held): consumed / restocking things = Item Shop; permanent, saved-and-kept-on-rebirth things = Upgrade Shop. Pads (`BuyPad`) stay on the plot, not in a shop.

## 27.2 World placement (`WorldLayout.PROP_SPOTS`, bearing 0 = +Z, x = sin(b) r, z = cos(b) r, r 90, yaw = bearing so the front faces the fountain)

| Anchor (Model name, under `workspace.Map`) | Bearing / r | Notes |
|---|---|---|
| `ItemShopStand` | 67.5 / 90 | the existing `ShopStand` spot, renamed |
| `UpgradeShopStand` | **34.5** / **96** (`propSpot(34.5, true, 96)`; was 34 / 90, 18.3 studs from the Campfire / CampBench camp (`RanchProps`, 22.5 / r92); 22.5 itself fails `PropClearance`) | between plot 1 and 2 spokes, inside the clear gap (bearing 35 at r 90-98 clips the plot 2 entrance corridor); 20 studs from the Campfire; about 72 studs from the ritual meadow (348 / 93) |

Both sit beyond the ring path (outer edge r 82; lane r 64.75-71.25, gate posts to 73.75), outside every plot rect / entrance corridor, and 12 studs of `PropClearance.SPOT_RADIUS` is kept clear (add the new spot to `PropClearance` and the minimap). Mesh: each stand skins its own kit mesh (`WorldLayout.SHOP_STANDS`: mesh, scale, sign face, counter; the scale is the largest at which the Upgrade stand fits its spot): the Item Shop `ranch_item_shop`, a pink and yellow market stall full of goods with a Mystery Egg on the sign; the Upgrade Shop `ranch_upgrade_cabinet`, a blue and gold booth whose back wall is a cabinet showing the six upgrades (Slime Snacks cookie, Strong Arms dumbbell, Night Shift moon, Lucky Charm clover, Rain Magnet magnet, Longer Locks clock padlock) with level pips. The face sign text differs ("ITEM SHOP" / "UPGRADE SHOP"); each uses its one `Sign` part on its own mesh's sign face, TextScaled with 12% side padding. `Props.shopStand(shopId)` / `Props.STAND_STYLES` give the sign colours (cream text on dark wood / gold text on a navy plate) and build the Model's box exactly as the skin's box, centred on the pivot, the `Counter` on the skin's counter. With `WorldShops` off the single `ShopStand` skins `ranch_shop_stand`. `MinimapData.points()` pins both stands (`label` "Item Shop" / "Upgrade Shop", `icon` 🛒 / ⬆️, `MinimapData.SHOP_PINS`). Collision: solid counter via `MeshAssets.COLLISION` `"Hull"` for `ranch_item_shop`, `ranch_upgrade_cabinet` and `ranch_shop_stand` (docs/COLLISION.md: players must not stand inside it, blobby), MeshSwap applies it; add the entry with the code. Old model name `ShopStand` / `Constants.SHOP_STAND`: with `WorldShops` **off** `WorldProps` still places the single `ShopStand` (same Item Shop spot, `PROP_SPOTS` has no `ShopStand` entry, it uses `ItemShopStand`'s); with it on there is no `ShopStand` model. `PROP_MESHES` lists `ItemShopStand` and `UpgradeShopStand` (the mesh slot count is 392). New constants: `SHOP_STAND_ITEM = "ItemShopStand"`, `SHOP_STAND_UPGRADE = "UpgradeShopStand"`.

## 27.3 Opening
- `PrimaryPart` `Counter` of each stand holds ONE ProximityPrompt `ShopPrompt` (`Constants.SHOP_PROMPT_NAME`, kept): Item Shop `ObjectText "Item Shop"`, `ActionText "Browse items"`; Upgrade Shop `ObjectText "Upgrade Shop"`, `ActionText "Browse upgrades"`; `KeyboardKeyCode E`, `HoldDuration 0`, `MaxActivationDistance 12`. Stand attribute `ShopId` = `"ItemShop" | "UpgradeShop"` tells the client which catalog to open.
- The server connects `ProximityPrompt.Triggered` on each `ShopPrompt` to `Actions.openFromPrompt` (same checks as `OpenShop`, but not the `OpenShop` rate limit, so the client's own `OpenShop` call right after still goes through), so the shop opens on the server without any client code. The UI opens client-side (like §5.3). The server tracks the open shop through `Request("OpenShop", shopId)` (below) and sets the Player attribute `OpenShop` (string `shopId`, nil = closed).
- **Range:** `Config.SHOP_RANGE = 14` studs. Checked on the server on `OpenShop` and on **every** purchase: distance from the character `HumanoidRootPart` to the stand's `Counter` (XZ+Y) must be <= `SHOP_RANGE`, character alive. Leaving range closes the shop (`ShopEvent` `Close`, reason `"range"`), checked in the existing per-player step (`stepPlayers`, every 0.25 s while a shop is open; no new loop). The distance is 3D, HumanoidRootPart to the Counter; exactly `SHOP_RANGE` still counts as in range.

## 27.4 Remotes (names final; reuse, do not duplicate purchase logic)
- **Reused unchanged:** `Lock`, `BuyConsumable`, `BuyPvpItem`, `BuyLockUpgrade`, `BuySpeedCoil`, `BuyUpgrade`. With `WorldShops` on they additionally require an open shop of the right type and range (see 27.6); the old HUD path is described in 27.6.
- **New `Request` actions** (rate limit 0.5 s, `Validate.ACTIONS`, both in `Remotes.ACTIONS`): `OpenShop(shopId: string)` validates flag, shopId, range and sets `OpenShop`; `CloseShop()` clears it; `ShopBuy(shopId: string, itemId: string, arg: string?)` validates flag, range, that `itemId` belongs to `shopId` (`Shared.Shops`), then **delegates to the matching existing action** from the table in 27.1 (`arg` is not needed for any item). Returns `(ok, message?)` as every action; on a shop failure the result is `{ ok = false, message = <readable text>, code = <27.7 code> }` (`Types.RequestResult.code`; the same `Denied` event fires). `ShopBuy` validates in this order (`server/ShopGuard.check`): flag, shopId, item membership, open shop (`WorldShopsStrict` only), alive, range; an item whose feature flag is off (`Shops.Item.flag`) answers `Unavailable`; the delegated action keeps its own rate limit (`Busy`). `Purchased.price` is the cash the existing handler took, `level` the new level of `LockUpgrade` / `Config.UPGRADES` items. Delegated refusals map to codes by their text (`ShopGuard.classify`).
- **New RemoteEvent `ShopEvent`** (`Constants.SHOP_EVENT = "ShopEvent"`, ServerToClient, in `Remotes.DEFINITIONS`), one table arg with `kind` and `serverTime`:

| kind | Fields |
|---|---|
| `"Open"` | `shopId` (server accepted `OpenShop`) |
| `"Close"` | `shopId, reason` (`"closed" | "range" | "dead" | "flag"`) |
| `"Purchased"` | `shopId, itemId, price: number, level: number?` (new level for leveled upgrades) |
| `"Denied"` | `shopId, itemId?, code` (27.7), `message` (display text) |

Fired to the buyer only. `State` is re-sent after every purchase as today.

## 27.5 State the client reads
- **Catalog:** new pure shared module `Shared.Shops`: `SHOPS = { ItemShop = { id, name, stand, items = { { id, action, ... } } }, UpgradeShop = { ... } }` with the rows of 27.1 in display order (`items[i] = { id, name, icon, text, action, flag? }`); names / icons / text come from `Config` (`UPGRADES`, `CONSUMABLES`, `PVP_TOOLS`) and `ShopCatalog` strings so there is one source. `Shops.items(shopId, features)` filters by flags. Also `Shops.shopOf(itemId)`.
- **Live data (existing `State`):** `State.shop` (prices, levels, `owned`, §5.1), `State.upgrades`, `State.consumables` (`left` / `max` / `restockAt`), `State.pvp`, `cash`. No new State field. Player attribute `OpenShop` (see 27.3) is a read-only hint for other clients.

## 27.6 Feature flag `FEATURES.WorldShops` (default `true` for server / world)
- On: both stands exist, `OpenShop` / `CloseShop` / `ShopBuy` / `ShopEvent` work, range is validated. The existing buy actions called **without** an open matching shop answer `"open the <Item|Upgrade> Shop first"` (`code "NotOpen"`) **only once** `FEATURES.WorldShopsStrict` (on since HUD v2, the HUD Shop button is gone).
- **Plot pad exception:** the owner-only plot prompts (`LockPrompt` "Lock", `BuyPadPrompt` "BuyPad", `MergePrompt` "Merge") are not shop purchases and never hit the strict gate: `Actions.handlePlotPad` checks the character is within `PlotPadGuard.range()` (`Config.PLOT_PAD_PROMPT_DISTANCE` + `PLOT_PAD_RANGE_SLACK`) of THAT prompt's own part (`ctx.plotPadAccess`), else `"walk closer to your lock pad"`. Under strict, `Request("Lock")` (HUD Lock button) is also allowed while standing at the owner's own LockButton; anywhere else it needs the Item Shop as before. `ShopBuy` is unchanged.
- Off: no stands, `OpenShop` / `ShopBuy` answer `"the shops are closed"` (`FlagOff`), no `ShopEvent`, no attribute; the single `ShopStand` and HUD Shop panel behave exactly as before.
- Old HUD **Shop** button: removed in HUD v2; `WorldShopsStrict` is on. The `ShopStand` / `ShopPrompt` prompt still opens the combined panel.

## 27.7 Deny codes (`ShopEvent` `Denied.code`, also the `Request` failure `message` prefix is the readable text)
`FlagOff` (shops closed / feature off), `BadShop` (unknown shopId), `NotInShop` (itemId not sold there), `NotOpen` (strict mode: shop not open), `OutOfRange` (> `SHOP_RANGE` or no character), `Dead` (character dead; added in the implementation, the contract had no code for "alive"), `NoCash`, `Maxed` (upgrade at max level / Speed Coil owned), `Locked` (rank `requires` / PvP gate), `SoldOut` (consumable stock 0), `Owned` (already owned: PvP item or a better tier), `BadTarget` (spray needs an owned idle slime; now answered when the item is used (the UseConsumable action), not by the purchase), `Busy` (rate limit), `Unavailable` (anything else the delegated action refuses; the original text is in `message`).
