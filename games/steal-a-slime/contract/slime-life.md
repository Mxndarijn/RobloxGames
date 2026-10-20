# 39. Slime life: species gaits, hops, lane beats and reactions

**Status:** contract first. Flag `FEATURES.SlimeChoreo` (needs `Parade` for the lane part). Server: a pure plan per lane
slime and three model attributes. Everything else is client-only cosmetics on top of the replicated pivot: no remote,
no State field, no save.

Wild slimes on the goo lane glide at one pace today (§37). With this flag each species moves its own way, lane slimes
stop now and then for a small beat (and catch up), and the slimes near you react to you and to each other.

## Persona: gait and temperament per species (`Shared.SlimePersona`, pure)

`SlimePersona.of(speciesId) -> Persona` = `{ gait, temper, hop }`. Every `SlimeRoster` id has an entry; an unknown id
gets `SlimePersona.DEFAULT`. One table, read by the server (temperament picks the beats) and the client (gait, reactions).

- **Gait** (how the body moves): `"Hop"`, `"Ooze"`, `"Waddle"`, `"Float"`, `"Scoot"`.
- **Temperament** (which beats, how it reacts): `"Bouncy"`, `"Lazy"`, `"Curious"`, `"Shy"`, `"Showoff"`, `"Feisty"`.
- **Hop** (hop gait only): `{ height, air, wait, settle }`, studs at size 1 and seconds; `wait` = studs the anchor gets
  ahead before the next jump (longer leaps), `settle` = seconds of landing wobble before the next squat.

## Lane beats (`Shared.ParadeChoreo`, pure; server authoritative)

- `ParadeChoreo.seedFor(id) -> number`, `ParadeChoreo.plan(seed, temper, walkSeconds, leadSeconds) -> Plan`. The plan is a list of
  beats, each `{ kind, t0, s0, s1, stop, pre, side }` in seconds since the walk starts (the slide mouth,
  `spawnedAt + RIDE_SECONDS`), and the matching speed keys.
- A beat: an optional run-ahead (`pre`, speed `CATCH_SPEED` x), a stop of `stop` seconds (speed 0), then a catch-up at
  `CATCH_SPEED` x. Speed changes ramp over `RAMP` seconds and every beat nets out to zero, so
  `ParadeChoreo.offset(plan, t)` (studs ahead of the plain lane spot) is 0 between beats and at the end of the walk.
  `|offset| <= LEASH` seconds of plain walking (`LEASH x walkSpeed` studs), speed stays in `0..CATCH_SPEED` x. No beat in the lead-in, none in the last
  `QUIET_END` seconds of the walk (the despawn telegraph is the slime's last act).
- Beat kinds: `look sniff slurp nap trip spin cheer hide zoom huff stuck`. Weights per temperament in
  `ParadeChoreo.WEIGHTS`.
- Server: `Spawner.spawnOne` gives a lane wild `wild.choreo = { seed }` (flag on, Parade on). A **copycat**: when the
  previous lane wild has the same species and spawned within `COPY_WINDOW` s, the new one sometimes (hash of its id,
  no `world.rng` roll) takes that slime's seed, so it repeats the same beats at the same lane spots.
  `ParadeLane.pose(..., offset)` adds the offset to the lane distance (clamped to the lane). A drop clears
  `wild.choreo` (the slime walks back and rejoins with a plain glide, §37).
- **Model attributes** (`Constants`), set by `WorldView.place` on a lane wild with a plan, nil otherwise:
  `ChoreoSeed: number`, `LaneAt: number` (= `spawnedAt`), `LaneUntil: number` (= `expiresAt`), server time
  (`workspace:GetServerTimeNow()`). The client rebuilds the same plan from them and the `Species` attribute, so a
  beat costs no replication.

## Client life (`src/ui`)

All of it runs inside `SlimeLifeRunner`'s one frame loop, only for the `SlimeLife.MAX_ACTIVE` near rigs (LOD "near";
mid and far tiers keep today's squish / rest). Pure parts have Lune specs. With the flag on every rig runs on the
procedural `SlimeMotor` path (the uploaded KeyframeSequences of `FEATURES.SlimeAnimations` stay off), since the life
rides on its Transform and the species bones. On the slide itself (`Riding` and less than `RIDE_SECONDS` since
`LaneAt`) the gait waits; the lead-in from the slide mouth already walks.

- **Gaits (`ui/SlimeGait`, pure).** The visible slime is offset from the replicated Body by the `SkinRoot` /
  `FaceRoot` Motor6D `Transform` (Body never moves). Anchor velocity = the Body's own movement, smoothed.
  - `Hop`: real jumps. It waits on the ground while the anchor moves on, squats (`CROUCH` s), jumps a parabola to where
    the anchor will be when it lands, stretches on the way up and down, tilts with the arc, splats on landing and
    wobbles (`1 - A e^{-7t} cos(17t)`). The visible slime is never more than one leap from the Body. Rhythm: normal,
    normal, big. Variants: `boing` (huge jump with a flip, Bouncy), `belly` (belly flop, Bouncy / Curious),
    `zig` (to the other side of the lane), `small` (after a boing or a flop).
  - `Ooze`: inchworm surges, `Waddle`: side-to-side rocking steps, `Scoot`: short pushes, `Float`: hovers and bobs.
    All locked to the distance moved, so a stopped slime stands still.
- **Beat poses (`ui/SlimeBeats`, pure).** The client looks the beat up in the plan at `GetServerTimeNow()` minus
  `SlimeActor.REPLICATION_LAG` (the Body arrives that late) and poses
  the slime (turns, leans, squash, lift) with an expression and an emote.
- **Reactions (`ui/SlimeReact`, pure).** Within `REACT_DISTANCE` of the local character: affordable (leaderstats
  `Cash >= Price`) and within `NEAR` = "pick me" (faces you, bounces, ♥); otherwise by temperament (Shy shrinks away,
  Showoff turns its back, Feisty glares and stamps, Lazy barely looks, Curious watches you). Nerves in the last
  `NERVES_SECONDS` before `LaneUntil`. Social: a neighbour within `STARTLE_DISTANCE` of a slime that turns `Carried`
  startles and watches it; slimes near the drain watch a slime sink; a slime that catches up with the one ahead bumps it.
- **Faces.** Through the existing bones: `Lids` close for happy / asleep / squeeze, `Eyes` push out a little for
  surprised (`SlimeBones` face override). Species faces stay as modelled.
- **Emotes (`ui/SlimeEmotes`).** One small BillboardGui per slime from a pool of at most `MAX_EMOTES`, nearest first:
  `♥ ! ? ★ ♪ … z ✶ #` and a sweat drop.
- **Hop effects.** Landing splat: `Emit` on one pooled ParticleEmitter per rig. Goo string: one Beam per rig from the
  take-off spot to the slime for the first quarter of the jump.
- **Cleanup.** Releasing a rig (LOD, state change, despawn) puts every Transform back, hides its emote and destroys
  its emitter and beam.

## Slimes never walk into each other (server)

- **Slide slots (`Spawner.slot`).** Every drop (regular, Mystery Egg or boss shed) takes the next free
  fountain-slide slot, at least `Spawner.SLIDE_GAP` seconds after the last one (`world.slideFreeAt`). A drop whose slot
  is still to come exists in World (it counts for the cap) but has no model yet (`Scene.describe` skips it).
- **Lane queue (`Shared.LaneTraffic`).** One loop in `WorldView` pivots every lane walker each Heartbeat. Front to back,
  a slime is never drawn closer to the slime ahead (when their sideways places overlap) than their two radii plus
  `LaneTraffic.GAP`; it waits, then catches up at most `LaneTraffic.CATCH_SPEED` x its pace, never backwards. The hold
  is capped by `LaneTraffic.holdLimit` (what it can still make up), so it reaches the drain on time.
- **Walking back.** A dropped slime walking back to the lane steps round other slimes and the boss
  (`LaneTraffic.push`), easing back onto its path and arriving exactly on the merge point.

## Smooth on the client

The Body replicates in steps. `SlimeActor` draws a lane slime from its lane math (the server's own `ParadeLane.pose`
plus its beats, at `GetServerTimeNow() - REPLICATION_LAG`) with a slow correction towards the Body (`CORRECT_RATE`;
it absorbs the lane queue), and anything else from a filtered Body. Turns are capped at `MAX_TURN`; within
`NEAR_DEAD_ZONE` of the player the slime keeps its last look. Wiggles stay around 1-2 Hz. A face shuts the eyes only
fully and only on a mesh with `Lids` (a half-shut blink pose leaves the eyes sunk with no arcs).
