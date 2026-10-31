# Obby sections: the section kit (contract)

The obby course is rebuilt from 25 section ideas (Merijn's picks, 2026-10-31), each with many variants. This file is
the one contract every piece builds against: the section module format, the part fields, motions, triggers, keys,
zones and controllers, the looks, and the test rules. `contract/obby.md` still holds the run rules (portal, no
checkpoints, finish, boost); where they disagree on sections, this file wins.

Variant designs (what each variant is): `docs/obby-variants/<id>.json` (copied from the agents' drafts), shown on
the variants page. Build every variant listed there, tuned per "Difficulty" below.

## 1. Layout

```
src/shared/ObbyCourse.luau          core: types, pick, build, floors, spans, frames (no section builders any more)
src/shared/ObbySections/init.luau   registry: requires every idea module, exposes ObbySections.ALL / byId
src/shared/ObbySections/Kit.luau    shared builder helpers (slab, hazard, row, chevrons, ...): see §6
src/shared/ObbySections/<Id>.luau   one module per idea (Id = PascalCase name: CrusherAlley, MeltingFloor, ...)
src/visuals/client/ObbyFx.luau      plays motions, triggers, keys, hazards (client)
src/visuals/client/ObbyMoves.luau   character controllers: boost, slide, sticky, vine, cannon, moon, dark (client)
src/visuals/client/ObbyFall.luau    fall + hazard reset (exposes ObbyFall.reset(reason))
src/visuals/shared/ObbyParts.luau   Part -> Instance, looks, attributes, readability decor
tests/ObbyCheck.luau                reusable checks (makeable path, reach, part count, widths, fairness runner)
tests/ObbySections.spec.luau        runs ObbyCheck over every variant of every idea; rotation tests
tests/obby/<Id>.spec.luau           optional idea-specific specs (generators, fairness)
```

Lune requires use the existing pattern: `if script then require(script.Parent.X) else require("./X")`.

## 2. Section module format

```lua
-- src/shared/ObbySections/CrusherAlley.luau
local Kit = if script then require(script.Parent.Kit) else require("./Kit")
local M = {}
M.id = "CrusherAlley"
M.name = "Crusher Alley"            -- shown in the run card
M.idea = 1                           -- number on the ideas page
M.variants = {                       -- array; index = variant number (stable: append, never reorder)
	{ name = "First Slam", tier = "easy", build = function(seed: number): Kit.Section ... end },
	...
}
-- optional: M.generator = { tiers = { "medium", "hard" }, build = function(seed, tier) ... end, examples = 6 }
return M
```

* `build(seed)` returns `{ length, rise, parts }` in section-local coords (x forward from the section start, y up
  from the entry floor top, z right; the lane is z in [-12, 12]). `seed` is a positive integer; hand-made variants
  may ignore it. A generator variant must be deterministic for a seed (use `Rng`).
* Every variant starts with a step at x in [0, 4] and y = 0 and ends with a step reaching `x = length`, top at
  `rise`. The course adds a jelly connector between sections and keeps the lane centred.
* Parts flagged `step = true` are the walking path in order (`route` tags allow branches, §3).

Picking (ObbyCourse.pick): ORDER stays 3 easy, 3 medium, 2 hard. For each slot it picks an idea not used in this
course nor the one before (chain rule as today), then a variant of that idea with that tier (or the idea's
generator if it covers the tier; a generator counts as one more variant). An idea with no variant of a tier is
skipped for that slot. `Pick = { id, tier, variant, seed }`. `ObbyCourse.NAMES` is replaced by
`ObbySections.byId[id].name`. `Config.OBBY.SECTIONS` and `LAYOUTS` go away.

## 3. Part fields (ObbyCourse.Part)

Existing: `size, pos, look, shape, ghost, motion, conveyor, ice, step, tone, link`. New:

| field | type | meaning |
|---|---|---|
| `yaw`, `pitch`, `roll` | number (deg) | rotation of the part (ramps, curves, banked turns, tilted pads). Applied Y then X then Z in course-local axes. |
| `hazard` | boolean | red see-through goo (look `hazard` forced). Touching it = `ObbyFall.reset("hazard")`. Not a floor. CanCollide false. |
| `route` | string | branch tag for steps: nil = main path, else "fast" / "safe" / "secret" / "key" / any name. Checks run per route (main + that route). |
| `boost` | { speed, carry } | standing on it sets the local WalkSpeed to `speed` (studs/s); it eases back to 16 `carry` s after you leave. `speed < 16` slows (back strips). |
| `slide` | { pull, cap } | slippery slide controller while standing on it (§7). Implies the ice look. |
| `sticky` | { fall } | sticky wall: in the air touching it you hold on and slide down at `fall` studs/s; jump throws you off (§7). |
| `vine` | { reach } | swing rope end: touching within `reach` of the part's bottom grabs it (§7). Use with motion `swing`. |
| `cannon` | { power, arc } | cannon seat (§7). Use with motion `sweep`. |
| `zone` | { kind, ... } | an invisible box the client checks the root against: `kind = "moon"` (`gravity` factor 0.2-0.6), `"dark"` (`light` radius studs), `"lift"` handled by motion lift. Ghost. |
| `key` | string | a pickup of key group G (§5). Ghost, floats, sparkles. |
| `gate` | { group, need } | solid until the local player holds `need` keys of `group`; then opens (fades, not solid). |
| `trigger` | string | touching it (standing on it or entering it) starts the per-player clock of group G (§5). |
| `start` | string | this part's motion runs on the per-player clock of group G instead of server time (§5). |
| `marker` | string | readability decor kind to add (§8): "rings1".."rings3", "chevrons", "arrows", "handprints", "cracks", "star", "rail", "ghostStop", "sign:<text>". |
| `beat` | number | snap this part's motion period to the beat clock: period = `beat` beats at `Kit.BPM`. |

## 4. Motions (ObbyCourse.Motion `kind`)

Kept as they are: `slide, spin, melt, flip, shrink, bounce, lift, swing, rock, roll, gust`. `punch` stays, but a
punching part must be a `hazard` (it no longer shoves: touching = reset). Changes and new kinds:

| kind | params | behaviour |
|---|---|---|
| `melt` | `delay, away, on, spread` | `on = "land"` (default) or `"leave"`; `away = -1` = gone until the player is reset to the start pad; `spread` = seconds after this tile melts that tiles listed in `next` (indices into the section's parts, resolved to names by ObbyParts) start melting. Warning look: cracks + darkening over `delay`, faster crack ticks. |
| `flip` | + `solid` | `solid = true`: only the glow blinks on and off (glow-only pulse); the part stays solid. |
| `bounce` | + `throw, duty, period, phase` | `throw = {x,y,z}` course-local launch velocity added on top of `power` up (tilted pads). With `duty`, it only throws while `cycle < duty` (geysers: rim glows `warn` s before). |
| `lift` | + `duty, period, phase, cap` | timed column when `duty` is set (on while `cycle < duty`, swirl fades 0.8 s before off). `cap` = height above the part bottom where you hover instead of rising. Entering sets your upward speed (catches a fall). |
| `path` | `points, period, hold, loop, once` | moves through course-local offsets `points` (first = rest = {0,0,0}); `hold` seconds at each point; `loop = true` returns to the first point by going on, else ping-pongs; `once = true` (with `start`) runs a single trip then stays. Carries a standing player (sets AssemblyLinearVelocity). Rides, sliding walls, rolling balls (`spinRoll = true` turns a ball), drips (one-way: `loop = true` with a `jump` back), orbits (points on a circle). |
| `sink` | `depth, speed` | lowers while the local player stands on it, rises back once they leave. |
| `rise` | `speed, delay, stop` | flood: moves up at `speed` studs/s after `delay`, on its `start` clock, up to `stop` studs; a `hazard` part. |
| `drop` | `at` | collapse: on its `start` clock, cracks 0.8 s before `at` s, then falls away (not solid). `at` per piece (Kit.collapseTimes computes them from the path distance). Back when the player is reset. |
| `sweep` | `amp, period, hold` | turns round its vertical axis between `-amp` and `+amp` degrees with `hold` seconds at each end (cannon aim, turning gates). |
| `turn` | `period, duty` | a belt whose `conveyor` points one way while `cycle < duty` and the opposite way after; chevrons flip, glow + tick 1 s before. |
| `pattern` | `beats, period` | a crusher/puncher/flip running a list of beats over one period: `beats = { {at, kind, amount} }` (kind "slam" / "half" / "rest"). Used with `axis`, `amp`. |

Every motion reads time as: `t = start and (os.clock() - startedAt[start]) or workspace:GetServerTimeNow()`. A part
with `start` whose group has not started sits at rest (cycle 0).

## 5. Triggers, keys and resets (client, per player)

* `trigger = G` part: first touch starts clock G (`startedAt[G] = os.clock()`), plays a soft "go" tick.
* `start = G` parts read that clock. Flood, collapse, chaser walls, waits-for-you rides, one-shot geysers and
  gate countdowns all use this.
* `key = G` part: touching hides it, chime, `keys[G] += 1`; `gate = {group = G, need = n}` opens when `keys[G] >= n`
  (lock icons on the gate fill one per key).
* On every reset to the start pad (fall or hazard), ObbyFx clears all clocks, keys, melted-until-reset tiles and
  collapsed pieces, and puts every per-player part back at rest.
* The server does not see per-player parts. A gate skip is possible for exploiters; accepted for now (the boost is
  small). `contract/obby.md`'s "skipped section" rule still marks gross skips invalid.

## 6. Kit helpers (src/shared/ObbySections/Kit.luau)

Pure Luau, no Roblox APIs. At least:

* `Kit.WIDTH = 24`, `Kit.FLOOR_MIN = 8`, `Kit.BEAM_MIN = 3`, `Kit.THICK = 1`, `Kit.BPM = 100`, `Kit.beat(n)` seconds.
* `Kit.slab(x, top, z, sx, sz, look, extra?)` (as today), `Kit.prop(size, pos, look, extra?)`, `Kit.row(...)`.
* `Kit.hazard(size, pos, extra?)` (sets `hazard = true`, look "hazard").
* `Kit.ramp(x0, top0, x1, top1, z, width, look, extra?)` a pitched slab between two points.
* `Kit.wall(x, z, length, height, alongX, extra?)` solid jelly maze wall, 9 studs tall by default.
* `Kit.collapseTimes(points, speed, headStart)` path distance -> drop times.
* `Kit.section(length, rise, parts)` builds the table and asserts the first/last step rules.
* `Kit.rng(seed)` = `Rng.new(seed)`.
* Gap/rise constants the checks use: `Kit.GAP_MAX = 6`, `Kit.RISE_MAX = 3.5` (walk + jump), `Kit.GRAVITY = 196.2`,
  `Kit.WALK = 16`, `Kit.launchReach(power, rise, throw?)`.

## 7. Character controllers (src/visuals/client/ObbyMoves.luau)

One module, one `tick(dt)` a frame, only while ObbyLook.isInside. Each controller restores the character exactly
when it ends (WalkSpeed 16, gravity, camera) and on every reset.

* **boost**: WalkSpeed to `boost.speed` while on the part, eases to 16 over 0.3 s, `carry` s after leaving.
* **slide**: on a `slide` part you keep your horizontal velocity, the slope adds `pull` downhill, walking input
  only steers (a quarter of normal accel), speed capped at `cap`. Brake goo (`sticky` look floor, not a wall)
  stops the slide.
* **sticky**: airborne and within 1.2 studs of a `sticky` wall face: horizontal speed into the wall zeroed, fall
  speed held at `sticky.fall`; jump throws you off at 30 studs/s away from the face + 45 up. Squelch on stick.
* **vine**: touching the rope end grabs it: the root follows the end's CFrame each frame (humanoid PlatformStand);
  jump lets go with the end's velocity + 20 up. "Jump to let go" hint the first 3 grabs.
* **cannon**: walking into the barrel snaps you in (PlatformStand, camera behind the barrel); jump fires: your root
  follows the fixed arc for the barrel's current aim (`power`, `arc` degrees up) and is handed back to physics 2
  studs above the landing. A dotted aim line shows the arc (red where it would hit a hazard or miss).
* **moon**: inside a `moon` zone a VectorForce cancels `(1 - gravity)` of workspace gravity on the character.
* **dark**: inside a `dark` zone Lighting fades to night over 0.6 s (via ObbyWorld's restore so nothing leaks) and
  a PointLight of `light` studs sits on the root. Leaving fades back.
* The fall/hazard reset (`ObbyFall.reset`) ends every controller first.

## 8. Readability (ObbyParts looks and markers)

One look per behaviour, same everywhere, plus a sound when it acts:

| behaviour | look |
|---|---|
| hazard | `hazard`: red (235, 70, 90), transparency 0.45, SmoothPlastic, slight pulse |
| sticky | `sticky`: lime green with drip parts on the bottom edge + `handprints` marker; squelch |
| bounce | `spring`: orange pad + 1-3 ring markers for its power; boing |
| slippery | `ice` (exists): glossy pale blue + frost sparkle emitter; skid sound |
| wind / lift | `wind` column with rising leaf particles and rings at the top; fan hum |
| speed / belt | yellow `boost` strip / belt with `chevrons` marker pointing the way; whoosh / hum |
| about to fall | cracks + darkening during the melt/drop warning; crack ticks speeding up |
| timing / beat | pulsing glow + tick on the beat |
| key / gate | gold key with sparkles; gate with lock icons |
| moon / dark zones | see-through bubble dome with sparkles / darker tint |

No Neon on large parts (it blooms); small Neon details are fine. No Glass. Markers are extra decor parts (ghost,
no collision, CanQuery false) and count toward the part budget. Sounds: use existing game sound helpers if any,
else `rbxasset://sounds/...` built-ins; never upload audio. Every sound is quiet and short.

## 9. Checks every variant must pass (tests/ObbyCheck + ObbySections.spec)

* Builds for seeds 1..20 without error; same seed = same parts.
* <= 80 parts including markers. Length 30..110 studs. Lane: every part within z [-12, 12].
* Floors you run on are >= 8 studs across the course direction you cross them (`Kit.FLOOR_MIN`); beams >= 3. The
  check: every `step` part has min(size.x, size.z) >= 3 and steps that are not beams (`look ~= "beam"`) >= 8 wide
  across the walking direction.
* Makeable path per route: every step reachable from the one before by walk/jump (gap <= GAP_MAX, rise <=
  RISE_MAX), launch (`launchReach`), lift, climb, sticky chain, vine release, cannon arc or boost jump, measured
  at the worst point of any motion (moving parts: closest-gap over 32 samples of a period).
* No straight-forward walk crosses the section (the existing check, routes included).
* Hazard fairness: a runner at 16 studs/s who loses 0.15 s per jump must find every hazard open for at least
  `WINDOW[tier]` seconds (easy 1.4, medium 1.0, hard 0.75) in some cycle; flood/collapse leave at least 1 s spare.
* Only motion kinds and fields from this file. Every `start` group has a `trigger`; every `gate` has enough keys
  reachable on its route.
* Fall height never resets a runner above a platform they could land on (existing check).
* **Walk-forward test (Merijn, 2026-10-31): just walking forward, no jumping, must never clear a section.** Two
  layers: the straight-walk check above runs for every variant, every route and seeds 1..20 (a walker holding
  forward, following moving floors, belts and boosts it lands on); and a Studio walk bot (verification step) holds
  forward from each section's first step in a real playtest and fails any section it reaches the end of. A variant
  that fails is tightened, not dropped.

## 10b. How data reaches the client (fixed, so the pieces can be built in parallel)

* `ObbyCourse.build` gives every part a unique `id` string `"<section>.<index>"` (start/finish/links: `"s"`, `"f"`,
  `"l<n>"`) and rewrites section-local references (`motion.next` indices) to those ids.
* ObbyParts sets on the Course model `ObbyFrame` (CFrame: origin, X forward, Y up, Z right, i.e. the course frame).
* Every part gets `ObbyId` (its id). A part with any behaviour (motion, hazard, boost, slide, sticky, vine, cannon,
  zone, key, gate, trigger, start, beat, conveyor, marker) also gets `ObbySpec`: `HttpService:JSONEncode` of exactly
  those fields, values course-local as in the data, and `ObbyBase` (its rest CFrame in world space). The old
  per-field attributes (ObbyMotion, ObbyAxis, ...) are dropped; ObbyFx and ObbyMoves read `ObbySpec` and convert
  course-local vectors with `ObbyFrame` (`frame:VectorToWorldSpace(Vector3.new(x, y, z))`).
* Attribute names live in Constants: `OBBY_SPEC = "ObbySpec"`, `OBBY_FRAME = "ObbyFrame"`, `OBBY_ID = "ObbyId"`,
  `OBBY_BASE = "ObbyBase"` (kept).

## 10. Difficulty: not too easy (Merijn, 2026-10-31)

The old course was too easy. Tiers shift up one notch from the drafts:
* **easy** = what the drafts called medium-easy: always at least one timing element or hazard; no section that is
  just walking. Windows <= 2.0 s.
* **medium** = the drafts' hard-but-fair; two mechanics overlapping (e.g. hazards on moving rides). Windows 1.0-1.4 s.
* **hard** = tight: windows 0.75-1.0 s, small margins, long sequences without a rest. Still passes every check.
Where a draft variant is too easy for its tier after this shift, tighten its numbers (shorter windows, longer
gaps up to the limits, more hazards, faster motions); don't drop it.

## 11. Settled while building the kit (these win over earlier wording)

* Rotation: `CFrame.fromEulerAnglesYXZ(rad(pitch), rad(yaw), rad(roll))` in the course frame. A positive `roll`
  lifts the part's forward (+x) end: that is how a ramp climbs (`Kit.ramp` sets it). `pitch` banks sideways.
* `Pick = { id, tier, variant, seed }`; `variant = 0` is the idea's generator. Part ids: `s` start, `h` home catch
  pad, `f` finish, `l<n>` connectors, `<section>.<index>` section parts; `motion.next` holds those ids.
* Motion timing has ONE source of truth: `Kit.offsetAt / pathAt / patternAt / sweepAt / punchAt / conveyorAt`. The
  checks sample them and ObbyFx plays them, so what a player sees is what the checks measured.
* Markers are anchored direct children of their host part (ObbyFx moves and fades them with it); `ghostStop` stays
  in the Course model with `ObbyHost`. `ObbyCheck.MARKER_PARTS` mirrors `ObbyParts.MARKER_PARTS` (keep in sync).
  Gate locks are `Lock1..LockN` (need <= 9).
* Walk-forward check: a 2-stud walker stepping up 1-stud ledges crosses holes shorter than about 3.6 studs, so every
  walking line needs a gap >= 4, a wall, or an always-present hazard. Pads, lifts, belts, boosts and moving floors
  carry the walker.
* Width check exempts ladders, wind columns, sticky walls, vines and cannons; bounce pads still need 8.
* Sounds: only the built-in `rbxasset://sounds/` files (volume_slider, action_jump, action_jump_land,
  action_footsteps_plastic, impact_water) at different pitches, through `ObbyFx.sound(name)`.
* Dark zones tint with their own ColorCorrection ("ObbyMovesDark"), never writing Lighting.
