# Exclusive Shop audit: icons, previews, models

Working file for `docs/shop-preview-audit` (2026-11-04). Deposit fanfares are left out: they leave the shop on
`feat/remove-fanfares`.

Sources: `src/shared/Config.luau` (`PET_SEATS`, `PLOT_SKINS`, `PLOT_BASES`, `EXCLUSIVE_SHOP`), `src/ui/ItemIcons.luau`,
`src/ui/ExclusiveShopView.luau` (`TEXTS`), `src/shared/MeshAssets.luau`. Icons checked in a hidden, muted Studio
playtest by drawing every shop icon with the game's own `ItemIconView` (screenshot `docs/shop-audit/icons_before.jpg`).

## Today: no preview at all

The shop's detail pane shows the same icon as the card, only bigger (`Panels/ExclusiveShop.luau` `bigIcon`). There is
no 3D view and no way to see a hat on a slime, a trail behind a player, a base skin or plot base on a plot, or what a
bundle holds. `ItemIconView` already has a live-model path (`meshBuilder`, `ItemIcons.MESHES`), but `MESHES` is empty,
so nothing uses it.

Every cosmetic already has an uploaded mesh in `MeshAssets` (seats, hats, lock stoppers, Bat skins, plot skin decor,
plot base parts). So a 3D preview needs no new upload for the items that exist; it is UI work.

## Item by item

Icon source: **pic** = uploaded rendered picture, **drawn** = UI-drawn frames (`ItemIconArt`), **glyph** = the same
generic tile for every item of the kind.

| Kind | Item | Price | Shop icon | Icon verdict | Mesh in game |
|---|---|---|---|---|---|
| Bundle | Starter bundle | 149 | `Gift` pic | weak: same gift box on all 3 bundles, no hint of contents | n/a (Leaf + x2 boost) |
| Bundle | Boutique bundle | 549 | `Gift` pic | weak: same gift box | n/a (Magic Carpet + Fairground) |
| Bundle | Sky bundle | 599 | `Gift` pic | weak: same gift box | n/a (4 elemental clouds) |
| Cloud | Storm, Sunset, Ice, Flame Cloud | 199 | pic | good | uploaded |
| Cloud | Leaf, Bubble, Lily Pad, Mushroom, Pancakes | 99 | pic | good (Bubble reads as a white disc) | uploaded |
| Cloud | Star Cushion, Crescent Moon, Clam Shell | 199 | pic | good | uploaded |
| Cloud | Magic Carpet, UFO, Royal Cushion, Hoverboard | 399 | pic | good | uploaded |
| Cloud | Pumpkin (Halloween) | 249 | drawn | **placeholder**: generic white seat with a green slime | uploaded |
| Cloud | Snow Globe (Winter) | 249 | drawn | **placeholder**: same generic white seat | uploaded |
| Base skin | Fairground, Beach Hut, Space Station, Winter Cabin, Haunted Ranch | 249-399 | drawn | weak: flat box tiles, do not show the jar tower | uploaded (`plot_skin_*`) |
| Plot base | Goo Factory, Mushroom Pagoda, Carousel Tent, Space Rocket, Tree House, Lighthouse, Snow Globe | 399-599 | drawn | **placeholder**: one identical capsule shape, only the colour changes | uploaded (multi-part kits) |
| Lock style | Candy Bar, Carousel, Sleepy Guard | 79-99 | glyph | **placeholder**: three identical red padlock dots | uploaded (`lock_stopper_*`) |
| Trail | Sparkle, Goo Drip, Hearts, Starfall, Rainbow | 49-149 | drawn | ok: coloured dots behind a slime, styles barely differ | n/a (particles) |
| Hat | Party, Big Bow, Chef, Flower Crown, Top Hat, Witch | 49-99 | glyph | **placeholder**: six identical slimes in a purple hat | uploaded (`slime_hat_*`) |
| Bat skin | Lollipop, Fish, Foam Finger, Golden Bat | 99-249 | drawn | weak: recoloured bat sticks; Fish and Foam Finger look like plain bats | uploaded (`bat_skin_*`) |
| Pass | VIP, x2 income, x2 offline, Fast brew, Warm nest, Lucky Charm+, Thief radar, Auto collect | 129-599 | reused icons (crown, coin bag, moon, vat, egg, clover, thief, cash) | ok; Thief radar reuses a goal icon | n/a |
| Sub | Slime Club | 99/mo | `Daily` (calendar) | ok | n/a |
| Boost | Luck Potion, Slime Rain, Weather Totem, x2 15 min, x2 1 h | 49-179 | reused pics | ok | n/a |
| Boost | Summon the boss | 199 | `Slap` (a hand) | weak: a slap hand, not a boss | n/a |

## In game (hidden muted Studio, 2026-11-04)

Every cosmetic mesh loaded (`AssetService:CreateMeshPartAsync` on the client, 36 of 36). Screenshot:
`docs/shop-audit/meshes_ingame.jpg`.

- **The meshes are mostly good; the shop just never shows them.** Hats, lock stoppers, Bat skins, Pumpkin, Snow Globe
  and the base-skin decor all read clearly in 3D, while their shop icons are identical placeholders.
- **Weak meshes:** Bubble is a plain white flattened orb; Crescent Moon is a cream blob; Ice Cloud is a dull grey-blue
  blob; the Fairground skin decor is a thin balloon stick that will vanish at game distance.
- **The white orbs Merijn sees:** the claw show grabs a plain lilac `Ball` part (`ShopDisplayFx.makePrize`, the
  "prize capsule") for every purchase that is not a featured cloud: hats, lock styles, base skins, plot bases, Bat
  skins, trails and every pass. The claw box itself is filled with pale untextured capsule balls (part of the
  `exclusive_slime_claw_shop` mesh), and the featured Bubble seat on its pedestal looks like one more white disc
  (`docs/shop-audit/claw_box_before.jpg`).

## Fix list

| # | Fix | Kind | Needs upload |
|---|---|---|---|
| 1 | Live 3D preview in the shop's detail pane for every cosmetic (model turns on the stage; hat worn by a slime) | UI | no: meshes are uploaded |
| 2 | Card pictures for hats, lock styles, Bat skins, plot bases, base skins, Pumpkin, Snow Globe, the 3 bundles | icons | yes, 30 pictures |
| 3 | The claw grabs the item's own mesh (hat, stopper, bat, skin decor) instead of a ball; a real capsule model for the rest | world + model | the capsule mesh |
| 4 | Remake Bubble, Crescent Moon, Ice Cloud | models | yes, 3 meshes (`--update`) |
| 5 | Bundles: the pane lists what is inside, with each item's picture | UI | no |
| 6 | Passes and boosts: the pane shows your own numbers before and after (income per second, brew time) | UI | no |
