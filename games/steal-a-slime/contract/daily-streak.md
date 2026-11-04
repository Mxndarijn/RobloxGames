# 54. Daily streak: 30 days of rewards, with skins you only get here

The daily login reward is a 30-day streak. Most days pay cash, and the other days give an item, a boost or a skin.
A missed day starts the streak again at day 1. Skins you have earned stay yours.

## Rule (`src/shared/DailyRewards`, pure)

- `Config.DAILY_REWARDS` lists the 30 days in order (`Config.DAILY_STREAK_CAP` = 30). Each entry is one reward:
  - `{ kind = "cash", amount }`: `amount` × the rebirth multiplier, floored.
  - `{ kind = "egg" }`: a Mystery Egg.
  - `{ kind = "boost", mult, minutes }`: an income boost (`Codes.addBoost`, the same as code and quest boosts).
  - `{ kind = "consumable", id, count? }`: `count` (default 1) of a `Config.CONSUMABLES` item added to the held stack.
  - `{ kind = "trail", id }`: a daily carry trail (below).
  - `{ kind = "seat", id }`: a daily pet seat (below).
- **Day of a streak:** `((streak - 1) % DAILY_STREAK_CAP) + 1`. After day 30 the streak keeps counting and the days
  repeat. `daily.streak` in the save is unchanged: `{ lastDay, streak }`. A claim the day after the last claim adds 1;
  anything else starts at 1. The Keep my streak product (§47) works as before.
- **What a day actually gives** (`DailyRewards.resolve(data, day, ctx)`): the listed reward, unless it can't be used:
  - A trail or seat the player already owns gives a Mystery Egg instead.
  - An egg when `FEATURES.MysteryEggs` is off, or the plot has no free pad, gives `DAILY_FALLBACK_CASH` × the rebirth
    multiplier instead.
  - A consumable when `FEATURES.Consumables` is off, a Weather Totem when `FEATURES.Weather` is off, or a stack that
    would go over `CONSUMABLE_HELD_MAX` gives that fallback cash too.
- **The egg:** its kind is rolled with the fountain's weights, but only among the kinds the player's rebirths may grab
  (`EggKind.rebirths`). Then the slime inside is rolled as for a wild egg. It is added to the first free pad and starts
  incubating at once.

## Daily-only cosmetics

- **Trails:** `Config.CARRY_TRAILS` entries with `daily = true` and no `robux`. They are not products and not gifts
  (no `Trail_<id>` / `Gift_Trail_<id>`). Owning one works like a bought trail: `ownedTrails`, `EquipTrail`, the
  `CarryTrail` attribute. The Exclusive shop's Style tab lists a daily trail only once it is owned, so it can be worn.
  The first two are Mint Fizz (sparkle style) and Sunbeam (stars style).
- **Seats:** `Config.PET_SEATS` entries with `unlock = { kind = "daily", day }`. They are unlocked once their id is in
  `ownedSeats` (the same list Exclusive seats use, kept by `SaveData.cleanOwnedSeats`). They are not products.
  A seat may carry `tint` (RGB 0..255): its template is `<mesh>_<id>` (`PetSeats.templateName`), a copy of the
  mesh's MeshPart with `Color` set to the tint, so one mesh wears several colours. The first two are Golden Cloud and
  Midnight Cloud (`pet_cloud` tinted). The Skins menu's Cloud tab says "Daily streak day N." for a locked one.
- No save version change: `ownedSeats` now also keeps daily seat ids, and `ownedTrails` keeps any `CARRY_TRAILS` id.

## Remote

`Request("Daily")` (no arguments, unchanged) claims today's reward. It fails with "already claimed today". The
toast names the reward: "Day 7: Mint Fizz trail!", "Day 3: +$1,000".

## State

`daily: DailyView`:

```luau
type DailyReward = {
	day: number,       -- 1..DAILY_STREAK_CAP
	kind: string,      -- "cash" | "egg" | "boost" | "consumable" | "trail" | "seat" (after the swaps above)
	label: string,     -- "$1,000", "Mystery Egg", "2x income 15m", "2 Luck Potions", "Mint Fizz trail"
	icon: string,      -- ItemIcons id: "Cash", "MysteryEgg", "Boost_Code", "Consumable_<id>", "Trail_<id>", "PetSeat_<id>"
	amount: number?,   -- cash days: the cash it pays
	skin: boolean,     -- a trail or seat (drawn as the big tile)
}
type DailyView = {
	available: boolean,
	streak: number,          -- the stored streak (of the last claim)
	day: number,             -- the day the pending claim pays; when nothing is pending, the day the last claim paid
	amount: number,          -- today's cash (0 on a day that is not cash)
	reward: DailyReward,     -- what `day` gives
	track: { DailyReward },  -- 7 days around `day`: the week it falls in (1-7, 8-14, 15-21), else days 24-30
	nextSkin: DailyReward?,  -- the next trail or seat day after `day` that the player doesn't own yet
}
```

The client draws only what `State.daily` says; it never works out a reward itself.

## Card (`Welcome` card, §24)

The daily row shows the 7 tiles of `daily.track`, each with its icon and label. The last tile is always a skin day (7, 14, 21 or 30) and stays the wide one, a line "Day N of 30"
and, when there is one, "Next skin: <name> on day N". The main button reads "Claim <label>".
