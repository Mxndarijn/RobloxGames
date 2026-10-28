# Exclusive Shop: Robux products and passes to create

Create these on the Creator Dashboard for the Steal a Slime experience (universe 10770917350): **Monetization > Developer Products** and **Monetization > Passes**. Use the name, description and price below. Then paste each new id into the `productId` / `passId` of the same key in `src/shared/Config.luau` (`EXCLUSIVE_SHOP`), or send the list to Claude and it fills them in.

While an id is 0 the shop shows the price with "Not on sale yet". Create the **passes off sale** until `FEATURES.ExclusiveShop` is turned on: a pass on sale shows in the experience's Store tab, and it would do nothing while the flag is off. Developer Products can only be bought from inside the game, so they are safe to create now.

Prices must match the `robux` in Config (the shop shows that number).

## Developer Products: clouds, bundle, quick-buys (27)

| Config key | Name | Description | Robux | Id |
|---|---|---|---|---|
| `Seat_bubble` | Bubble cloud | An Exclusive pet cloud: your pet rides the Bubble. Yours to keep. | 99 | |
| `Seat_clam_shell` | Clam Shell cloud | An Exclusive pet cloud: your pet rides the Clam Shell. Yours to keep. | 199 | |
| `Seat_crescent_moon` | Crescent Moon cloud | An Exclusive pet cloud: your pet rides the Crescent Moon. Yours to keep. | 199 | |
| `Seat_flame_cloud` | Flame Cloud cloud | An Exclusive pet cloud: your pet rides the Flame Cloud. Yours to keep. | 199 | |
| `Seat_hoverboard` | Hoverboard cloud | An Exclusive pet cloud: your pet rides the Hoverboard. Yours to keep. | 399 | |
| `Seat_ice_cloud` | Ice Cloud cloud | An Exclusive pet cloud: your pet rides the Ice Cloud. Yours to keep. | 199 | |
| `Seat_leaf` | Leaf cloud | An Exclusive pet cloud: your pet rides the Leaf. Yours to keep. | 99 | |
| `Seat_lily_pad` | Lily Pad cloud | An Exclusive pet cloud: your pet rides the Lily Pad. Yours to keep. | 99 | |
| `Seat_magic_carpet` | Magic Carpet cloud | An Exclusive pet cloud: your pet rides the Magic Carpet. Yours to keep. | 399 | |
| `Seat_mushroom` | Mushroom cloud | An Exclusive pet cloud: your pet rides the Mushroom. Yours to keep. | 99 | |
| `Seat_pancakes` | Pancakes cloud | An Exclusive pet cloud: your pet rides the Pancakes. Yours to keep. | 99 | |
| `Seat_royal_cushion` | Royal Cushion cloud | An Exclusive pet cloud: your pet rides the Royal Cushion. Yours to keep. | 399 | |
| `Seat_star_cushion` | Star Cushion cloud | An Exclusive pet cloud: your pet rides the Star Cushion. Yours to keep. | 199 | |
| `Seat_storm_cloud` | Storm Cloud cloud | An Exclusive pet cloud: your pet rides the Storm Cloud. Yours to keep. | 199 | |
| `Seat_sunset_cloud` | Sunset Cloud cloud | An Exclusive pet cloud: your pet rides the Sunset Cloud. Yours to keep. | 199 | |
| `Seat_ufo` | UFO cloud | An Exclusive pet cloud: your pet rides the UFO. Yours to keep. | 399 | |
| `StarterBundle` | Starter bundle | The Leaf cloud for your pet and x2 income for 15 minutes. Once per player. | 149 | |
| `FinishBrew_1` | Finish brew (up to 5 min) | Finishes your merge vat brew now. The result was already decided when the brew started. | 15 | |
| `FinishBrew_2` | Finish brew (up to 30 min) | Finishes your merge vat brew now. The result was already decided when the brew started. | 35 | |
| `FinishBrew_3` | Finish brew (up to 1 hour) | Finishes your merge vat brew now. The result was already decided when the brew started. | 59 | |
| `FinishBrew_4` | Finish brew (over 1 hour) | Finishes your merge vat brew now. The result was already decided when the brew started. | 99 | |
| `HatchNow_speckled` | Hatch now: Speckled egg | Your Speckled Mystery Egg is ready to hatch now. What is inside was decided when it started. | 25 | |
| `HatchNow_shiny` | Hatch now: Shiny egg | Your Shiny Mystery Egg is ready to hatch now. What is inside was decided when it started. | 35 | |
| `HatchNow_golden` | Hatch now: Golden egg | Your Golden Mystery Egg is ready to hatch now. What is inside was decided when it started. | 45 | |
| `HatchNow_cosmic` | Hatch now: Cosmic egg | Your Cosmic Mystery Egg is ready to hatch now. What is inside was decided when it started. | 49 | |
| `DoubleOffline` | Double offline cash | Get your last welcome-back offline cash a second time. | 49 | |
| `ServerLuckPotion` | Server Luck Potion | Rarer slimes for everyone on the server: tier 3+ odds x2.5 for 5 more minutes (up to 15). | 79 | |

## Developer Products: Style and lock break (10)

| Config key | Name | Description | Robux | Id |
|---|---|---|---|---|
| `Trail_sparkle` | Sparkle trail | A sparkle carry trail that streams behind you while you carry a slime. Yours to keep. | 49 | |
| `Trail_goo_drip` | Goo Drip trail | A goo drip carry trail that streams behind you while you carry a slime. Yours to keep. | 79 | |
| `Trail_hearts` | Hearts trail | A hearts carry trail that streams behind you while you carry a slime. Yours to keep. | 79 | |
| `Trail_starfall` | Starfall trail | A starfall carry trail that streams behind you while you carry a slime. Yours to keep. | 99 | |
| `Trail_rainbow` | Rainbow trail | A rainbow carry trail that streams behind you while you carry a slime. Yours to keep. | 149 | |
| `BatSkin_lollipop` | Lollipop Bat skin | Your Bat looks like a lollipop. Same reach and timing as the normal Bat. | 99 | |
| `BatSkin_fish` | Fish Bat skin | Your Bat looks like a fish. Same reach and timing as the normal Bat. | 99 | |
| `BatSkin_foam_finger` | Foam Finger Bat skin | Your Bat looks like a foam finger. Same reach and timing as the normal Bat. | 149 | |
| `BatSkin_golden` | Golden Bat Bat skin | Your Bat looks like a golden bat. Same reach and timing as the normal Bat. | 249 | |
| `LockBreak` | Open locked door | Walk through one locked base's door for 60 seconds. The lock stays up for everyone else. | 499 | |

## Developer Products: gifts (25)

Every cosmetic is also sold as a gift for another player in the server (same price).

| Config key | Name | Description | Robux | Id |
|---|---|---|---|---|
| `Gift_Seat_bubble` | Gift: Bubble cloud | Give the Bubble cloud to another player in your server. | 99 | |
| `Gift_Seat_clam_shell` | Gift: Clam Shell cloud | Give the Clam Shell cloud to another player in your server. | 199 | |
| `Gift_Seat_crescent_moon` | Gift: Crescent Moon cloud | Give the Crescent Moon cloud to another player in your server. | 199 | |
| `Gift_Seat_flame_cloud` | Gift: Flame Cloud cloud | Give the Flame Cloud cloud to another player in your server. | 199 | |
| `Gift_Seat_hoverboard` | Gift: Hoverboard cloud | Give the Hoverboard cloud to another player in your server. | 399 | |
| `Gift_Seat_ice_cloud` | Gift: Ice Cloud cloud | Give the Ice Cloud cloud to another player in your server. | 199 | |
| `Gift_Seat_leaf` | Gift: Leaf cloud | Give the Leaf cloud to another player in your server. | 99 | |
| `Gift_Seat_lily_pad` | Gift: Lily Pad cloud | Give the Lily Pad cloud to another player in your server. | 99 | |
| `Gift_Seat_magic_carpet` | Gift: Magic Carpet cloud | Give the Magic Carpet cloud to another player in your server. | 399 | |
| `Gift_Seat_mushroom` | Gift: Mushroom cloud | Give the Mushroom cloud to another player in your server. | 99 | |
| `Gift_Seat_pancakes` | Gift: Pancakes cloud | Give the Pancakes cloud to another player in your server. | 99 | |
| `Gift_Seat_royal_cushion` | Gift: Royal Cushion cloud | Give the Royal Cushion cloud to another player in your server. | 399 | |
| `Gift_Seat_star_cushion` | Gift: Star Cushion cloud | Give the Star Cushion cloud to another player in your server. | 199 | |
| `Gift_Seat_storm_cloud` | Gift: Storm Cloud cloud | Give the Storm Cloud cloud to another player in your server. | 199 | |
| `Gift_Seat_sunset_cloud` | Gift: Sunset Cloud cloud | Give the Sunset Cloud cloud to another player in your server. | 199 | |
| `Gift_Seat_ufo` | Gift: UFO cloud | Give the UFO cloud to another player in your server. | 399 | |
| `Gift_Trail_sparkle` | Gift: Sparkle trail | Give the Sparkle carry trail to another player in your server. | 49 | |
| `Gift_Trail_goo_drip` | Gift: Goo Drip trail | Give the Goo Drip carry trail to another player in your server. | 79 | |
| `Gift_Trail_hearts` | Gift: Hearts trail | Give the Hearts carry trail to another player in your server. | 79 | |
| `Gift_Trail_starfall` | Gift: Starfall trail | Give the Starfall carry trail to another player in your server. | 99 | |
| `Gift_Trail_rainbow` | Gift: Rainbow trail | Give the Rainbow carry trail to another player in your server. | 149 | |
| `Gift_BatSkin_lollipop` | Gift: Lollipop Bat skin | Give the Lollipop Bat skin to another player in your server. | 99 | |
| `Gift_BatSkin_fish` | Gift: Fish Bat skin | Give the Fish Bat skin to another player in your server. | 99 | |
| `Gift_BatSkin_foam_finger` | Gift: Foam Finger Bat skin | Give the Foam Finger Bat skin to another player in your server. | 149 | |
| `Gift_BatSkin_golden` | Gift: Golden Bat Bat skin | Give the Golden Bat Bat skin to another player in your server. | 249 | |

## Game Passes (2, create off sale)

| Config key | Name | Description | Robux | Id |
|---|---|---|---|---|
| `Income2x` | 2x Income | Double base income from your slimes, forever. | 449 | |
| `Offline2x` | 2x Offline Earnings | Earn 50% instead of 25% of your income while you are offline. | 199 | |
