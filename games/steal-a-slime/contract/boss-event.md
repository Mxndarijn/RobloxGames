# §33 Boss event: a server-wide fight, a haul race, boss badges

Design: `docs/SLIME-ECONOMY.md` §3. The boss is one of the three `kind = "boss"` species in `Shared.SlimeRoster`
(`goozilla`, `queen_jelly` at tier 6, `mecha_goo` at tier 7). It replaces the old "first grab wins" Boss Slime
(`Spawner.spawnBoss`, `BOSS_TIER`, `BOSS_LIFETIME`), which is gone.

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
- **Rotation.** `BOSS.ROTATION` in order (`goozilla queen_jelly goozilla queen_jelly mecha_goo`), looping. A Secret-tier
  slot (`mecha_goo`) needs `world.fountainTier >= BOSS.SECRET_FOUNTAIN_TIER` (Starlight); otherwise it is
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
- **Win.** The carrier reaches their HomeZone (`Carry.depositBoss`, no free pad needed): a server-wide toast names the
  winner and every helper is credited in their boss record (below). The boss slime is removed; it never goes into
  `data.slimes` or anywhere else in the save.
- **Fail.** Meter not full by the fight deadline, or not home by the haul deadline: the boss (carried or not) is removed:
  it gets away. No slimes drop; the sheds are the fight's reward.
- Bosses never count toward the wild cap and are never a random merge or fountain result.

## Boss record and badges: `data.boss` (save v9)

Boss badges are kept in the player's save, not on Roblox (they are unrelated to `server/Badges` and `Config.BADGES`).
A later build shows them in the base or a panel; for now they are saved, in State and toasted.

```lua
data.boss = {
	hits: number, -- counted Bat hits on any boss (BossFight.hit returned true)
	wins: { [string]: number }, -- boss species id -> wins helped
	hauls: number, -- bosses this player carried home
	mvps: number, -- won bosses where this player was the top contributor
	badges: { [string]: number }, -- Config.BOSS_BADGES key -> unix seconds (server time) it was earned
}
```

- **Triggers (`server/BossCredit`).** A counted hit in `BossEvent.hit` records a hit. When the boss is brought home,
  every player on the server whose `BossFight.share` is at least `BOSS.WIN_SHARE` gets a win for that species. The
  carrier gets a haul (and a win only through their own share). The top contributor (`BossFight.top`), if still on the
  server, gets an MVP. Every winner and the carrier get the species in their SlimeDex (`PlayerData.discover` with the
  boss slime).
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
}
```

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
POINTS_PER_PLAYER HIT_GAP HIT_REACH DRAIN_PER_SECOND DRAIN_GRACE SHED_EVERY SHED_COUNT DROP_LUCK CARRY_SLOW
SCALE SPOT_ANGLE SPOT_RADIUS WANDER_ARC WANDER_SPEED WANDER_CLEARANCE ROTATION SECRET_FOUNTAIN_TIER SECRET_FALLBACK
WIN_SHARE`, and the badge list `Config.BOSS_BADGES`. Values live in `Config.luau` only.

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
