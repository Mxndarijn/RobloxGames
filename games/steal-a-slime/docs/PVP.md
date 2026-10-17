# PvP ladder (v22) - in-repo design reference

Flag: `Config.FEATURES.PvP` (default `false`). Contract: `CONTRACT.md` §26. Code: `src/shared/PvpRules.luau`, `src/server/PvpService.luau`, data in `Config.PVP` / `Config.PVP_TOOLS`.

## Principles

1. Cash plus rank, no Robux. Rank is checked on purchase and on every use.
2. Server-enforced cooldown, never below 1.5 s.
3. Nothing deals damage or can kill. Knockback is horizontal with a small arc, capped per tier, and the landing point is clamped inside the map. A PvP fall causes no damage.
4. Max 2 s crowd control (slows max 3 s), then 3 s control immunity. Safe zones (spawn, shop, fountain) and the new-player shield (10 min played or first rebirth; ends early if the player steals) block all tools.
5. Tools work only on your own plot, or against a thief carrying a slime. Purely cosmetic fun items are exempt from that rule but still respect safe zones and the shield (`FunConfetti` may be used inside a safe zone).
6. Show-off, not power gap: the top tier is about 2x the base effect. A higher tier replaces the lower one.

Price = `max(100, floor(k x Economy.rebirthCost(gate)))`, k = 0.03 for tools, 0.01 for fun items (the pacing sim tunes it). The base slap stays free (4 studs push, PR B).

## Ladder

| Rank (rebirths) | Knockback | Goo Trap | Goo Blaster | Fun |
|---|---|---|---|---|
| 0 Slime Rookie | base Slap | | | `FunConfetti` |
| 1 Goo Getter | `KnockGlove1` | | | `FunBalloon` |
| 3 Slime Wrangler | | `GooTrap1` | | `FunBubbles` |
| 5 Blob Baron | `KnockGlove2` | | | `FunBouncePad` |
| 6 Goo Tycoon | | `GooTrap2` | | `FunSqueaky` |
| 7 Jelly Magnate | | | `GooBlaster1` | `FunHatLauncher` |
| 8 Ooze Overlord | `KnockGlove3` | | | `FunDanceBomb` |
| 10 Slime Sovereign | | `GooTrap3` | | `FunFireworks` |
| 12 Gel Emperor | `KnockGlove4` | | `GooBlaster2` | |
| 20 Mythic Monarch | `KnockGlove5` | | `GooBlaster3` | |

Ranks 15 and 30 add cosmetic gold skins / aura FX later (no item in this PR).

**Knockback** (reach 10, cooldown 1.5 s): Bonk Glove 5 studs, Bounce 6, Boom 7, Thunder 7.5, Royal 8.

**Goo Trap** (own plot): Puddle 1 trap, freeze 1 s, re-arm 30 s, radius 3; Sticky 2 traps, 1.5 s, 25 s, 3.5; Mega 2 traps, 2 s, 20 s, 4.

**Goo Blaster** (server hitscan, range 40 / 45 / 50, only vs a thief carrying a slime): Squirter slow 30 % for 2 s, cooldown 12 s; Blaster 40 % / 2.5 s / 11 s; Cannon 50 % / 3 s / 10 s.

**Fun items** (cooldown): Confetti 5 s, Balloon 3 s (decals fade after 10 s, max 8), Bubbles 4 s, Bounce Pad 10 s (own plot, max 1, 25 studs straight up, thieves 1.2 s then immunity), Squeaky Hammer 3 s (2-stud nudge on a thief only), Hat Launcher 8 s (self or friends, 30 s), Dance Bomb 45 s (own plot, thieves only, 2 s), Fireworks 20 s (own plot, cosmetic).

## PR sequence

A fairness core (this) - B knockback - C traps - D blaster - E fun items - F icons (done: all 19 Pvp_* icons rendered and uploaded, wired in `ItemIcons.IMAGES`, covered by `tests/ui/ShopIcons.spec.luau`). Then Jolt builds the hotbar and shop UI.
