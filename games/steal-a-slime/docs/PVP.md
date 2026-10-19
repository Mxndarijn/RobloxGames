# PvP ladder (v22) - in-repo design reference

Flag: `Config.FEATURES.PvP` (default `false`). Contract: `CONTRACT.md` §26. Code: `src/shared/PvpRules.luau`, `src/server/PvpService.luau`, data in `Config.PVP` / `Config.PVP_TOOLS`.

## Principles

1. Cash plus rank, no Robux. Rank is checked on purchase and on every use.
2. Server-enforced cooldown, never below 1.5 s.
3. Nothing deals damage or can kill. Knockback is horizontal with a small arc, capped per tier, and the landing point is clamped inside the map. A PvP fall causes no damage.
4. Max 2 s crowd control (slows max 3 s), then 3 s control immunity. Safe zones (spawn, shop, fountain) and the new-player shield (10 min played or first rebirth; ends early if the player steals) block all tools.
5. Tools work only on your own plot, or against a thief carrying a slime. Fun items are aimed toys that follow their own rules (CONTRACT.md §26.4); their control effects still respect the shield and the control cap.
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

**Fun items** (CONTRACT.md §26.4; tunables in `Config.PVP_FUN`, cooldowns in the `PVP_TOOLS` rows): toys first, power second. Every one is aimed with a click (no target pick), works anywhere and needs no plot of your own.

- **Confetti Popper:** aim anywhere, also straight up; the burst rains down over about 10 studs and sticks confetti on everyone under it for a few seconds. Hold to charge a mega pop.
- **Goo Balloon:** lobbed in an arc; the splash paints everyone in it goo green for 10 s and leaves a splat on the ground. A thief in the splash is slowed a little.
- **Bubble Wand:** blows a stream of floating bubbles. A player who touches one floats in a bubble for 1.5 s (control); anyone else can click the bubble to pop it early. A wild slime it touches floats up, drifts and lands (cosmetic).
- **Bounce Pad:** a trampoline, at most 2 live, 60 s each. Everyone bounces on it, wild slimes too; the owner bounces higher with a flip.
- **Squeaky Hammer:** bonk a slime (wild or on any pad) and it squashes flat with a squeak, wobbles and springs back with an excited bounce: no harm, no theft, no value change. Bonk a player and they pancake for 0.8 s, then spring back with a BOING and a small push. Three hits on the same target in quick succession is a giant squeak.
- **Slime Hat Launcher:** a hit player wears a slime hat for 30 s (stacks to 3); a miss turns into a little hat-slime that hops around for 20 s.
- **Dance Bomb:** a lobbed disco bubble with lights and music; everyone inside dances for 2 s (control).
- **Goo Fireworks:** a rocket that bursts high in the colour of your favourite slime, visible across the map; nearby wild slimes cheer-hop. Hold to fire a 3-rocket volley.

A thief carrying a stolen slime who gets lifted, bounced, bonked or made to dance drops it, and the slime goes home. Shielded players only get the cosmetic part (confetti, paint, hats, fireworks).

## Hit feel (tuning and sounds)

Knockback: max push 8 studs (`KNOCKBACK_MAX_PUSH`), arc 2 studs, landing clamped inside `MAP_BOUNDS` minus 6 studs, launch over 0.35 s with a **1.5x horizontal friction boost** (`KNOCKBACK_FRICTION_BOOST`), vertical speed cap 110 studs/s (`KNOCKBACK_MAX_SPEED_Y`, the 25-stud Bounce Pad needs ~99). The server sets the velocity and holds `PlatformStand` for 0.35 s; the victim's client applies the `velocity` from the Effect payload to its own root (same clamp). Void guard: 5 s after a PvP launch or under control, a character below y = -20 is rescued (kill plane -60); nothing in PvP can kill, there is no fall damage. Trap hold 1 / 1.5 / 2 s and blaster slow 30 % 2 s / 40 % 2.5 s / 50 % 3 s are asserted in `tests/PvpFeel.spec`.

Client effect sounds (Roblox library sounds plus one Pro Sound Effects sound, all `AssetTypeId` 3 and `IsPublicDomain` true per economy.roblox.com/v2/assets/<id>/details):

| `Sounds.IDS` | id | library name | used for |
|---|---|---|---|
| `PvpHit` | 12222046 | hit.wav | glove punch |
| `PvpCollide` | 12221984 | collide.wav | spare impact |
| `PvpGoo` | 12222152 | splat.wav | trap freeze goo |
| `PvpSquirt` | 12222103 | Rubber band sling shot.wav | blaster shot / splat |
| `PvpBoing` | 12222124 | Short spring sound.wav | Bounce Pad |
| `PvpPop` | 12221996 | flashbulb.wav | confetti / balloon / hat / dance |
| `PvpSqueak` | 9125994570 | Squeeze Toy Squeaky Rubber (Pro Sound Effects, public domain) | Squeaky Hammer |
| `PvpFirework` | 12222065 | Launching rocket.wav | fireworks |
| `PvpBubble` | 12222054 | Kerplunk.wav | Bubble Wand |
| `PvpDisco` | 9047231371 | APM "Copacetic - 15" (Roblox-licensed APM music) | Dance Bomb disco bubble |

## PR sequence

A fairness core (this) - B knockback - C traps - D blaster - E fun items - F icons (done: all 19 Pvp_* icons rendered and uploaded, wired in `ItemIcons.IMAGES`, covered by `tests/ui/ShopIcons.spec.luau`). Then Jolt builds the hotbar and shop UI.
