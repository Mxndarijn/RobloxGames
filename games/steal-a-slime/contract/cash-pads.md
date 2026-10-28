# 47. Cash pads: income piles up at each slime and the owner walks over it to collect

**Status:** behind `Config.FEATURES.CashPads`. With the flag off, income goes straight to cash and nothing below exists. Server-authoritative; no remote, one State field (`padCash`: the whole cash waiting on all my pads, nil with the flag off), **no save version bump** (one optional key).

## Rules (`src/shared/CashPads`, `src/server/CashPadService`)

- **Piles.** `Income.step` adds each pad slime's income (`PlayerData.slimeIncome`: rebirth, upgrades, rank, dex, boost codes, friends, ritual, Boss Champion, pets and the weekend x2 all count *as it piles up*) to `data.padCash[pad]` instead of cash. Slimes being carried away or brewing in the vat add nothing (`World.incomeSkip`).
- **Cap.** A pad stops filling at what the slime on it earns in the player's offline cap time (`Perks.offlineCap`: `OFFLINE_CAP_SECONDS` plus Night Shift). A pile above the cap (a weaker slime moved there) keeps what it has.
- **Pile belongs to the pad.** A stolen, sold, merged or moved slime leaves its pile behind; the owner can still collect it, and the next slime on that pad keeps adding to it.
- **Offline.** `Income.applyOffline` puts `Economy.offlineIncome` of each slime (`OFFLINE_RATE`, at most the offline cap) on its pad, under the same cap. The join toast and the welcome-back card (`welcomeBack.onPads = true`) say the cash waits on the cash pads.
- **Collect.** `CashPadService.touch(world, nags, userId, plotIndex, pad, now)`: the plot owner gets the pile's whole cash (`PlayerData.earn`, so `totalEarned`, goals, badges and the boards count it when collected; the fraction stays) and the `"Collect"` effect (§5.4) on their root. Anyone else gets nothing and the `"bad"` toast "Not your cash! Only the owner can collect it." at most once per `Config.CASH_PAD.NAG_SECONDS`, and only while there is a pile. A locked base changes nothing here: visitors can never collect.
- **Rebirth** (`Progression.rebirth`) clears every pile along with the cash. The Rebirth panel's "Resets" well names the cash waiting on the pads (`State.padCash`), so nobody loses it by surprise.

## World (`src/server/CashPadView`, Roblox adapter)

- On every owned plot, each unlocked pad with a slime or a pile gets a `CashPad` Part (child of `Pad_<j>`): a flat Neon gold cylinder `Config.CASH_PAD.RADIUS` across, `FRONT[floor]` studs in front of the pad centre (`CashPads.front`; the pad's -Z, towards the jar, well past the pad sign; the top jar uses a shorter distance to stay clear of the stair hole). Anchored, CanCollide / CanQuery / CanTouch false.
- Its `CashPadLabel` BillboardGui shows the pile (`CashPads.label`: "$1.2K", "FULL $3.6K" in gold at the cap, empty under $1) from `LABEL_DISTANCE` studs. After the owner collects, it shows "+$X" in green for a moment.
- Stepping on it: `ServerLoop` polls each player's `HumanoidRootPart` every `VIEW_INTERVAL` (`CashPads.touching`: flat distance up to `RADIUS + TOUCH_SLACK`, 0..`TOUCH_HEIGHT` studs above the disc). A touch counts once per step-on: standing still collects nothing more until the player steps off and back on. There is no `Touched` handler.
- Discs of plots without an owner, pads that are gone (a removed floor) or pads with neither slime nor pile are destroyed.

## Save (`SaveData`)

`padCash` is an optional dense list, entry i = the pile on pad i (0 = empty), left out when nothing is piled up. Missing / junk -> no piles; non-numbers, NaN, non-positive entries and pads past `padsUnlocked` are dropped (`CashPads.clean`). An older build ignores the key, so a rollback only loses the uncollected piles.

## Not in this version

- No tutorial step (inserting one would shift saved `tutorialStep` indices). While the tutorial runs, a toast says how to collect once $`CASH_PAD.HINT_AT` waits (once a session); the offline join toast and the counters explain it to everyone else.
