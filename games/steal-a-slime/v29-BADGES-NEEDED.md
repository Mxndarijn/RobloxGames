# v29 #6: Roblox badges needed

Nothing has been created or uploaded. The code is wired and skips every milestone below until its id is filled in
(`badgeId = nil` means no BadgeService call, no toast).

**Where to paste the IDs:** `src/shared/Config.luau`, table `Config.BADGES`. Replace `badgeId = nil` with the number from
Creator Hub (Experience > Monetization > Badges). Keep the `key`s: they are what the server and tests use. No save
change: ownership is read from Roblox (`UserHasBadgeAsync`, cached per player), so the milestones also pay out
retroactively for old saves the next time those players join.

Create each badge in Creator Hub (Badges cost 100 Robux each after the free daily allowance), icon 512x512 PNG, name
under 50 characters, description under 1000.

| Config key | Badge name | Description | Trigger (server, from the save) | Suggested icon (512x512) |
|---|---|---|---|---|
| `FirstSlime` | First Slime | You caught your very first slime! | `stats.caught >= 1` (or owns a slime) | A smiling green blob on a mint circle |
| `FirstSteal` | Sticky Fingers | You stole a slime from another player's plot. | `totalStolen >= 1` | A slime with a little burglar mask, purple background |
| `FirstRebirth` | Reborn | You rebirthed for the first time. | `rebirths >= 1` | A slime inside a swirling gold ring |
| `Rebirth5` | Born Again x5 | You rebirthed five times. | `rebirths >= 5` | Same ring with a big "5" |
| `Dex25` | Dex Explorer | You discovered 25% of the SlimeDex. | dex entries >= 25% of the dex total | Open book, quarter-filled gauge |
| `Dex50` | Dex Collector | You discovered half of the SlimeDex. | dex entries >= 50% | Open book, half-filled gauge |
| `Dex100` | Dex Master | You completed the whole SlimeDex! | dex entries = 100% | Open book, full gold gauge, sparkles |
| `FirstLegendary` | Legend Spotted | You found your first Legendary slime. | SlimeDex holds a tier 5 (Legendary) entry | Golden slime with a crown |
| `FirstSecret` | Secret Keeper | You found a Secret slime. About 1 in 2000. | SlimeDex holds a tier 7 (Secret) entry | Cyan slime with a keyhole, dark background |
| `Millionaire` | Slime Millionaire | You earned $1,000,000. | `totalEarned >= 1,000,000` | Pile of gold coins with a slime on top |

Notes:
- Style: one bold centred subject, flat colours, thick outline, no text except the "5" (badges show tiny).
- The in-game toast ("Badge unlocked!" + name, gold star) is shown only when a badge is newly awarded, not when the
  player already owned it.
- Failed BadgeService calls are retried 4 times (2, 4, 8 s backoff) off the game loop (`Config.BADGE_RETRIES`).
