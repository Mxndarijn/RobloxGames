# Steal a Slime: analytics events

What the game sends to Roblox analytics and where to read it. The source of truth for names is
`GameAnalytics.CATALOG` in [src/server/GameAnalytics.luau](../src/server/GameAnalytics.luau). Keep names and step order
stable between versions, or the before/after comparison on the dashboard breaks.

All events go out from the server (Roblox drops client events) and only from the published game (Roblox drops Studio
events). Charts take up to 24 h to fill; **View Events** on each dashboard page shows the latest events within minutes.
Creator Dashboard → the game → Analytics.

## How it works

- Game systems queue `World.track(world, userId, { op, name, ... })` into the outbox, next to toasts and effects.
- `Outbox` hands each call to `GameAnalytics.play`, which calls the shared tracker (`shared/luau/src/analytics`).
- The tracker keeps names to the catalog and stays under Roblox's rate limit (120 + 20 × players requests a minute;
  it uses 80 %). Frequent things (income, merges, refused steals or buys) are added up and sent once a minute per
  player, and on leave.
- In Studio, the calls go to a recorder. Set the workspace attribute `AnalyticsLog = true` to print them as
  `[Analytics] ...` in the output.

## Funnels (Analytics → Funnels)

| Funnel | Steps | Who |
|---|---|---|
| Onboarding | 1 Joined, 2–9 the tutorial steps (Grab, Deposit, Lock, Leaderboard, Guide, BuyPad, Merge, BuyItem), 10 Done | Only players who have not finished the tutorial; Joined only for a fresh save |
| Shop | 1 Opened, 2 Tried, 3 Bought | One session per shop visit; custom field = shop or item |

The biggest drop between two onboarding steps is the first thing to fix. A skipped tutorial logs `TutorialSkipped`
with the step it was on.

## Economy (Analytics → Economy)

One currency, `Cash`. The transaction type says where cash came from or went:

- **Sources:** Income (cash pads and passive income, batched), Offline, Sale, Daily, Quest, Code, Goal,
  DexMilestone, Robux.
- **Sinks:** WildSlime (buying from the lane; field = tier), Pad, SpeedCoil, Upgrade, Consumable, PvpItem, Shop
  (anything bought in a shop; sku = item), Rebirth (cash reset), Brew, Hatch, Credit.

Request actions are measured as the cash change around the action (`GameAnalytics.afterAction`). An action that moves
cash and is not listed in `GameAnalytics.TRANSACTIONS` is not tracked: add it there. Roblox groups transaction types
past 20 as "Other"; the catalog spec checks the count.

## Progression

`Rebirth`: level = rebirth count, level name = rank title.

## Custom events (Analytics → Explore)

| Event | When | Value | Fields |
|---|---|---|---|
| SlimeCaught | a wild slime reached the plot | | tier |
| SlimeSold | sold | | tier |
| StealStarted / StealDone | picked up / delivered someone's slime | | tier |
| StealFailed | lost on the way | | reason (slap, drop, left, unsaved, guard) |
| StealBlocked | refused at the start (batched) | count | reason |
| Merged | brew collected (batched) | count | tier of the result |
| RecipeFound | first brew of a recipe | | recipe |
| SpeciesFound | new SlimeDex species | species owned | |
| EggHatched | Mystery Egg hatched | | tier |
| BossHits | every player online when a boss fight ends | hits | outcome, joined yes/no |
| BossWon | carrier of a won boss | | species |
| ShopDenied | shop buy refused (batched) | count | shop, reason, item |
| RobuxPurchase | Developer Product granted | Robux | product, kind |
| GamePassBought | Game Pass bought in game | | pass |
| DailyClaimed / QuestClaimed / CodeRedeemed | claimed | | |
| SessionMinutes | on leave | minutes | rank, average server size (Alone, 2-3, 4-5, 6+), first visit or later |
| RebirthHours | on rebirth | total hours played | rebirth number |
| SlimeLost | the owner's side of StealDone | | tier |
| LeftAfterRobbed | left within 5 min of a SlimeLost | minutes since the loss | slimes lost this session (1, 2-3, 4+) |
| FirstTime | once per player, ever: Sell, Steal, Robbed, Rebirth, Boss (hit at least once), Obby (finished), Egg | minutes played until then | which |
| RobuxPrompt | a Robux prompt closed (product, Game Pass or subscription) | | item, bought yes/no |
| BrokeTopUp | a player with no slimes and too little cash got the broke top-up (a custom event, not an economy source: the 20 transaction names are taken) | cash given | top-ups this session (1, 2, 3+) |

## Why players leave: what to read after a release

- **Does being robbed drive players out?** Compare `LeftAfterRobbed` with `SlimeLost`, per day. A high share means
  steals feel too harsh.
- **Do players reach the fun after the tutorial?** Unique players per `FirstTime` field against onboarding `Done`.
  The value shows how many minutes it took. A step few players reach is the next target.
- **Are servers too empty?** Split `SessionMinutes` by server size. Short sessions in `Alone` servers point at
  matchmaking or server size, not at the game.
- **First visits vs. returning players:** split `SessionMinutes` by `Visit - First` / `Visit - Later`.
- **Do players get stuck broke?** `BrokeTopUp` per day against unique players. Many `TopUps - 2` / `3+` means
  players lose everything again soon after the top-up (stealing too harsh, or the top-up too small).
- **Do offers convert?** `RobuxPrompt` per item: `Bought - yes` against all. Many prompts and few buys = price or
  offer problem; few prompts = players don't find the shop. Subscriptions report "tried to buy" as yes (Roblox
  gives no more than that).

`FirstTime` is remembered in the save (`firsts`), so it fires once per player. Saves from before this release start
with none: a returning tester logs their first times again.

`RebirthHours` checks the economy sim's pacing (SLIME-ECONOMY.md §7.2: rebirth 1 at 0.5 h, 3 at 2.2 h, 6 at 7 h,
10 at 17 h). It reads `stats.playSeconds`, which only started counting with this release: for players who played
before, it is too low. Read it for players whose first rebirth came after the release.

## Adding an event

1. Add the name to `GameAnalytics.CATALOG` (at most 100 custom events, 10 funnels, 3 custom fields).
2. Queue it with `World.track` where it happens, from server code.
3. Cover it in `tests/GameAnalytics.spec.luau`; its harness records names missing from the catalog in `drops`, so
   assert `#h.drops == 0`.
4. Use custom fields for categories (tier, item, reason) instead of new event names. Keep field values to a small
   set: no ids, no player names, no numbers that grow.
