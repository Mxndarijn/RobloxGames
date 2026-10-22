# §33 Boss event: a server-wide fight, a haul race, boss badges

Design: `docs/SLIME-ECONOMY.md` §3. The boss is one of the six `kind = "boss"` species in `Shared.SlimeRoster`
(`goozilla`, `queen_jelly`, `klawdius`, `pumpking` at tier 6, `mecha_goo`, `goomancer` at tier 7; see Bosses below).
It replaces the old "first grab wins" Boss Slime (`Spawner.spawnBoss`, `BOSS_TIER`, `BOSS_LIFETIME`), which is gone.

## Flow (server)

| Phase | Lasts | What happens |
|---|---|---|
| `"warning"` | `BOSS.WARNING_SECONDS` | Server-wide Notify (heads-up) and `State.boss.phase = "warning"`. No model yet. |
| `"fight"` | up to `BOSS.FIGHT_SECONDS` | A wild slime with `boss = true` drops onto the plaza boss spot and moves round the boss area (Moves, below), `BOSS.SCALE` x its size, prompt disabled. Bat hits fill the goo meter. |
| `"haul"` | up to `BOSS.HAUL_SECONDS` | The boss stops where it stood (move `down`) and shrinks to carry size over `BOSS.SHRINK_SECONDS`; then scale 1, prompt "Grab", hold 0. Carried through `Carry` like a wild slime. |
| `"won"` / `"failed"` | `BOSS.LINGER_SECONDS` | Result shown in `State.boss`, then the event clears. |

- **Schedule (`server/BossEvent`).** The first boss arrives `BOSS.FIRST_AT` after server start, then every
  `BOSS.INTERVAL` after the previous arrival. The warning starts `BOSS.WARNING_SECONDS` before the arrival. If Slime Rain
  is still running at the arrival, or starts within `BOSS.RAIN_GAP` after it, the arrival moves `BOSS.SKIP_DELAY` later
  (checked again then). `world.nextBossAt` is the next arrival (workspace attribute `BossNextAt` as before).
- **Rotation.** `BOSS.ROTATION` in order (`goozilla queen_jelly klawdius pumpking mecha_goo goozilla queen_jelly
  klawdius pumpking goomancer`), looping: every tier-6 boss twice and each Secret once per lap. A Secret-tier slot
  (`mecha_goo`, `goomancer`) needs `world.fountainTier >= BOSS.SECRET_FOUNTAIN_TIER` (Starlight); otherwise it is
  `BOSS.SECRET_FALLBACK`.
- **Meter (`Shared.BossFight`, pure).** One point per Bat hit per player, at most one per `BOSS.HIT_GAP` seconds each.
  Target = `BOSS.POINTS_PER_PLAYER` x players on the server (at least 1), read live. With no hit for `BOSS.DRAIN_GRACE`
  seconds it drains `BOSS.DRAIN_PER_SECOND` of the target per second. Every player's points are kept (they never drain).
  Each `BOSS.STAGE_EVERY` of the meter crossed for the first time is a new stage (`BossFight.stage`, event `stage`):
  the boss speeds up (below). The boss never drops wild slimes, during the fight or after it. The full meter starts
  the haul.
- **Area (`Shared.BossArea`, pure).** The plaza inside the parade lane, within `BOSS.WANDER_ARC` radians either side of
  `BOSS.SPOT_ANGLE`: its Body (radius `SLIME_BASE_DIAMETER x MAX_SIZE x BOSS.SCALE / 2`) outside the landing ring
  (`Fountain.LANDING_RING_OUTER`), its centre at least `BOSS.WANDER_CLEARANCE` from the lane's edge and the goo drain's
  lip. It is a long, thin strip round the fountain. Every point of every move is in it.
- **Moves (`Shared.BossChoreo`, pure).** The boss moves one move at a time; `server/BossEvent` picks the next one when
  the last ends, starting at that end time (no gap), from where the players near it (`BossEvent.ENGAGE_RADIUS`) stand:
  - `arrive`: drops onto the boss spot from `BOSS.ARRIVE_HEIGHT` over `BOSS.ARRIVE_FALL`, splats (`ARRIVE_SECONDS`).
  - `stroll`: a straight walk `BOSS.STROLL_MIN..STROLL_MAX` studs along the strip at `BOSS.STROLL_SPEED`, easing in
    and out over `BOSS.STROLL_EASE`; with chance `BOSS.STROLL_TOWARD` it heads for the players' middle.
  - `look`: stands `BOSS.LOOK_SECONDS` and turns to the nearest player.
  - `windup` / `attack` / `dazed` / `rise` / `land`: the attacks (below).
  - `down`: the meter filled; it stands where it was while it shrinks.
  A move is: number, kind, slot, start time, length, start and end spot (plaza coordinates round the fountain centre),
  end heading, and the plaza origin in world studs. Hits, the Body and every client use the same pose from server time.
- **Hits.** The Bat (`BatTool.swing`, no remote): anyone carrying a slime (stolen, wild or the boss) in reach is tried
  first (the slap);
  otherwise a guard in `BOSS.GUARD_REACH` and in front is popped (`BossEvent.hitGuard`); otherwise the boss in the
  fight phase is hit when its move's pose is within `BOSS.HIT_REACH` and in front (`BatRules`). A hit counts
  `BossAttacks.hitValue` points: 1, `BOSS.DAZED_MULTIPLIER` while it is dazed, a vent's `multiplier` from behind while
  dazed once the phase is on, none while it floats (`rise` / `land`: "it's out of reach"). A stunned player's swings do
  nothing (no hits, no slaps). The latest counted hit is `world.boss.lastHit`.
- **Attacks (`Shared.BossAttacks`, pure; `Config.BOSS.MOVES` per species).** From `BOSS.FIRST_ATTACK` after it lands,
  and `BOSS.ATTACK_GAP` (÷ the stage speed-up) after each daze, the next attack winds up from a `look` stop, rotating
  through `BossAttacks.available` (its `start` set, plus its `phase` set from `BOSS.PHASE_AT` of the meter; `vent` is
  passive). Every attack is `windup` (`BOSS.WINDUP_SECONDS`, facing its target: the top hitter for a charge, else the
  nearest player) → `attack` → `dazed` (`BOSS.DAZED_SECONDS`):
  - `ring` { radius, speed, push }: from `BOSS.RING_DELAY` a band `BOSS.RING_WIDTH` thick runs out from where it
    stomped; it strikes grounded players it passes (a jump clears it).
  - `cone` { radius, angle, push }: at `BOSS.CONE_HIT_AT`, players inside the wedge in front.
  - `charge` { distance, speed, width, push }: it rams along its heading up to `distance` (stopping at the area's
    edge); it strikes anyone within its Body radius + width / 2.
  - `spit` { count, slowSeconds, slow }: the windup picks `count` landing spots (the nearest players, then spots
    `BOSS.SPIT_SPREAD` round it); they land `BOSS.SPIT_FLIGHT` into the attack as puddles of `BOSS.PUDDLE_RADIUS` that
    last `slowSeconds`; a player in one walks at `slow` x speed (`Session.bossSlow`, `Carry.targetWalkSpeed`).
  - `guards` { count }: instead of an attack it `rise`s (`BOSS.RISE_HEIGHT`) for up to `BOSS.GUARD_SECONDS` with
    `count` guards `BOSS.GUARD_RADIUS` round it, each `BOSS.GUARD_POINTS` meter points to pop. The last pop makes it
    `land` (slot `daze`) then `dazed`; a timeout lands it without the daze. With `rain` { every, count, delay, radius,
    speed, push } it is not idle while it floats: from `BOSS.RISE_SECONDS` + 0.3 s after the rise starts, every
    `every` seconds (÷ the stage speed-up) it drops goo on the `count` players nearest to it (`World.BossEvent.rainAt`):
    each drop is a spit (red landing circle, `BOSS.SPIT_FLIGHT`) whose puddle bursts `delay` later into a ring of
    `radius` at `speed` (push `push`). Stand still and it knocks you; keep moving while you pop the guards.
  - `hops` { count, distance, radius, speed, push }: `count` legs of move `hop`, each a leap of `distance` toward the
    top hitter (else the nearest player) over `BOSS.HOP_SECONDS`, `BOSS.HOP_HEIGHT` high, then a ring of `radius` at
    `speed` from where it landed; then `dazed`.
- **Signature attacks.** Every boss has one attack only it has, set by options on the primitives:
  - Goozilla, double stomp: ring `waves = 2`; each next wave starts `waveGap` later, `waveSpeedUp` x faster. A player
    can be struck once per wave.
  - Queen Jelly, royal guards: guards `heal` + `rain`. While her guards stand she rains jelly on the nearest players,
    and if any guard is still up when the call runs out she gets `heal` x the meter target back (a server toast says
    so).
  - Mecha Goo, ricochet charge: charge `bounces = 1`. After each leg it winds up again (`BOSS.LEG_WINDUP_SECONDS`,
    slot `<slot>#<leg>`) and rams the top hitter.
  - Klawdius, scuttle: charge `sideways`, `backAndForth`, `bounces = 2`. It travels to its right (it faces the
    player, so it runs across them like a crab), and each next leg runs back the way it came.
  - Pumpking, bouncing stomps: `hops`.
  - Goomancer, rune puddles: spit `burst` { delay, radius, speed, push }. `delay` after landing, each puddle bursts
    into a ring of its own (puddle `burstAt`).
  A struck player is knocked `push` studs away from the boss, `BOSS.HIT_ARC` high (`ctx.launch` + a PvpEvent
  Knockback, live whatever `FEATURES.PvP` says), stunned for `BOSS.STUN_SECONDS` (`Session.bossStunUntil`) and toasted.
  Each attack strikes a player once. The meter never drains during `windup`, `attack`, `hop`, `rise` or `land`. Every
  `BOSS.STAGE_EVERY` of the meter reached speeds its moves and attack gaps by `BOSS.STAGE_SPEEDUP`.
- **Haul.** For the first `BOSS.PRIORITY_SECONDS` only the top contributor may grab it (if still on the server); then
  anyone. The carrier walks at `BASE_WALK_SPEED x (1 - BOSS.CARRY_SLOW)`: no Speed Coil, no Strong Arms
  (`Carry.walkSpeed`). A Bat slap (reach `SLAP_REACH`, the shared slap cooldown) or `Request("Drop")` drops it on the
  spot; anyone can grab it again. Dropping never resets the haul deadline.
- **Win.** The carrier reaches their HomeZone (`Carry.depositBoss`, no free pad needed): a server-wide toast names the
  winner, who alone gets the win (below); the top hitter gets the Boss MVP boost. The boss slime is removed; it never
  goes into `data.slimes` or anywhere else in the save.
- **Fail.** Meter not full by the fight deadline, or not home by the haul deadline: the boss (carried or not) is removed:
  it gets away. No slimes drop.
- Bosses never count toward the wild cap and are never a random merge or fountain result.

## Bosses

Each boss is a `kind = "boss"` species with its own mesh (`slime_<id>`, `shared/modeling-kit/models/pool`), look
(`SlimeLooks`) and gait / temper (`SlimePersona`). In the fight it stands `BOSS.SCALE` x a MAX_SIZE slime, so every boss
has one bold silhouette that reads across the plaza.

| id | Name | Tier | Gait / temper | Theme |
|---|---|---|---|---|
| `goozilla` | Goozilla | 6 | Waddle / Feisty | roaring kaiju slime with glowing back plates |
| `queen_jelly` | Queen Jelly | 6 | Float / Showoff | jellyfish queen with a tiara and ribbon tentacles |
| `klawdius` | Klawdius | 6 | Scoot / Feisty | hermit crab in a spiral shell, one giant fiddler claw |
| `pumpking` | Pumpking | 6 | Hop / Bouncy | ribbed jack-o'-lantern with a glowing carved grin, curly stem and a crown |
| `mecha_goo` | Mecha Goo | 7 | Waddle / Feisty | mech with a tiny slime pilot |
| `goomancer` | Goomancer | 7 | Float / Curious | wizard with a tall bent star hat, white beard and an orb staff |

**Attacks (design).** Every boss has a start set of one or two attacks and one more that unlocks once the goo meter
passes 50 %. They are built only from the boss-attack primitives: `ring` (a goo shockwave from the boss, jump over it),
`spit` (puddles land at players and slow them), `guards` (the boss floats out of reach and calls small guards; bonking
them all drops it dazed), `cone` (a push in front of it), `charge` (a ram along a telegraphed lane at the top hitter) and
`vent` (a weak spot on its back while it is dazed). The numbers below are the design's starting values; the attack
values live in `Config.BOSS.MOVES` (Attacks, below).

**Fight pacing (the fun pass).** A fight lasts long enough for the boss to attack many times: the meter target is
`BOSS.POINTS_PER_PLAYER` (110) per player, a dazed hit counts `BOSS.DAZED_MULTIPLIER` (2), and every `vent` is x3. The
first attack comes `BOSS.FIRST_ATTACK` (3 s) after it lands and the next `BOSS.ATTACK_GAP` (2.5 to 4 s) after each daze.
Every boss starts with at least two real attacks and adds at least one more from 50 % (a spec checks this), so no boss
has a phase where it only waits. A solo bot that never dodges fills the meter in about 35 to 50 s and takes 2 to 10
knockbacks; players who get pushed out of reach take longer. Current move sets (`Config.BOSS.MOVES`, which wins over the
design text below):

| Boss | Start | From 50 % |
|---|---|---|
| Goozilla | double stomp `ring`; `spit` | wide `cone`; triple stomp `ring` |
| Queen Jelly | `guards` with `rain` and `heal`; `cone` | `ring`; `spit` |
| Klawdius | `cone`; sideways scuttle `charge` | `spit`; `ring`; `vent` |
| Pumpking | `hops`; `spit` | `guards` with `rain`; bigger `hops`; `vent` |
| Mecha Goo | ricochet `charge`; `ring` | `spit`; double ricochet `charge`; `vent` |
| Goomancer | rune `spit`; `cone` | `ring`; `vent` |

### Klawdius

A scuttling brawler: it fights up close and sideways, like a crab.
- **Start:** a claw snap, a `cone` of radius 16 and 70 degrees (push 35) when players crowd its front, and a sideways
  scuttle `charge` of 35 studs at 32 studs/s, 7 wide (push 45), at the top hitter.
- **From 50 %:** it froths: `spit` of 4 sea-foam bubble puddles that slow to 0.55 x walk speed for 5 s.
- **Dazed:** it flips onto its shell with its legs kicking, and the soft goo tail pokes out of the shell mouth on its
  back: that is the `vent` (x4 for 4 s).

### Pumpking

A heavy hopper: every landing is a stomp.
- **Start:** each big hop lands with a `ring` shockwave, radius 24 at 20 studs/s (push 40), to jump over.
- **From 50 %:** it rises on a swirl of candle smoke out of reach and calls 3 gourdling `guards` (little pumpkins);
  bonking all of them drops it.
- **Dazed:** it thuds down, its candle sputters out so the grin goes dark, its crown slips crooked; steam leaks from a
  split seam on its back: the `vent` (x3 for 5 s).

### Goomancer

A caster that keeps players moving: it hexes from range and blasts anyone in front of it.
- **Start:** hex bolts, `spit` of 4 puddles that slow to 0.5 x walk speed for 6 s, and a staff blast `cone` of radius 20
  and 100 degrees (push 40).
- **From 50 %:** an arcane nova, a wide fast `ring` of radius 28 at 26 studs/s (push 45).
- **Dazed:** its hat slides down over its eyes and the staff clatters to the ground; a rune patch glows on its back:
  the `vent` (x5 for 3 s, a short window for the Secret boss).

## Boss record and badges: `data.boss` (save v9)

Boss badges are kept in the player's save, not on Roblox (they are unrelated to `server/Badges` and `Config.BADGES`).
A later build shows them in the base or a panel; for now they are saved, in State and toasted.

```lua
data.boss = {
	hits: number, -- counted Bat hits on any boss (BossFight.hit returned true)
	wins: { [string]: number }, -- boss species id -> times carried home
	hauls: number, -- bosses this player carried home
	mvps: number, -- won bosses where this player was the top contributor
	badges: { [string]: number }, -- Config.BOSS_BADGES key -> unix seconds (server time) it was earned
}
```

- **Triggers (`server/BossCredit`).** A counted hit in `BossEvent.hit` records a hit. When the boss is brought home,
  only the carrier gets a win for that species (so its boss badge), a haul and the species in their SlimeDex
  (`PlayerData.discover` with the boss slime). Other helpers get nothing for the boss itself.
- **Boss MVP boost.** The top contributor (`BossFight.top`), if still on the server, counts an MVP (`mvps`, no badge)
  and gets `data.mvpBonus = BOSS.MVP_BONUS` (+50 % income, a factor of `Perks.bonusMultiplier` like the ritual's
  Blessed) until `session.mvpUntil = now + BOSS.MVP_SECONDS` (5 min). Both are runtime only, never saved; leaving the
  server ends it, and a new MVP restarts the timer. `BossCredit.expire` (every `GameLoop.step`) clears it and toasts.
  `State.mvpBoost = { bonus, endsAt }` while it lasts; the HUD shows it as the `Mvp` status slot right after `Blessed`
  (`Boost_Mvp` icon, time left in its pill, tooltip "Boss MVP" / "+50% income for landing the most hits on a boss.").
- **Badges (`Config.BOSS_BADGES`, `Shared.BossBadges`).** Each entry: `key`, `name`, `description`, `trigger`, `value`,
  optional `species`. Triggers: `hits` (record.hits >= value), `win` (wins[species] >= value), `wins` (all species
  summed >= value), `hauls`, `mvps`. A per-species badge is one `win` line with its `species`. After each recorded event
  `BossBadges.grant(data, now)` stamps every reached, unearned badge; each new one toasts that player
  (`World.notify`, kind `"badge"`): `Badge earned: <name>!`. A badge, once earned, is never taken away.
- **Save.** `SAVE_VERSION` 9. `SaveData.migrateV8` turns the old `trophies` list into `boss.wins[species] = 1` per boss
  species held (unknown / non-boss species dropped) and removes `trophies`. `SaveData.deserialize` sanitizes `boss`
  (`BossBadges.clean`: whole numbers clamped, unknown species and badge keys dropped, missing -> zeros), then grants
  every badge the record has reached, stamped with the save's `lastOnline` (silently, no toast), and discovers every
  boss species in `wins` in the SlimeDex. A boss badge added later is therefore granted on the next load to players
  who already qualify.
- Bosses earn no income and nothing about them can be stolen.

## `State.boss` (`Types.BossView`, in every snapshot)

```lua
boss: {
	active: boolean, -- a boss event is on (warning, fight or haul)
	phase: string?, -- "warning" | "fight" | "haul" | "won" | "failed"; nil = no event
	kind: string?, -- boss species id (SlimeRoster), nil with no event
	name: string?, -- species display name
	tier: number?,
	meter: number, -- 0..1 goo meter (1 from the haul on)
	endsAt: number?, -- server time the current phase ends (warning: the arrival)
	nextAt: number?, -- server time of the next arrival when no event is on
	yourPoints: number, -- this player's hits on this boss
	yourShare: number, -- yourPoints / top contributor's points, 0..1
	carrierName: string?, -- haul: who carries it
	priorityName: string?, -- haul: the top contributor while their head start runs
	priorityUntil: number?,
	winnerName: string?, -- "won": who brought it home
	badges: number, -- boss badges this player has earned
	move: string?, -- fight: the boss's move kind (BossChoreo)
	moveEndsAt: number?, -- server time that move ends
	multiplier: number?, -- dazed: points per bat hit
	guardsLeft: number?, -- rise: guards still standing
	guardsTotal: number?, -- rise: guards it called
	stunnedUntil: number?, -- this player can't hit until then
}
```

## Attack view (server `BossFxView`, client `visuals/client/BossTelegraph`)

- `workspace.BossFx`: one guard model per live guard (attribute `BossGuard = true`) and one goo puddle per puddle. A
  guard is a mini copy of its boss (`BOSS.GUARD_SIZE` across), built by WorldView's slime model factory from the boss's
  own slime data (`BossFxView.sync`'s `look`), with every slime tag removed so nothing treats it as a slime; it faces
  away from the boss. Without a factory (tests, a failed build) it is the plain crowned ball. Clients make guards hop
  in place, out of step with each other (`BossTelegraph`).
- Boss model attributes: `BossTargets` ("x,z;..." world spots a spit windup will hit), `BossSpits` ("x,z,landAt;..."),
  `BossRunes` ("x,z,burstAt,radius,speed;..." rune puddles that burst into a ring),
  `BossHitAt` / `BossHitBy` / `BossHitPoints` (the latest counted bat hit: the boss squashes, the hitter sees a "+n").
- Clients draw from the same `BossAttacks` geometry: a pulsing red outline during the windup (the ring, the wedge, the
  charge lane, the spit spots), the goo ring running out, spits in flight, and stars over it while it is dazed. Local
  parts only.

Every phase change, meter change and grab / drop pushes State to every player (`World.markAllDirty`).

## `State.bossBadges` (`Types.BossBadgeView`, in every snapshot)

```lua
bossBadges: { { key: string, earnedAt: number } }, -- earned boss badges, in Config.BOSS_BADGES order
```

Names and descriptions come from `Config.BOSS_BADGES` by `key`. A newly earned badge marks the session dirty.

## Request actions

None new. Hits are Bat swings (no remote), grabs are the slime's ProximityPrompt (`Carry.grab`), drops are the existing
`Request("Drop")`.

## Config (`Config.BOSS`)

`FIRST_AT INTERVAL WARNING_SECONDS RAIN_GAP SKIP_DELAY FIGHT_SECONDS HAUL_SECONDS LINGER_SECONDS PRIORITY_SECONDS
POINTS_PER_PLAYER HIT_GAP HIT_REACH DRAIN_PER_SECOND DRAIN_GRACE STAGE_EVERY CARRY_SLOW
SCALE SPOT_ANGLE SPOT_RADIUS WANDER_ARC WANDER_CLEARANCE STROLL_* LOOK_SECONDS ARRIVE_* WINDUP_SECONDS CHARGE_EASE
STRIKE_SECONDS RING_DELAY SPIT_FLIGHT DAZED_SECONDS RISE_* LAND_SECONDS GUARD_SECONDS SHRINK_SECONDS
MOVE_PIVOT_INTERVAL ROTATION SECRET_FOUNTAIN_TIER SECRET_FALLBACK MVP_BONUS MVP_SECONDS FIRST_ATTACK ATTACK_GAP
STAGE_SPEEDUP PHASE_AT DAZED_MULTIPLIER STUN_SECONDS HIT_ARC RING_WIDTH CONE_HIT_AT PUDDLE_RADIUS SPIT_SPREAD GUARD_*
MOVES`, and the badge list `Config.BOSS_BADGES`. Values live in `Config.luau` only.

## World / Scene

- `world.boss: BossEvent? = { fight: BossFight.State, slimeId: string?, lastStepAt, rng }`, `world.bossIndex`
  (rotation position). `rng` is the boss's own (where it strolls), so the fountain's sequence never shifts.
- `Wild.move: BossChoreo.Move?` on the boss slime: its current move.
- `Scene.Entry.bossScale` (`BOSS.SCALE` in the fight phase and the haul's first `BOSS.SHRINK_SECONDS`, else nil = 1)
  and `promptEnabled` only in the haul phase after the shrink (`Carry.grab` refuses during it too). Never on the parade
  lane or the fountain ride. The model keeps attribute `Boss = true`.
- While it is wild and undropped the model carries `BossMove` (`BossChoreo.encode` of its move); anything else clears
  it. The server pivots the Body to the move's pose every `BOSS.MOVE_PIVOT_INTERVAL` (the prompt, streaming, the label);
  clients draw the move itself every frame: the life rig (`SlimeActor`, with the species gait, the boss always has a
  rig) or, without one, the visuals client's pivot. Nothing on the client pushes the boss aside.
