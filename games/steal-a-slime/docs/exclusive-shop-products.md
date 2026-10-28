# Exclusive Shop: Robux products and passes to create

Create these on the Creator Dashboard for the Steal a Slime experience (universe 10770917350): **Monetization > Developer Products** and **Monetization > Passes**. Use the name, description and price below. Then paste each new id into the `productId` / `passId` of the same key in `src/shared/Config.luau` (`EXCLUSIVE_SHOP`), or send the list to Claude and it fills them in.

While an id is 0 the shop shows the price with "Not on sale yet". Create the **passes off sale** until `FEATURES.ExclusiveShop` is turned on: a pass on sale shows in the experience's Store tab, and it would do nothing while the flag is off. Developer Products can only be bought from inside the game, so they are safe to create now.

Prices must match the `robux` in Config (the shop shows that number).

## Developer Products (27)

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

## Game Passes (2, create off sale)

| Config key | Name | Description | Robux | Id |
|---|---|---|---|---|
| `Income2x` | 2x Income | Double base income from your slimes, forever. | 449 | |
| `Offline2x` | 2x Offline Earnings | Earn 50% instead of 25% of your income while you are offline. | 199 | |
