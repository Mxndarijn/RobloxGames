# 49. Cash pads: income piles up on a gold coin at each slime and the owner walks over it to collect

**Status:** behind `Config.FEATURES.CashPads`. With the flag off, income goes straight to cash and nothing below exists. Server-authoritative; no remote, one State field (`padCash`: the whole cash waiting on all my pads, nil with the flag off), **no save version bump** (one optional key).

## Rules (`src/shared/CashPads`, `src/server/CashPadService`)

- **Piles.** `Income.step` adds each pad slime's income (`PlayerData.slimeIncome`: rebirth, upgrades, rank, dex, boost codes, friends, ritual, Boss Champion, pets and the weekend x2 all count *as it piles up*) to `data.padCash[pad]` instead of cash. Slimes being carried away or brewing in the vat add nothing (`World.incomeSkip`).
- **No cap.** A pad keeps filling for as long as the player is online.
- **Pile belongs to the pad.** A stolen, sold, merged or moved slime leaves its pile behind; the owner can still collect it, and the next slime on that pad keeps adding to it.
- **Offline.** `Income.applyOffline` puts `Economy.offlineIncome` of each slime (`OFFLINE_RATE`, for at most the offline cap time: `Perks.offlineCap`, `OFFLINE_CAP_SECONDS` plus Night Shift) on its pad. The join toast and the welcome-back card (`welcomeBack.onPads = true`) say the cash waits on the cash pads.
- **Collect.** `CashPadService.touch(world, nags, userId, plotIndex, pad, now)`: the plot owner gets the pile's whole cash (`PlayerData.earn`, so `totalEarned`, goals, badges and the boards count it when collected; the fraction stays) the `"Collect"` effect (§5.4) on their root, and a Notify with the soft `"CashPadCollect"` coin sound (only they hear it, once per collect; volume and pitch in `ui/Sounds`). Anyone else gets nothing and the `"bad"` toast "Not your cash! Only the owner can collect it." at most once per `Config.CASH_PAD.NAG_SECONDS`, and only while there is a pile. A locked base changes nothing here: visitors can never collect.
- **Rebirth** (`Progression.rebirth`) clears every pile along with the cash. The Rebirth panel's "Resets" well names the cash waiting on the pads (`State.padCash`), so nobody loses it by surprise.

## World (`src/server/CashPadView`, Roblox adapter)

- On every owned plot, each unlocked pad with a slime or a pile gets a raised gold coin, visible to everyone: a `CashPad` Part (child of `Pad_<j>`, the printed top) on a slightly wider `Base` (the raised edge). Per floor (`CashPads.floorLook`, `Config.CASH_PAD`): `DIAMETER` studs across, its centre `FRONT` studs in front of the pad centre (the pad's -Z, towards the jar, clear of the pad sign), its bottom `LIFT` studs above the pad's bottom, on that floor's walk surface. The small top jar has a smaller coin that fits between the signs and the stair landing. Anchored, CanCollide / CanQuery / CanTouch false.
- Its `Face` SurfaceGui, on top and readable for a player facing the slime, shows `CashPads.face`: the amount with COLLECT under it while cash waits; a dimmed coin with a centred "$0" while less than $1 waits; and a centred green "+$X" for `FLASH_SECONDS` right after the owner collects.
- Stepping on it: `ServerLoop` polls each player's `HumanoidRootPart` every `VIEW_INTERVAL` (`CashPads.touching`: flat distance up to `DIAMETER / 2 + TOUCH_SLACK`, 0..`TOUCH_HEIGHT` studs above the coin). A touch counts once per step-on: standing still collects nothing more until the player steps off and back on. There is no `Touched` handler.
- Coins of plots without an owner, pads that are gone (a removed floor) or pads with neither slime nor pile are destroyed.

## Save (`SaveData`)

`padCash` is an optional dense list, entry i = the pile on pad i (0 = empty), left out when nothing is piled up. Missing / junk -> no piles; non-numbers, NaN, non-positive entries and pads past `padsUnlocked` are dropped (`CashPads.clean`). An older build ignores the key, so a rollback only loses the uncollected piles.

## Not in this version

- No tutorial step (inserting one would shift saved `tutorialStep` indices). While the tutorial runs, a toast says how to collect once $`CASH_PAD.HINT_AT` waits (once a session); the offline join toast and the COLLECT on every coin explain it to everyone else.
