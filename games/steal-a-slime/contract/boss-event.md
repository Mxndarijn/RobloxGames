# §33 Boss event: a server-wide fight, a haul race, a trophy

Design: `docs/SLIME-ECONOMY.md` §3. The boss is one of the three `kind = "boss"` species in `Shared.SlimeRoster`
(`goozilla`, `queen_jelly` at tier 6, `mecha_goo` at tier 7). It replaces the old "first grab wins" Boss Slime
(`Spawner.spawnBoss`, `BOSS_TIER`, `BOSS_LIFETIME`), which is gone.

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
- **Rotation.** `BOSS.ROTATION` in order (`goozilla queen_jelly goozilla queen_jelly mecha_goo`), looping. A Secret-tier
  slot (`mecha_goo`) needs `world.fountainTier >= BOSS.SECRET_FOUNTAIN_TIER` (Starlight); otherwise it is
  `BOSS.SECRET_FALLBACK`.
- **Meter (`Shared.BossFight`, pure).** One point per Bat hit per player, at most one per `BOSS.HIT_GAP` seconds each.
  Target = `BOSS.POINTS_PER_PLAYER` x players on the server (at least 1), read live. With no hit for `BOSS.DRAIN_GRACE`
  seconds it drains `BOSS.DRAIN_PER_SECOND` of the target per second. Every player's points are kept (they never drain).
  Each `BOSS.SHED_EVERY` of the meter crossed for the first time sheds `BOSS.SHED_COUNT` wild slimes (luck
  `BOSS.DROP_LUCK`, outside the wild cap). The full meter starts the haul.
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
- **Hits.** The Bat (`BatTool.swing`, no remote): a carrying thief or boss carrier in reach is tried first (the slap);
  otherwise the boss in the fight phase is hit when its move's pose is within `BOSS.HIT_REACH` and in front
  (`BatRules`).
- **Haul.** For the first `BOSS.PRIORITY_SECONDS` only the top contributor may grab it (if still on the server); then
  anyone. The carrier walks at `BASE_WALK_SPEED x (1 - BOSS.CARRY_SLOW)`: no Speed Coil, no Strong Arms
  (`Carry.walkSpeed`). A Bat slap (reach `SLAP_REACH`, the shared slap cooldown) or `Request("Drop")` drops it on the
  spot; anyone can grab it again. Dropping never resets the haul deadline.
- **Win.** The carrier reaches their HomeZone (`Carry.deposit`, no free pad needed): the boss slime goes to
  `data.trophies` (below), a server-wide toast names the winner.
- **Fail.** Meter not full by the fight deadline, or not home by the haul deadline: the boss (carried or not) is removed:
  it gets away. No slimes drop; the sheds are the fight's reward.
- Bosses never count toward the wild cap and are never a random merge or fountain result.

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
SCALE SPOT_ANGLE SPOT_RADIUS WANDER_ARC WANDER_CLEARANCE STROLL_* LOOK_SECONDS ARRIVE_* WINDUP_SECONDS CHARGE_EASE
STRIKE_SECONDS RING_DELAY SPIT_FLIGHT DAZED_SECONDS RISE_* LAND_SECONDS GUARD_SECONDS SHRINK_SECONDS
MOVE_PIVOT_INTERVAL ROTATION SECRET_FOUNTAIN_TIER SECRET_FALLBACK`. Values live in `Config.luau` only.

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
