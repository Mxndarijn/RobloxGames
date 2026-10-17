# 11. v29 #4: friend income bonus (2026-10-16, Jolt)

**Status:** contract first. `Config.FEATURES.FriendBonus` (default on); `false` = no bonus, no badge.

- **Rule:** +`FRIEND_BONUS_PER_FRIEND` (10%) income per friend of the player who is in the **same server**, at most `FRIEND_BONUS_CAP` (+30%). `FriendBonus.bonus(count)` (`src/shared/FriendBonus`).
- **Server (`src/server/Friends`):** `Player:IsFriendsWith` through a pcall, cached per pair for `FRIEND_CACHE_SECONDS` (600). A failed check keeps the last known answer (false when none) and isn't retried for `FRIEND_RETRY_SECONDS` (30). `Friends.refresh` runs on every join and leave (async; it yields) and writes `session.friends` and `data.friendBonus`.
- **Income path:** `data.friendBonus` (runtime, **never saved**, no save-format change; optional on `PlayerData.Data`) is a factor of `Perks.bonusMultiplier`, so `incomePerSecond`, `slimeIncome`, `State.incomeMultiplier` and offline income all use it (offline pays at join, before any friend is known: 0).
- **State:** `friends: { count: number, bonus: number }` in every snapshot (0 / 0 with none or the feature off).
- **UI:** HUD banner `"👥 +20% friends"` (hidden while a menu is open, like the modifier banner); the SlimeDex card's income line adds `Friends +20% income`.
