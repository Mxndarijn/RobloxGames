# PvP ladder - in-repo design reference

Flag: `Config.FEATURES.PvP`. Contract: `CONTRACT.md` §26 (`contract/pvp.md`). Code: `src/shared/PvpRules.luau`, `src/server/PvpService.luau` (+ `PvpKnockback`, `PvpTrap`, `PvpBlaster`, `PvpSlow`, `PvpFun`), data in `Config.PVP` / `Config.PVP_TOOLS`. Every number below is a starting value; `Config` holds the live one.

## Principles

1. Cash plus rank, no Robux. Rank is checked on purchase and on every use.
2. Server-enforced cooldown, never below 1.5 s (the Goo Squirter's cooldown is per tank of 6 shots).
3. Nothing deals damage or can kill. Knockback is mostly horizontal with a capped arc, and the landing point is clamped inside the map. A PvP fall causes no damage; the void guard puts anyone who still falls back.
4. Max 2 s crowd control (slows max 3 s), then 3 s control immunity.
5. **No safe zones.** Every PvP item works on anyone, anywhere. On a player who carries nothing the effect stays light (a push, a short slow, a laugh); nobody loses anything to it.
6. **A caught thief loses the slime.** Whenever a PvP item hits a player carrying a stolen slime (every item except the purely cosmetic Confetti Popper), the slime bounces home to its owner's plot (`PvpService.catchThief`, the same drop + bounce + notifications as the Bat).
7. **Fun items are toys first** (CONTRACT.md §26.8): aimed with a click, no target pick, no plot of your own needed. Their control effects still respect the control cap.
8. Show-off, not power gap: the top tier is about 2x the base effect.

Price = `max(100, floor(k x Economy.rebirthCost(gate)))`, k = 0.03 for gloves and blasters, 0.01 for fun items, and a smaller k for one Goo Trap charge (traps are used up).

## Ladder

| Rank (rebirths) | Knockback | Goo Trap | Goo Blaster | Fun |
|---|---|---|---|---|
| 0 Slime Rookie | Bat | | | `FunConfetti` |
| 1 Goo Getter | `KnockGlove1` | | | `FunBalloon` |
| 3 Slime Wrangler | | `GooTrap1` | | `FunBubbles` |
| 5 Blob Baron | `KnockGlove2` | | | `FunBouncePad` |
| 6 Goo Tycoon | | `GooTrap2` | | `FunSqueaky` |
| 7 Jelly Magnate | | | `GooBlaster1` | `FunHatLauncher` |
| 8 Ooze Overlord | `KnockGlove3` | | | `FunDanceBomb` |
| 10 Slime Sovereign | | `GooTrap3` | | `FunFireworks` |
| 12 Gel Emperor | `KnockGlove4` | | `GooBlaster2` | |
| 20 Mythic Monarch | `KnockGlove5` | | `GooBlaster3` | |

## Gloves

Tap = punch. Hold (at least `CHARGE_SECONDS`) and release = power punch: 1.5x push, longer cooldown. Punching a thief always sends the slime home, also when the push itself is refused by immunity.

| Glove | Push | Special |
|---|---|---|
| Bonk | 5 | a clean punch and a "BONK!" popup |
| Bounce | 6 | the target pogo-bounces 3 times, each lower |
| Boom | 7 | a small blast also pushes everyone within 5 studs of the target |
| Thunder | 7.5 | lightning chains to up to 2 nearby players at half push |
| Royal | 10 | a long push in a high arc with gold confetti |

Knockback caps (`KNOCKBACK_MAX_PUSH`, `KNOCKBACK_ARC_HEIGHT`, `KNOCKBACK_BOUNDS_MARGIN`) are raised just enough for the Royal power punch; the landing stays inside `MAP_BOUNDS` minus the margin, which also covers the friction-boost overshoot.

## Goo Traps

Buying gives one trap charge (a stack, like consumables); at most 5 per tier. Click the ground to throw one (one charge). At most 5 live traps per player; a 6th removes the oldest. A trap lasts 3 minutes or until it catches someone. Charges are saved, live traps are not. The owner sees their traps glowing; others see a faint shimmer.

| Trap | Radius | Effect |
|---|---|---|
| Goo Puddle | 3 | 50 % slow for 2 s, green goo on the feet, a squelch |
| Sticky Trap | 3.5 | stuck 1.5 s, then slowed |
| Mega Trap | 4 | jaws snap: held 2 s, then spat out with a small bounce; also pulls in anyone else within 4 studs |

Any tier that catches a thief sends the slime home. The trap meshes (`pvp_goo_trap_1..3`) drop in through `PvpModels` once uploaded; until then the marker is the placeholder model on a goo disc.

## Goo Blasters

Real goo blobs fly a visible arc; the server owns the shot (start point, range, aim, rate) and decides the hit at fire time. A hit slows, splats goo on the edge of the victim's screen and tints them green. A miss leaves a slippery splat on the ground for 5 s; a thief who walks into a splat or a Cannon pool is caught too.

| Blaster | Shot | Effect |
|---|---|---|
| Goo Squirter | rapid fire, 6 shots per tank, then a short refill | each hit stacks a little slow (the whole slow capped at 3 s); a hit on a thief sends the slime home |
| Goo Blaster | 3 blobs in a fan | slow; a hit on a thief sends the slime home |
| Goo Cannon | hold to aim, a big lob | splashes everyone within 6 studs, leaves a slowing pool for 4 s; a hit on a thief sends the slime home |

## Fun items

Tunables in `Config.PVP_FUN`, cooldowns in the `PVP_TOOLS` rows. Toys first, power second. Every one is aimed with a click (no target pick), works anywhere and needs no plot of your own.

- **Confetti Popper:** aim anywhere, also straight up; the burst rains down over about 10 studs and sticks confetti on everyone under it for a few seconds. Purely cosmetic: it never catches a thief. Hold to charge a mega pop.
- **Goo Balloon:** lobbed in an arc; the splash paints everyone in it goo green for 10 s and leaves a splat on the ground. A thief in the splash is slowed a little.
- **Bubble Wand:** blows a stream of floating bubbles. A player who touches one floats in a bubble for 1.5 s (control); anyone else can click the bubble to pop it early. A wild slime it touches floats up, drifts and lands (cosmetic).
- **Bounce Pad:** a trampoline, at most 2 live, 60 s each. Everyone bounces on it, wild slimes too; the owner bounces higher with a flip.
- **Squeaky Hammer:** bonk a slime (wild or on any pad) and it squashes flat with a squeak, wobbles and springs back with an excited bounce: no harm, no theft, no value change. Bonk a player and they pancake for 0.8 s, then spring back with a BOING and a small push. Three hits on the same target in quick succession is a giant squeak.
- **Slime Hat Launcher:** a hit player wears a slime hat for 30 s (stacks to 3); a miss turns into a little hat-slime that hops around for 20 s.
- **Dance Bomb:** a lobbed disco bubble with lights and music; everyone inside dances for 2 s (control).
- **Goo Fireworks:** a rocket that bursts high in the colour of your favourite slime, visible across the map; nearby wild slimes cheer-hop. Hold to fire a 3-rocket volley.

A thief carrying a stolen slime who gets splashed, lifted, bounced, bonked, hatted or made to dance drops it, and the slime goes home (confetti and fireworks catch nobody).

## Hit feel (sounds)

Client effect sounds (Roblox library sounds plus one Pro Sound Effects sound, all `AssetTypeId` 3 and `IsPublicDomain` true per economy.roblox.com/v2/assets/<id>/details):

| `Sounds.IDS` | id | library name | used for |
|---|---|---|---|
| `PvpHit` | 12222046 | hit.wav | glove punch |
| `PvpCollide` | 12221984 | collide.wav | spare impact |
| `PvpGoo` | 12222152 | splat.wav | trap goo / squelch |
| `PvpSquirt` | 12222103 | Rubber band sling shot.wav | blaster shot / splat |
| `PvpBoing` | 12222124 | Short spring sound.wav | Bounce Pad, Bounce Glove pogo |
| `PvpPop` | 12221996 | flashbulb.wav | confetti / balloon / hat / dance |
| `PvpSqueak` | 9125994570 | Squeeze Toy Squeaky Rubber (Pro Sound Effects, public domain) | Squeaky Hammer |
| `PvpFirework` | 12222065 | Launching rocket.wav | fireworks |
| `PvpBubble` | 12222054 | Kerplunk.wav | Bubble Wand |
| `PvpDisco` | 9047231371 | APM "Copacetic - 15" (Roblox-licensed APM music) | Dance Bomb disco bubble |

