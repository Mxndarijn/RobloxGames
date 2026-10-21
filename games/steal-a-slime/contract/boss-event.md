# §33 Boss event: a server-wide fight, a haul race, a trophy

Design: `docs/SLIME-ECONOMY.md` §3. The boss is one of the six `kind = "boss"` species in `Shared.SlimeRoster`
(`goozilla`, `queen_jelly`, `klawdius`, `pumpking` at tier 6, `mecha_goo`, `goomancer` at tier 7; see Bosses below).
It replaces the old "first grab wins" Boss Slime (`Spawner.spawnBoss`, `BOSS_TIER`, `BOSS_LIFETIME`), which is gone.

## Flow (server)

| Phase | Lasts | What happens |
|---|---|---|
| `"warning"` | `BOSS.WARNING_SECONDS` | Server-wide Notify (heads-up) and `State.boss.phase = "warning"`. No model yet. |
| `"fight"` | up to `BOSS.FIGHT_SECONDS` | A wild slime with `boss = true` wanders the boss area round the plaza boss spot (below), `BOSS.SCALE` x its size, prompt disabled. Bat hits fill the goo meter. |
| `"haul"` | up to `BOSS.HAUL_SECONDS` | The boss stops where it stood and pops to carry size (scale 1, prompt "Grab", hold 0). Carried through `Carry` like a wild slime. |
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
  Each `BOSS.SHED_EVERY` of the meter crossed for the first time sheds `BOSS.SHED_COUNT` wild slimes (luck
  `BOSS.DROP_LUCK`, outside the wild cap). The full meter starts the haul.
- **Wander (`Shared.BossWander`, pure).** In the fight the boss walks laps of one smooth loop without stopping, at
  `BOSS.WANDER_SPEED` (it speeds up from a stand over its first second), in a direction seeded per boss. The loop is a
  racetrack laid along the boss area's strip: two long sides half a track width either side of the strip's (smoothed)
  middle, joined by round ends as wide as the track, so it never stops, snaps round or turns on the spot. It starts at
  the loop point nearest the boss spot. The boss area is the plaza inside the parade lane, within `BOSS.WANDER_ARC`
  radians either side of `BOSS.SPOT_ANGLE`: its Body (radius `SLIME_BASE_DIAMETER x MAX_SIZE x BOSS.SCALE / 2`) outside
  the landing ring (`Fountain.LANDING_RING_OUTER`), its centre at least `BOSS.WANDER_CLEARANCE` from the lane's edge
  and the goo drain's lip. Every point of the loop is in the area.
- **Hits.** The Bat (`BatTool.swing`, no remote): a carrying thief or boss carrier in reach is tried first (the slap);
  otherwise the boss in the fight phase is hit when its Body is within `BOSS.HIT_REACH` and in front (`BatRules`).
- **Haul.** For the first `BOSS.PRIORITY_SECONDS` only the top contributor may grab it (if still on the server); then
  anyone. The carrier walks at `BASE_WALK_SPEED x (1 - BOSS.CARRY_SLOW)`: no Speed Coil, no Strong Arms
  (`Carry.walkSpeed`). A Bat slap (reach `SLAP_REACH`, the shared slap cooldown) or `Request("Drop")` drops it on the
  spot; anyone can grab it again. Dropping never resets the haul deadline.
- **Win.** The carrier reaches their HomeZone (`Carry.deposit`, no free pad needed): the boss slime goes to
  `data.trophies` (below), a server-wide toast names the winner.
- **Fail.** Meter not full by the fight deadline, or not home by the haul deadline: the boss (carried or not) is removed:
  it gets away. No slimes drop; the sheds are the fight's reward.
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
system's own table is where they live once it is built.

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

## Trophies: `data.trophies` (save)

`data.trophies: { Slime }`, at most one per boss species, saved in the profile. No `SAVE_VERSION` bump: a save without
the field has none; `SaveData.cleanTrophies` keeps sanitized slimes of a boss species only (first per species, `pad` nil).

- A trophy slime: the boss species (its name, colour and mesh), the boss tier, size `MAX_SIZE`.
- Trophies earn income (added to `PlayerData.incomePerSecond` like a pad slime) and are not in `data.slimes`, so they
  can't be stolen, merged, sold or placed on a pad.
- Shown on the owner's plot on gold pedestals at `WorldLayout.TROPHY_SPOTS` (server `WorldView`, boss mesh through
  `SlimeMesh`): slots 1 and 2 on the back corners either side of the Dex board, slot 3 on a front corner, all on the
  Base clear of the jar and its moat.

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
	trophies: number, -- this player's trophy count
}
```

Every phase change, meter change and grab / drop pushes State to every player (`World.markAllDirty`).

## Request actions

None new. Hits are Bat swings (no remote), grabs are the slime's ProximityPrompt (`Carry.grab`), drops are the existing
`Request("Drop")`.

## Config (`Config.BOSS`)

`FIRST_AT INTERVAL WARNING_SECONDS RAIN_GAP SKIP_DELAY FIGHT_SECONDS HAUL_SECONDS LINGER_SECONDS PRIORITY_SECONDS
POINTS_PER_PLAYER HIT_GAP HIT_REACH DRAIN_PER_SECOND DRAIN_GRACE SHED_EVERY SHED_COUNT DROP_LUCK CARRY_SLOW
SCALE SPOT_ANGLE SPOT_RADIUS WANDER_ARC WANDER_SPEED WANDER_CLEARANCE ROTATION SECRET_FOUNTAIN_TIER SECRET_FALLBACK
TROPHY_GAP`. Values live in `Config.luau` only.

## World / Scene

- `world.boss: BossEvent? = { fight: BossFight.State, slimeId: string? }`, `world.bossIndex` (rotation position).
- `Wild.wanderUntil: number?` on the boss slime: the server time the haul started (`BossEvent`); its wander pose is
  frozen there.
- `Scene.Entry.bossScale` (`BOSS.SCALE` in the fight phase, else nil = 1) and `promptEnabled` only in the haul phase.
  WorldView walks an undropped boss along its `BossWander` plan (seeded from the slime id, starting at its arrival) every
  frame of the fight and leaves it at the pose of `wanderUntil` in the haul; never on the parade lane or the fountain
  ride. The model keeps attribute `Boss = true`.
- While it walks (undropped, wild) the model also carries `BossWalkSeed` (`BossWander.seed` of its id), `BossWalkAt`
  (its arrival, server time) and `BossWalkUntil` (the haul start, nil while it fights); any other state clears them. The
  client builds the same plan and draws the pose at `GetServerTimeNow` every frame, so the walk runs at frame rate,
  not at replication rate.
