# Obby sections: the section kit (contract)

The obby course is rebuilt from 24 section ideas (Merijn's picks, 2026-10-31; Sticky Walls removed 2026-11-02, Merijn:
"Remove the Slime wall section completely"), each with many variants. This file is
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
src/shared/ObbySections/Vine.luau   the rope swing's physics (pure), shared by ObbyMoves and the checks (§7 vine)
src/shared/ObbySections/<Id>.luau   one module per idea (Id = PascalCase name: CrusherAlley, MeltingFloor, ...)
src/visuals/client/ObbyFx.luau      plays motions, triggers, keys, hazards (client)
src/visuals/client/ObbyMoves.luau   character controllers: boost, slide, vine, cannon, moon, dark (client)
src/visuals/client/ObbyFall.luau    fall + hazard reset (exposes ObbyFall.reset(reason))
src/visuals/shared/ObbyParts.luau   Part -> Instance, looks, attributes, readability decor
tests/ObbyCheck.luau                reusable checks (makeable path, timing run, reach, part count, widths, fairness runner)
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
* Joins are flush (`tests/ObbyJoins.spec`): the first step starts at exactly x = 0 with its top at 0, the last step
  ends at exactly `x = length` with its top at `rise`, and no part's top face reaches outside x in [0, length] (a
  turn, ramp or decor that pokes back over the connector shows under it at another height). In whole courses the
  start pad, every connector and the finish meet the steps next to them with no step, gap or overlap and span them
  across the lane.
* Parts flagged `step = true` are the walking path in order (`route` tags allow branches, §3).

Picking (ObbyCourse.pick): ORDER is 2 easy, 2 medium, 2 hard (6 sections; it was 3/3/2 until Merijn asked for a 25% shorter obby on 2026-11-02). For each slot it picks an idea not used in this
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
| `vine` | { reach, hint } | a rope's grab knob: within `reach` studs of your body (feet to head) grabs you (§7); `hint` = seconds of the let-go flight the dots show. Use with motion `swing` (axis `"x"` along the course, else across). |
| `cannon` | { power, arc } | cannon seat (§7). Use with motion `sweep`. |
| `zone` | { kind, ... } | an invisible box the client checks the root against: `kind = "moon"` (`gravity` factor 0.2-0.6), `"dark"` (`light` radius studs), `"lift"` handled by motion lift. Ghost. |
| `key` | string | a pickup of key group G (§5). Ghost, floats, sparkles. |
| `gate` | { group, need } | solid until the local player holds `need` keys of `group`; then opens (fades, not solid). |
| `trigger` | string | touching it (standing on it or entering it) starts the per-player clock of group G (§5). |
| `start` | string | this part's motion runs on the per-player clock of group G instead of server time (§5). |
| `marker` | string | readability decor kind to add (§8): "rings1".."rings3", "chevrons", "arrows", "handprints", "cracks", "star", "rail", "ghostStop", "pic:<id>[,<id>...]" (asks for a picture sign banner over the part, §8b). |
| `beat` | number | snap this part's motion period to the beat clock: period = `beat` beats at `Kit.BPM`. |

## 4. Motions (ObbyCourse.Motion `kind`)

Kept as they are: `slide, spin, melt, flip, shrink, bounce, lift, swing, rock, roll, gust`. `punch` stays, but a
punching part must be a `hazard` (it no longer shoves: touching = reset). Changes and new kinds:

| kind | params | behaviour |
|---|---|---|
| `melt` | `delay, away, on, spread` | `on = "land"` (default) or `"leave"`; `away = -1` = gone until the player is reset to the start pad; `spread` = seconds after this tile melts that tiles listed in `next` (indices into the section's parts, resolved to names by ObbyParts) start melting. Warning look: cracks + darkening over `delay`, faster crack ticks. **Trapdoor** (`Kit.trap()`: `delay = 0`, `on = "land"`, `away = -1`): the floor of every wrong choice (Glow Memory fakes, Clue Doors wrong corridors) never holds a runner, not even for a jump: ObbyParts builds it with `CanCollide = false`, ObbyFx plays its crack and fade (`TRAP_FADE`) once the local root is over it, and tests/ObbyCheck treats it as no floor (walker and masher fall through). Safe tiles that melt keep a `delay` over 0. |
| `flip` | + `solid` | `solid = true`: only the glow blinks on and off (glow-only pulse); the part stays solid. |
| `bounce` | + `throw, duty, period, phase` | `throw = {x,y,z}` course-local launch velocity added on top of `power` up (tilted pads). With `duty`, it only throws while `cycle < duty` (geysers: rim glows `warn` s before). |
| `lift` | + `duty, period, phase, cap` | timed column when `duty` is set (on while `cycle < duty`, swirl fades 0.8 s before off). `cap` = height above the part bottom where you hover instead of rising. Entering sets your upward speed (catches a fall). |
| `path` | `points, period, hold, loop, once` | moves through course-local offsets `points` (first = rest = {0,0,0}); `hold` seconds at each point; `loop = true` returns to the first point by going on, else ping-pongs; `once = true` (with `start`) runs a single trip then stays. Carries a standing player (sets AssemblyLinearVelocity). Rides, sliding walls, rolling balls (`spinRoll = true` turns a ball), drips (one-way: `loop = true` with a `jump` back), orbits (points on a circle). |
| `sink` | `depth, speed` | lowers while the local player stands on it, rises back once they leave. |
| `rise` | `speed, delay, stop` | flood: moves up at `speed` studs/s after `delay`, on its `start` clock, up to `stop` studs; a `hazard` part. |
| `flood` | `keys` | one goo part that grows (Rising Goo; Merijn, 2026-11-01: scale one part, no new part per phase): `keys = { {t, up} }` on its `start` clock, times ascending, `up` never going down; the top surface rises `up` studs over its rest top, piecewise linear between keys (equal heights hold), 0 before the first and the last height after it (`Kit.floodAt`). Its bottom stays put: the client grows Size.Y and moves the centre up by half. The checks read it as the top moving (Kit.offsetAt's dy); a `hazard` part. |
| `drop` | `at` | collapse: on its `start` clock, cracks 0.8 s before `at` s, then falls away (not solid). `at` per piece (Kit.collapseTimes computes them from the path distance). Back when the player is reset. |
| `swing` | + `axis` | `axis = "x"` swings along the course (turning round the across axis, +angle forward); default across it. A vine rope is a real pendulum: `period = Vine.period(arm)`. |
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
* Jump pads: every bounce motion's `power` is built as `Kit.bounce(n)` = n x `Config.OBBY.BOUNCE_BOOST` (1.1, one
  tunable for every pad and geyser), so layouts and checks see the thrown speed. Measured in Studio: a launch under
  the jump speed (about 53) is just a jump, and air control wears a `throw` down at `Kit.AIR_DECEL` (120 studs/s^2),
  so a throw adds only throw^2 / 240 studs to a hop (14: 0.8, 16 across: 1.1). `launchReach`, the makeable check and
  the walker use that, not the full throw over the whole flight.

## 7. Character controllers (src/visuals/client/ObbyMoves.luau)

One module, one `tick(dt)` a frame, only while ObbyLook.isInside. Each controller restores the character exactly
when it ends (WalkSpeed 16, gravity, camera) and on every reset.

* **boost**: WalkSpeed to `boost.speed` while on the part, eases to 16 over 0.3 s, `carry` s after leaving.
* **slide**: on a `slide` part you keep your horizontal velocity, the slope adds `pull` downhill, walking input
  only steers (a quarter of normal accel), speed capped at `cap`. Brake goo (a `sticky` look floor)
  stops the slide.
* **vine** (reworked 2026-11-01, Merijn: "they are not fun"; physics in `src/shared/ObbySections/Vine.luau`, shared
  with the checks): the feel of a classic platformer rope swing. A knob within `vine.reach` of your body grabs you,
  in a jump or walking at it (on the ground only while you walk at it). You hang under it, arms up on the knob,
  body leaning with the rope, on a real pendulum (gravity `Vine.G` 110, about 2 s a swing) that keeps 85 % of the
  speed you came in with; holding the stick along the swing pumps it (26 studs/s²) up to 62°, and it fades slowly
  when you let go of the stick. A fresh jump press (not a held jump) after 0.25 s lets go: you fly off with the
  swing's speed along its arc + 12 up, and the air steering only turns or brakes that flight. While you hang, 6
  dots show the flight's first `vine.hint` s (easy 0.9, medium 0.5, hard 0.3), mint when it ends on a safe floor
  or in another rope's reach, red otherwise. The rope you leave swings on and eases back to its server-time swing
  over 0.8 s (ObbyFx reads the held angle from the knob's `ObbyHeldAngle` attribute). Squelch and a goo puff on a
  grab, a whoosh and a puff on a let go, a Beam from the knob to your hands. "Jump to let go" the first 3 grabs.
* **cannon**: walking into the barrel snaps you in (PlatformStand, camera behind the barrel); jump fires: your root
  follows the fixed arc for the barrel's current aim (`power`, `arc` degrees up) and is handed back to physics 2
  studs above the landing. A dotted aim line shows the arc (red where it would hit a hazard or miss).
* **moon**: inside a `moon` zone a VectorForce cancels `(1 - gravity)` of workspace gravity on the character.
  "Inside" is the bubble dome the zone draws (the ellipsoid inscribed in its box, `ObbyZone` shape `"ellipsoid"`),
  not the box: its ends and corners are outside, so size the box so the dome holds the route (tests/ObbyCheck and
  tests/obby/MoonJump.spec test the same dome).
* **dark**: inside a `dark` zone Lighting fades to night over 0.6 s (via ObbyWorld's restore so nothing leaks) and
  a PointLight of `light` studs sits on the root. Leaving fades back.
* The fall/hazard reset (`ObbyFall.reset`) ends every controller first.

## 8. Readability (ObbyParts looks and markers)

One look per behaviour, same everywhere, plus a sound when it acts:

| behaviour | look |
|---|---|
| hazard | `hazard`: one look for every hazard of every idea, set once in `ObbyParts.HAZARD`: danger red (215, 20, 25), transparency 0.25, SmoothPlastic, and a dark outline (90, 0, 10), 0.12 studs, on every shape (a box: a SelectionBox; a ball, log or disc: rings round its round edges plus a silhouette that faces the camera, adornments only, no parts). Whenever it can hurt you it shows exactly this. Tells and beat pulses flash toward a brighter red (255, 45, 30), never toward white (that reads pink). A hazard that is off (a flip in its off share, a fallen piece) is far more see-through with no outline. No floor, prop or jelly uses red or pink, so red always means danger; the only other hazard-red things are Rolling Blobs' launcher rim (`danger`) and the next ball waiting in it (`loaded`), and ObbyMoves' "bad" aim dots |
| brake goo | `sticky`: lime green goo with drips falling off it (Ice Slide's brake floor) |
| bounce | `spring`: orange pad + 1-3 ring markers for its power; boing |
| slippery | `ice` (exists): glossy pale blue + frost sparkle emitter; skid sound |
| wind / lift | `wind` column with rising leaf particles and rings at the top; fan hum |
| speed / belt | yellow `boost` strip / belt with `chevrons` marker pointing the way; whoosh / hum |
| about to fall | cracks + darkening during the melt/drop warning; crack ticks speeding up |
| timing / beat | pulsing glow + tick on the beat |
| key / gate | gold key with sparkles; gate with lock icons |
| moon / dark zones | see-through bubble dome with sparkles / darker tint |

No Neon on large parts (it blooms); small Neon details are fine. No Glass. Markers are extra decor parts (ghost,
no collision, CanQuery false) and count toward the part budget. Looks solid means is solid: a ghost part you
pass through is not an opaque slab at body height or over the void where it reads as a floor, wall or door. A look
used both ways sets `ghostTransparency` in `LOOKS` (a ghost `fan` vent shows as a see-through grille), and a fan
under a column over a safe floor lies in that floor (Updraft `Column.floor`). Sounds: use existing game sound helpers if any,
else `rbxasset://sounds/...` built-ins; never upload audio. Every sound is quiet and short.

## 8b. Picture signs (docs/obby-signs-proposal.html; Merijn, 2026-11-01)

Signs are pictures only: no words (no FAST, SAFE, LOW GRAVITY, ...). Digits only where the number is the message
(a stopwatch's seconds, Rising Goo's 3 2 1); no step numbers. A multi-step mechanic shows all its steps on one board,
left to right with an arrow in the gap between each (the cannon: walk in, it swings with you inside, jump when its
green aim line hits the green target ring, land in the ring).

One visual language for every picture (two blind tests of every picture by three judges: a 10-year-old player, an
adult non-gamer and an icon designer):

* Fixed colours, one meaning each: hazard red (215, 20, 25) is danger only (a hazard, a fake or breaking tile);
  green is safe / the target only (a safe tile, the lit pad in the dark, the cannon's aim line on target and its
  target ring); yellow is a thing you use (spring pads, buttons, keys, live vents, vines, the speed pad); lilac is an
  ordinary platform (belts, planks, ledges, ladders, beat pads, floors). Yellow never draws "the path" or a crumbling
  floor. Other colours only where they are that thing's own look (ice, wind, the cannon, Glow Memory's pink fakes).
  White is the runner, its jumps and the arrows.
* The mechanic is the biggest thing on the board (no corner icons carrying the message), and the runner is on every
  board that asks you to do something (status boards excepted: the shield, the speed pad, a stopwatch or countdown).
  Nothing is cropped at the slot's edge.
* White dots are only ever the runner's own jump path, evenly spaced along it; a launch (cannon, geyser vent, spring
  pad) draws the runner's path the same way. A falling or rolling hazard is a solid shape with motion streaks behind
  it, never dots.
* No lightning bolt. Speed is the yellow pad with chevrons (Speed Strip, Two Roads' fast road); chevrons mean nothing
  else. One danger tile: red with a dark rim and a crack (Glow Memory's pink fakes: the same tile in pink, rimmed
  red). "Watch" is an almond eye with a pupil.
* One arrow style (round-ended white stroke, open head) in three weights; one motion cue per picture (no arc plus
  arrow for the same move); no leftward arrow unless the message is "go back" (crossing is a two-headed arrow). A
  stopwatch shows big white bold digits with a thick dark outline (the glyph about two thirds of the dial) and a sweep
  as big as its seconds on a ten-second dial.
* One of each, everywhere (third blind test): one runner size (20 x 42 on the 100 grid; only Glow Memory's runner on
  a tile is drawn small); one ghost for "where it was / where it goes" (the same shape as a faded lilac outline: the
  cannon's other swing, Rolling Blobs' step aside, the ride's stop, the cannon's launch point, Moon Jump's normal
  hop); one crack (a thick near-black zigzag with a thin white edge, on lilac, green, red and pink tiles alike);
  motion streaks only on the trailing side, uneven in length (above a falling tile, drop or crusher; never below or
  as two equal upright bars, which read as a pause sign); one cannon (side view: a wooden wheel with spokes over a
  tapered dark barrel with a muzzle ring) on every cannon step, and the cannon's flight is the runner's white jump
  arc (green only for the target ring); "look" is always the eye. A geyser is a pale water jet with an up arrow
  lifting the runner, a dead vent an hourglass (wait). Terraced roads are a side view of three stepped ledges, this
  road's solid lilac with the runner on it, the others dashed outlines at their heights.
* Safe margin: every picture draws inside `ObbySigns.SIZE.margin` (5%) of its slot and keeps within 3..97 of its
  grid, so nothing comes nearer than about 8% to the slot's edge.
* Same idea, same drawing: the crumbling floor (Melting Floor: tiles, Collapsing Bridge: planks, Glow Memory's hot
  feet: green tiles) is one layout, the floor's shape telling them apart; Two Moons' picture is Moon Jump's (a
  see-through dome over the floor, a big floaty jump beside a faded small hop).

* One design for every sign (Merijn: "the boards should be overhanging, so from the most left side to the right
  side ... give it boosters or something so it can fly and look nice and place higher"): a ghost `banner` part
  spanning the lane (`ObbyCourse.SIGN.width`, left lane edge to right lane edge), its bottom `SIGN.lift` (12) studs
  over the floor at its spot, held up by a cartoon booster under each end (adornments plus a built-in fire-particle
  flame blowing down, `ObbySigns.boosters`), hovering `SIGN.bob` up and down over `SIGN.bobPeriod` s (a `slide`
  motion on the y axis, played by ObbyFx on the shared clock: no loop of its own). No posts.
* One picture = one square slot, its size set by the board (`ObbyCourse.slotSize`): a board of up to three pictures
  draws them `SIGN.slot` (7.2) studs big, so the banner is 8 studs tall; where that banner finds no clear spot it falls
  back to `SIGN.small` (5.4). A board of four (the cannon's steps) draws them `SIGN.four` (5) big, `SIGN.step` (1)
  apart, with an arrow in each gap (`ObbySigns.paint`, steps listed in its `THEN`). A sign's slots sit across the
  banner, each over the part of the lane it is about (`pic:<id>@<z>` on the banner; Two Roads: the shield over the
  left road, the speed pad over the right; floors low / middle / high left to right), kept `SIGN.pad` apart (the
  step gap on a board of four) and on the banner. Entry signs space their slots evenly round the middle.
* Pictograms live in `src/visuals/shared/ObbySigns.luau` (ids `ObbySigns.IDS`): Frames, UICorner, UIStroke, rotated
  Frames and digit TextLabels on a SurfaceGui on the banner's face towards the runner, no uploads. How they are drawn
  in `ObbySigns.SIZE` (50 px/stud, MaxDistance 200, main shapes >= 1.3 studs; the booster sizes); the banner's
  geometry in `ObbyCourse.SIGN`; `ObbySigns.paint(gui, slots, deps, height)` takes the banner's height.
* Entry signs: `ObbySections.ENTRY_SIGNS` names the pictures for every idea (Merijn, 2026-11-02: every section
  shows its board; the ten the proposal had skipped got crusher, melt, ride, bounce, ice, spin, fork, rising,
  collapse and panels). A section can name its own with `Section.sign` (`Kit.signed`): Glow Memory's modes, and the
  idea's picture plus one per mechanic a variant borrows from another idea (a spring pad in Key Run: `key,bounce`;
  keys, boosts, the dark, melting floors, wind columns likewise). The banner hangs over the section's first step;
  when nothing in the section leaves it room (a shaft walled up both sides), over the connector before it (x down to
  `SIGN.reach - LINK_LENGTH`).
* Spot signs: a `pic:<id>` marker on a part asks for a banner over that spot (Two Roads' roads, Key Run's stopwatch
  gate, Rising Goo's countdown arch, Moon Jump's two moons); the marker draws nothing on the part (`ObbyCourse.build`
  drops it). Marked parts whose near ends lie within `SIGN.group` studs share one banner (a fork's roads); its floor
  is the highest of their tops.
* `ObbyCourse.signs(section, idea)` places them all: from the spot it tries banner positions along the course
  (`SIGN.tries`) inside the section and takes the first where the banner, its boosters (`SIGN.hang`, `SIGN.reach`)
  and its hover are clear of every part over that part's whole motion (`ObbyCourse.bannerBox`; zones and floods
  excepted: they cover the section by design) and of the other banners. Banner ids `p<section>-<n>`. Each sign is
  `ObbyCourse.SIGN_PARTS` (1) part toward the section's budget: the boosters and pictures are adornments, particles
  and a SurfaceGui on it.
* `ObbyCheck.fields` refuses a `pic:` id ObbySigns doesn't know and any `sign:<text>` marker; `ObbyCheck.signs`
  fails a section whose sign finds no clear spot.

## 9. Checks every variant must pass (tests/ObbyCheck + ObbySections.spec)

* Builds for seeds 1..20 without error; same seed = same parts.
* <= 80 parts including markers. Length 30..110 studs. Lane: every part within z [-12, 12].
* Floors you run on are >= 8 studs across the course direction you cross them (`Kit.FLOOR_MIN`); beams >= 3. The
  check: every `step` part has min(size.x, size.z) >= 3 and steps that are not beams (`look ~= "beam"`) >= 8 wide
  across the walking direction.
* Makeable path per route: every step reachable from the one before by walk/jump (gap <= GAP_MAX, rise <=
  RISE_MAX), launch (`launchReach`), lift, climb, vine release, cannon arc or boost jump, measured
  at the worst point of any motion (moving parts: closest-gap over 32 samples of a period).
* **Timed floors give a person time (Merijn, 2026-11-03, after Moon Pulse's second island went out before the
  first).** `ObbyCheck.timing` runs every section with a step that comes and goes (`flip` without `solid`, `drop`,
  `melt` started by landing) through time: from the first step at 0 it tries every take-off (0.05 s ticks, waiting
  on a floor that stays as long as the longest period + 3 s) onto any reachable step up to 6 ahead, with the real
  air time of the move, and passes when some run reaches the last step of every route on which each such floor is
  there from **the moment you take off towards it** (you see what you jump at and it doesn't go out under your float:
  `TIME_SEEN`; at least 0.25 s before you land) **until 0.25 s after you take off from it** (`TIME_SLACK`; a melting
  tile, which starts when you land, until 0.2 s after: `MELT_SLACK`, MeltingFloor's hard slack). A blinking boost
  strip lying on a walkway is no vanishing floor; you take off within its `carry` of 0.25 s on it lit. Air times: a jump goes up at
  `Kit.JUMP_SPEED` under the gravity of the bubble you take off in (0.54 s on the flat, 1.55 s in a 35 % moon
  bubble); walking on (gap <= 1.5, step <= 2) takes no air time; a walk-off drop its fall; a pad launches on
  landing with its power and throw; a cannon its arc; a ladder its height at 11.1 studs/s. Time on a floor: 0.1 s
  re-jump plus the walk across it that the jumps in and out don't carry (each carries 0.9 of its reach). Geometry is
  `makeable`'s; moving floors are taken where they are at the take-off; hazards are fairness's. A variant whose
  floors line up only for a blind or split-second jump fails here even when `makeable` passes it, and is re-timed,
  not dropped. `ObbyCheck.timingPlan` returns the run it found (the legs a Studio bot can replay).
* No straight-forward walk crosses the section (the existing check, routes included).
* Hazard fairness: a runner at 16 studs/s who loses 0.15 s per jump must find every hazard open for at least
  `WINDOW[tier]` seconds (easy 1.4, medium 1.0, hard 0.75) in some cycle; flood/collapse leave at least 1 s spare.
* Only motion kinds and fields from this file. Every `start` group has a `trigger`; every `gate` has enough keys
  reachable on its route.
* Fall height never resets a runner above a platform they could land on (existing check).
* **Walk-forward test (Merijn, 2026-10-31): just walking forward, no jumping, must never clear a section.** Two
  layers: the walk checks below run for every variant, every route and seeds 1..20; and a Studio walk bot
  (verification step) holds forward from each section's first step in a real playtest and fails any section it
  reaches the end of. A variant that fails is tightened, not dropped.
* **No mashing either: jumping on every landing must not be a strategy.** Sections must not be too easy: a bot that
  holds forward and jumps every time it lands may clear a section by luck, never as a plan.
* The walk model (tests/ObbyCheck, matched to a Studio walk bot: default character, WalkSpeed 16, JumpPower 50):
  * It stands while its floor sensor (1 stud ahead of or behind its middle, 0.5 to the side) is over a floor, and
    walks or stumbles onto anything up to its hip height (2 studs) above its feet. Walking off a ledge is a real
    fall (gravity 196.2, still 16 studs/s forward), so it lands on a lower floor across a hole when the drop allows
    it. A hole between floors at the same height must be at least 4.4 studs long to stop it; a 4-stud hole is
    walked over.
  * Past the section's end there is always a lane-wide floor at `rise` (the connector or the finish): landing on
    it from any height clears the section.
  * Slide parts run the ObbyMoves slide controller (speed kept, `pull` downhill, holding forward adds 16 studs/s²,
    capped at `cap`; the speed carries off the end in the air). Belts, rides, boosts, pads (with `throw`), lifts and
    gusts carry it; leaving a floor keeps the floor's own speed.
  * A wall stops its forward speed, not the walker: it keeps pressing on until it has made no headway for the
    longest period + 2 s (at once when wall and floor never change). Hazards (a 1 x 2 x 5 box, a ball by its real
    sphere) reset it; melting tiles go `delay` s after it lands or leaves (ObbyFx defaults 0.7 / 2.5; a trapdoor is no floor at all), spread to
    `next`, come back; drops go at `at`.
  * Every line across the lane (1 stud apart) and 48 start times over the longest period (on a 1/30 s tick grid).
* `ObbyCheck.straightWalk`: the walker without jumping must fail for every line and every start time.
* `ObbyCheck.masher`: the same walker jumping (JumpPower 50: 6.4 studs up, so ledges up to about 8.3 with the hip
  catch; a 9-stud wall stops it) every time it is on a floor. On its best line it may clear the section from at most 20 % of the start times
  (`ObbyCheck.MASHER_SHARE`); the failure names the variant, the line and the share.

## 10b. How data reaches the client (fixed, so the pieces can be built in parallel)

* `ObbyCourse.build` gives every part a unique `id` string `"<section>.<index>"` (start/finish/links: `"s"`, `"f"`,
  `"l<n>"`) and rewrites section-local references (`motion.next` indices) to those ids.
* ObbyParts sets on the Course model `ObbyFrame` (CFrame: origin, X forward, Y up, Z right, i.e. the course frame).
* Every part gets `ObbyId` (its id). A part with any behaviour (motion, hazard, boost, slide, vine, cannon,
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
* **Forgiveness (2026-11-01, Merijn: "make people have less accidents by mistake")**: spinners turn 1.3-1.5x slower
  (Merry-Go-Round, Ice Slide and Updraft sweepers), crushers rest 13 studs up (a jumping head clears them), and hazards
  reset only 0.4 studs inside their drawn edge (`ObbyFx.HAZARD_GRACE`). Windows may now run up to 2.5 / 1.8 / 1.4 s
  (easy / medium / hard); the masher and walk-forward checks still decide what is too easy.
Where a draft variant is too easy for its tier after this shift, tighten its numbers (shorter windows, longer
gaps up to the limits, more hazards, faster motions); don't drop it.

Vine Swing's windows are per swing, not per cycle: you hang as long as you like, so a window is the time in one
full (pumped) swing in which a let go lands on the next step (tests/obby/VineSwing.spec): easy 0.3-0.8 s, medium
0.2-0.45 s, hard 0.15-0.3 s. The spec's player bot (pumps, lets go when the flight lands) must clear every variant
from 90 % of start times, and a masher bot (holds forward, jumps on every landing, lets go once it can) from at most
20 %.

## 11. Settled while building the kit (these win over earlier wording)

* Rotation: `CFrame.fromEulerAnglesYXZ(rad(pitch), rad(yaw), rad(roll))` in the course frame. A positive `roll`
  lifts the part's forward (+x) end: that is how a ramp climbs (`Kit.ramp` sets it). `pitch` banks sideways.
* `Pick = { id, tier, variant, seed }`; `variant = 0` is the idea's generator. Part ids: `s` start, `h` home catch
  pad, `f` finish, `l<n>` connectors, `p<section>-<n>` sign banners (§8b), `<section>.<index>` section parts;
  `motion.next` holds those ids.
* Motion timing has ONE source of truth: `Kit.offsetAt / pathAt / patternAt / sweepAt / punchAt / conveyorAt`. The
  checks sample them and ObbyFx plays them, so what a player sees is what the checks measured.
* Markers are anchored direct children of their host part (ObbyFx moves and fades them with it); `ghostStop` stays
  in the Course model with `ObbyHost`. `ObbyCheck.MARKER_PARTS` mirrors `ObbyParts.MARKER_PARTS` (keep in sync).
  Gate locks are `Lock1..LockN` (need <= 9).
* Walk-forward check: see the walk model in §9. Every walking line needs a same-height hole of at least 4.4 studs, a
  wall the walker can't climb (over 2 studs; 8.4 or more against the masher), or a hazard it can't slip past at any
  start time. Pads, lifts, belts, boosts, slides and moving floors carry the walker.
* Width check exempts ladders, wind columns, vines and cannons; bounce pads still need 8.
* Sounds: only the built-in `rbxasset://sounds/` files (volume_slider, action_jump, action_jump_land,
  action_footsteps_plastic, impact_water) at different pitches, through `ObbyFx.sound(name)`.
* Dark zones tint with their own ColorCorrection ("ObbyMovesDark"), never writing Lighting.
