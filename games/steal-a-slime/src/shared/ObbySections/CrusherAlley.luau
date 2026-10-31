--!strict
--[[
	Crusher Alley (obby idea 1, docs/obby-variants/1.json; contract/obby-sections.md)

	Red see-through crushers slam down on a beat over the walking path: read the beat, wait in a safe pocket, go when
	it lifts. Touching a crusher sends you back to the start pad (it is a `hazard`). Later variants add wall punchers
	(a `punch` / one-beat `pattern` on z), swinging blobs (`swing`, with a rope to the pivot), a `pattern` crusher that
	fakes a lift, trip plates (`trigger` + `start`) and rising goo (`rise`) that punishes waiting.

	This is the reference idea module: copy its shape for a new idea. Each variant is a `build(seed)` returning
	Kit.section(length, rise, parts); hand-made variants ignore the seed. Variants are appended, never reordered (a
	pick stores the index).

	Crusher timing: a crusher is a `punch` on y, its bottom CRUSHER_LIFT above the floor at rest, slamming down to the
	floor. Kit.punchAt keeps it below head height for about 45 % of its period, so the window a runner gets is about
	0.55 x period minus the time it takes to walk under it (tests/ObbyCheck measures it exactly). Tuned per §10:
	easy windows 1.4..1.7 s, medium 1.0..1.15 s, hard 0.75..0.9 s (tests/obby/CrusherAlley.spec bounds
	them).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local CRUSHER_LIFT = 11 -- studs from the floor to a crusher's bottom at rest: well over a head (5) plus a jump
local CRUSHER_THICK = 4 -- crusher block height
local CRUSHER_LONG = 8 -- along the course: about half a second to walk under
local ENTRY_LONG = 10 -- the entry pad before the jump in
local ENTRY_GAP = 5 -- every variant opens with a jump: a 5-stud hole stops a walker (a 4-stud one is walked over, ObbyCheck.walkStop)

local PUNCHER_TALL = 4 -- a wall puncher's height, its bottom half a stud over the floor
local ROPE = 0.6 -- a pendulum rope's thickness

-- A crusher `long` (default CRUSHER_LONG) x `wide` centred on (x, z) over a floor whose top is `top`, slamming every
-- `period` s.
local function crusher(
	x: number,
	z: number,
	wide: number,
	top: number,
	period: number,
	phase: number,
	long: number?
): Kit.Part
	local bottom = top + CRUSHER_LIFT
	return Kit.hazard({ long or CRUSHER_LONG, CRUSHER_THICK, wide }, { x, bottom + CRUSHER_THICK / 2, z }, {
		motion = { kind = "punch", axis = "y", amp = -CRUSHER_LIFT, period = period, phase = phase },
	})
end

-- A crusher running a beat list (`pattern`): "slam" comes all the way down, "half" (amount) stops part way.
local function patternCrusher(x: number, top: number, period: number, phase: number, beats: { Kit.Beat }): Kit.Part
	local bottom = top + CRUSHER_LIFT
	return Kit.hazard({ CRUSHER_LONG, CRUSHER_THICK, Kit.WIDTH }, { x, bottom + CRUSHER_THICK / 2, 0 }, {
		motion = {
			kind = "pattern",
			axis = "y",
			amp = -CRUSHER_LIFT,
			period = period,
			phase = phase,
			beats = beats,
		},
	})
end

export type PunchOpts = {
	thick: number, -- across the lane at rest (z), against its wall
	reach: number, -- how far it shoots across
	long: number, -- along the course (x)
	snap: boolean?, -- true: a one-beat `pattern` (out, short hold, straight back) instead of a held `punch`
	tall: number?, -- its height (default PUNCHER_TALL); a tall one can't be jumped over
}

-- A wall puncher at `x` on the `side` wall (-1 left, +1 right) of a floor whose top is `top`, shooting across.
local function puncher(x: number, side: number, top: number, period: number, phase: number, o: PunchOpts): Kit.Part
	local motion: Kit.Motion = if o.snap
		then {
			kind = "pattern",
			axis = "z",
			amp = -side * o.reach,
			period = period,
			phase = phase,
			beats = { { at = 0, kind = "slam" } },
		}
		else { kind = "punch", axis = "z", amp = -side * o.reach, period = period, phase = phase }
	local tall = o.tall or PUNCHER_TALL
	return Kit.hazard(
		{ o.long, tall, o.thick },
		{ x, top + 0.5 + tall / 2, side * (Kit.HALF - o.thick / 2) },
		{ motion = motion }
	)
end

export type SwingOpts = {
	size: Kit.Vec, -- the blob
	ball: boolean?, -- a round blob (size should be even)
	bottom: number, -- its bottom at the low point of the swing
	arm: number, -- pivot height over the blob's centre
	amp: number, -- degrees each way
	period: number,
	phase: number?,
}

-- A swinging blob hanging from a pivot over (x, z), plus its rope (ghost decor that swings with it).
local function pendulum(parts: { Kit.Part }, x: number, z: number, o: SwingOpts)
	local cy = o.bottom + o.size[2] / 2
	local pivot = cy + o.arm
	local ropeLow = cy + o.size[2] / 2
	local ropeY = (pivot + ropeLow) / 2
	table.insert(
		parts,
		Kit.hazard(o.size, { x, cy, z }, {
			shape = if o.ball then "ball" else nil,
			motion = { kind = "swing", amp = o.amp, period = o.period, phase = o.phase or 0, arm = o.arm },
		})
	)
	table.insert(
		parts,
		Kit.prop({ ROPE, pivot - ropeLow, ROPE }, { x, ropeY, z }, "rope", {
			ghost = true,
			motion = { kind = "swing", amp = o.amp, period = o.period, phase = o.phase or 0, arm = pivot - ropeY },
		})
	)
end

-- The entry pad and the jump onto the alley floor that starts at x = ENTRY_LONG + ENTRY_GAP.
local function entry(parts: { Kit.Part }, extra: { [string]: any }?)
	local pad = Kit.slab(ENTRY_LONG / 2, 0, 0, ENTRY_LONG, Kit.WIDTH, "jelly", { tone = 1 })
	for k, v in (extra or {}) :: { [string]: any } do
		(pad :: any)[k] = v
	end
	table.insert(parts, pad)
end

local FLOOR_FROM = ENTRY_LONG + ENTRY_GAP

-- A floor slab from x0 to x1 (top `top`), centred on z, `wide` across (default the whole lane).
local function floor(
	parts: { Kit.Part },
	x0: number,
	x1: number,
	top: number,
	look: string,
	tone: number,
	wide: number?,
	z: number?
)
	table.insert(parts, Kit.slab((x0 + x1) / 2, top, z or 0, x1 - x0, wide or Kit.WIDTH, look, { tone = tone }))
end

-- Rising goo under a stretch of floor (x0..x1, floor top `top`): after `delay` s on clock `group` it climbs at
-- `speed` studs / s through the floor and up to `stop` studs over where it started.
local function flood(
	x0: number,
	x1: number,
	top: number,
	group: string,
	delay: number,
	speed: number,
	stop: number
): Kit.Part
	return Kit.hazard({ x1 - x0, 0.4, Kit.WIDTH }, { (x0 + x1) / 2, top - 0.5, 0 }, {
		start = group,
		motion = { kind = "rise", speed = speed, delay = delay, stop = stop },
	})
end

local M = {}
M.id = "CrusherAlley"
M.name = "Crusher Alley"
M.idea = 1

M.variants = {
	{
		-- One big crusher over a wide floor: learn the shadow and the wobble. A pocket to land in, then the slam,
		-- then a hop up onto the exit ledge.
		name = "First Slam",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 44, 1.5
			local parts = {}
			entry(parts)
			local floorTo = 37 -- the alley floor, then a 2-stud gap up onto the exit ledge
			table.insert(
				parts,
				Kit.slab((FLOOR_FROM + floorTo) / 2, 0, 0, floorTo - FLOOR_FROM, Kit.WIDTH, "goo", { tone = 2 })
			)
			table.insert(parts, crusher(27, 0, Kit.WIDTH, 0, 3.7, 0))
			local ledge = length - (floorTo + 2)
			table.insert(parts, Kit.slab(length - ledge / 2, rise, 0, ledge, Kit.WIDTH, "jelly", { tone = 3 }))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Three crushers going up and down together on a slow beat: wait once, then walk all three in one go.
		name = "Slow Trio",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 50
			local parts = {}
			entry(parts)
			table.insert(
				parts,
				Kit.slab((FLOOR_FROM + length) / 2, 0, 0, length - FLOOR_FROM, Kit.WIDTH, "goo", { tone = 1 })
			)
			-- 3-stud seams: too thin to wait in, so you go on one lift and walk all three without a stop.
			local long, pocket = 6, 3
			local first = FLOOR_FROM + 3 + long / 2 -- a 3-stud landing before the first one
			for i = 0, 2 do
				table.insert(parts, crusher(first + i * (long + pocket), 0, Kit.WIDTH, 0, 5.5, 0, long))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three walled lanes side by side, one crusher each on its own beat: look along the row and take the lane
		-- that is open now (the walls stop you switching halfway).
		name = "Pick a Lane",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 44
			local parts = {}
			entry(parts)
			table.insert(
				parts,
				Kit.slab((FLOOR_FROM + length) / 2, 0, 0, length - FLOOR_FROM, Kit.WIDTH, "goo", { tone = 3 })
			)
			local wallFrom, wallTo = 16, 38
			local split = 4.5 -- the lane walls' centres: an 8-wide middle lane, 7-wide outer lanes
			for _, z in { -split, split } do
				table.insert(parts, Kit.wall((wallFrom + wallTo) / 2, z, wallTo - wallFrom, nil, true, { tone = 2 }))
			end
			local outer = Kit.HALF - split - 0.5
			local x = 27
			-- Faster than the draft (3 / 3.4 / 3.8 s): one lane alone gives 0.7..1.2 s, picking the open lane about 2 s.
			table.insert(parts, crusher(x, -(split + 0.5 + outer / 2), outer, 0, 2.2, 0))
			table.insert(parts, crusher(x, 0, 2 * split - 1, 0, 2.5, 0.3))
			table.insert(parts, crusher(x, split + 0.5 + outer / 2, outer, 0, 2.8, 0.6))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Four half-lane crushers nearly back to back, left, right, left, right, each a quarter beat before the one
		-- behind it: the open half swaps sides as you go, so weave across instead of waiting.
		name = "Half Lane",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 60
			local parts = {}
			entry(parts)
			floor(parts, FLOOR_FROM, length, 0, "goo", 2)
			local long, half, pocket = 10, Kit.WIDTH / 2, 1 -- 1-stud seams: too thin to wait in
			for i = 0, 3 do
				local side = if i % 2 == 0 then -1 else 1
				local x = 16 + long / 2 + i * (long + pocket)
				table.insert(parts, crusher(x, side * half / 2, half, 0, 2.6, (i * 0.75) % 1, long))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- One big blob swings slowly across a narrow bridge: cross under its pivot while it is out at the far side. A
		-- tall wall stands in front of the bridge, so you step round it and back onto the bridge's line.
		name = "Big Swing",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 46
			local parts = {}
			entry(parts)
			local bridgeFrom, bridgeTo = 24, 36
			floor(parts, FLOOR_FROM, bridgeFrom, 0, "goo", 1)
			-- 12 wide over the bridge's 8: every straight line either hits it or misses the bridge.
			table.insert(parts, Kit.wall(17, 0, 12, nil, false, { tone = 2 }))
			floor(parts, bridgeFrom, bridgeTo, 0, "beam", 1, Kit.FLOOR_MIN)
			floor(parts, bridgeTo, length, 0, "jelly", 2)
			pendulum(parts, 30, 0, {
				size = { 6, 6, 6 },
				ball = true,
				bottom = 0.5,
				arm = 14,
				amp = 40,
				period = 3.8,
			})
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three punchers flash out of alternate walls and snap straight back: the danger is the quick shot, so walk
		-- past right after the snap. Each fires a little earlier than the one before (8 % of a beat), so a runner who
		-- never stops meets one of them; they stand 7 tall, too tall to hop over.
		name = "Wall Knock",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 52
			local parts = {}
			entry(parts)
			floor(parts, FLOOR_FROM, length, 0, "goo", 3)
			local o = { thick = 8, reach = Kit.WIDTH - 8, long = 6, snap = true, tall = 7 }
			for i = 0, 2 do
				local side = if i % 2 == 0 then -1 else 1
				table.insert(parts, puncher(22 + i * 10, side, 0, 2.3, (i * 0.92) % 1, o))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Four crushers each on their own beat over low slots, with raised safe pockets between them: hop up into a
		-- pocket, read the next beat, drop in when it lifts.
		name = "Off-Beat",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, high = 80, 1.5
			local parts = {}
			entry(parts)
			local periods = { 2.8, 3.1, 2.9, 3.0 }
			local slot, pocket = 6, 8
			local x = FLOOR_FROM + 6 -- the landing, then the first slot
			floor(parts, FLOOR_FROM, x + slot, 0, "goo", 1)
			for i, period in periods do
				table.insert(parts, crusher(x + slot / 2, 0, Kit.WIDTH, 0, period, 0.2 * i, slot))
				if i > 1 then
					floor(parts, x, x + slot, 0, "goo", 1)
				end
				x += slot
				local to = if i == #periods then length else x + pocket
				floor(parts, x, to, high, "jelly", 1 + i % 3)
				x = to
			end
			return Kit.section(length, high, parts)
		end,
	},
	{
		-- Three crushers on 2 : 3 : 4 beats with seams too thin to wait in: watch for the moment all three are up
		-- together (three times a 16.2 s cycle, every 4.5 to 6.5 s) and run the whole row.
		name = "Rare Line-Up",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 48
			local parts = {}
			entry(parts)
			floor(parts, FLOOR_FROM, length, 0, "goo", 2)
			-- 2.7 / 4.05 / 5.4 s; these phases (a search) leave about 1.05 s for the whole row.
			local long, pocket, beat = 5, 3, 2.7
			for i, phase in { 0, 0.8, 0.3 } do
				local x = FLOOR_FROM + 3 + long / 2 + (i - 1) * (long + pocket)
				table.insert(parts, crusher(x, 0, Kit.WIDTH, 0, beat * (i + 1) / 2, phase, long))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Each landing island has a crusher over it: jump the gap only once it has lifted.
		name = "Slam and Jump",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 66
			local parts = {}
			entry(parts)
			local island, gap = 10, 6
			local x = FLOOR_FROM
			for i = 0, 2 do
				floor(parts, x, x + island, 0, "jelly", 1 + i)
				table.insert(parts, crusher(x + island / 2, 0, Kit.WIDTH, 0, 3.5, i * 0.33))
				x += island + gap
			end
			floor(parts, x - gap + ENTRY_GAP, length, 0, "goo", 1)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Punchers from both walls, close together and each on its own offset: zigzag through as each pulls back.
		-- They stand 7 tall (no hopping over), and the offsets keep any one straight line from staying open.
		name = "Cross-Punch",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 54
			local parts = {}
			entry(parts)
			floor(parts, FLOOR_FROM, length, 0, "goo", 3)
			-- 3-stud seams between them: too thin to wait in, so the four are one run. These phases (a search) leave
			-- about 1.05 s for a runner who steers, and almost none for one who holds a line (jumping or not).
			local o = { thick = 10, reach = 14, long = 6, tall = 7 }
			for i, phase in { 0, 0.9, 0.3, 0.4 } do
				local side = if i % 2 == 1 then -1 else 1
				table.insert(parts, puncher(20 + (i - 1) * 9, side, 0, 3.6, phase, o))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A low blob swings across the lane at shin height (jump it or dodge it), then a crusher half a beat later.
		name = "Low Sweep",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 54
			local parts = {}
			entry(parts)
			local bridgeFrom, bridgeTo = 20, 28
			floor(parts, FLOOR_FROM, bridgeFrom, 0, "goo", 1)
			floor(parts, bridgeFrom, bridgeTo, 0, "beam", 1, Kit.FLOOR_MIN)
			floor(parts, bridgeTo, length, 0, "goo", 1)
			local period = 2.8
			pendulum(parts, 24, 0, { size = { 4, 3, 6 }, bottom = 0.2, arm = 14, amp = 40, period = period })
			table.insert(parts, crusher(40, 0, Kit.WIDTH, 0, period, 0.5, 6))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The alley climbs: a crusher over each wide step, so you time each step up as well as the slam.
		name = "Crusher Stairs",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, up, long = 60, 2, 12
			local parts = {}
			entry(parts)
			for i = 1, 3 do
				local x0 = FLOOR_FROM + (i - 1) * long
				floor(parts, x0, x0 + long, i * up, "jelly", i)
				table.insert(parts, crusher(x0 + long / 2, 0, Kit.WIDTH, i * up, 3.0, (i - 1) * 0.3))
			end
			floor(parts, FLOOR_FROM + 3 * long, length, 3 * up, "goo", 2)
			return Kit.section(length, 3 * up, parts)
		end,
	},
	{
		-- The crushers play slam, half drop, slam: a half drop still reaches your head, so count the pattern instead
		-- of going on the first lift.
		name = "Fake Out",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 58
			local parts = {}
			entry(parts)
			floor(parts, FLOOR_FROM, length, 0, "goo", 2)
			local beats: { Kit.Beat } = {
				{ at = 0, kind = "slam" },
				{ at = 0.9, kind = "half", amount = 0.65 },
				{ at = 1.8, kind = "slam" },
			}
			for i = 0, 2 do
				table.insert(parts, patternCrusher(FLOOR_FROM + 7 + i * 14, 0, 4.0, i * 0.1, beats))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Red goo floods the entry pad a few seconds after you step on it: go on the first good beat, don't wait.
		name = "Don't Dawdle",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 60
			local parts = {}
			entry(parts, { trigger = "dawdle" })
			table.insert(parts, flood(0, ENTRY_LONG, 0, "dawdle", 5, 1.5, 3))
			floor(parts, FLOOR_FROM, length, 0, "goo", 3)
			for i = 0, 2 do
				table.insert(parts, crusher(FLOOR_FROM + 7 + i * 14, 0, Kit.WIDTH, 0, 3.0, i * 0.3))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Each crusher sleeps until you step on the plate under it, then slams 0.7 s later: keep walking and jump
		-- straight on, never stop on a plate.
		name = "Trip Plate",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 96
			local parts = {}
			entry(parts)
			-- Five plates with 5-stud jumps between them; each crusher is a stud short of its plate at both ends, so
			-- the jump off the far edge is never under it. 0.7 s is the tightest the fairness runner passes (0.65 fails).
			local plate, gap, period, delay = 8, 5, 2.7, 0.7
			local x = FLOOR_FROM + 4
			floor(parts, FLOOR_FROM, x, 0, "goo", 1)
			for i = 1, 5 do
				x += gap
				local g = `plate{i}`
				table.insert(parts, Kit.slab(x + plate / 2, 0, 0, plate, Kit.WIDTH, "glow", { tone = 1, trigger = g }))
				local c = crusher(x + plate / 2, 0, Kit.WIDTH, 0, period, 1 - delay / period, plate - 2)
				c.start = g
				table.insert(parts, c)
				x += plate
			end
			floor(parts, x + gap, length, 0, "goo", 1)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- All three kinds in one run: a slam, a wall punch, a blob swinging over a bridge and a last slam, each on its
		-- own beat.
		name = "Gauntlet",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 72
			local parts = {}
			entry(parts)
			local bridgeFrom, bridgeTo = 40, 50
			floor(parts, FLOOR_FROM, bridgeFrom, 0, "goo", 1)
			floor(parts, bridgeFrom, bridgeTo, 0, "beam", 2, Kit.FLOOR_MIN)
			floor(parts, bridgeTo, length, 0, "goo", 2)
			table.insert(parts, crusher(20, 0, Kit.WIDTH, 0, 2.4, 0, 5))
			table.insert(parts, puncher(26, -1, 0, 2.4, 0.3, { thick = 10, reach = 14, long = 4 })) -- right behind the slam
			pendulum(parts, 45, 0, { size = { 6, 6, 6 }, ball = true, bottom = 0.5, arm = 14, amp = 40, period = 2.6 })
			table.insert(parts, crusher(60, 0, Kit.WIDTH, 0, 2.1, 0.5, 4))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A crusher and two wall punchers hit the same narrow square on different beats: go only when all three are
		-- back. Two stations.
		name = "Double Trouble",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 64
			local parts = {}
			entry(parts)
			local square, long = 12, 8
			-- The punchers sit over the holes beside the square and reach 3 studs past its middle.
			local o = { thick = (Kit.WIDTH - square) / 2, reach = 9, long = 6 }
			-- Crusher 2.6 s, punchers 2 s: these phases leave about 0.8 s in the first cycles (a phase search).
			local phases = { { 0.1, 0.35 }, { 0.35, 0.1 } }
			local x = FLOOR_FROM
			for i = 1, 2 do
				floor(parts, x, x + 10, 0, "goo", 1)
				x += 10
				floor(parts, x, x + long, 0, "beam", 2, square)
				table.insert(parts, crusher(x + long / 2, 0, square, 0, 2.6, 0, long))
				table.insert(parts, puncher(x + long / 2, -1, 0, 2, phases[i][1], o))
				table.insert(parts, puncher(x + long / 2, 1, 0, 2, phases[i][2], o))
				x += long
			end
			floor(parts, x, length, 0, "goo", 1)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Five fast crushers with thin pockets, each slamming a step later than the one before: the gaps travel down
		-- the alley at walking speed, so walk with the wave without stopping.
		name = "Head-On Wave",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 66
			local parts = {}
			entry(parts)
			floor(parts, FLOOR_FROM, length, 0, "goo", 3)
			local long, pocket, period = 6, 3, 2.3
			local step = (long + pocket) / Kit.WALK / period -- a walker reaches the next crusher one step later
			for i = 0, 4 do
				local x = FLOOR_FROM + 3 + long / 2 + i * (long + pocket)
				table.insert(parts, crusher(x, 0, Kit.WIDTH, 0, period, (-i * step) % 1, long))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Five crushers that get faster down the hall, and the hall floor floods with red goo if you take too long.
		name = "Hurry Up Hall",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, hallTo = 90, 84
			local parts = {}
			entry(parts, { trigger = "hurry" })
			floor(parts, FLOOR_FROM, hallTo, 0, "goo", 1)
			table.insert(parts, flood(FLOOR_FROM, hallTo, 0, "hurry", 12, 0.5, 3))
			local long, pocket = 4, 8
			for i, period in { 2.3, 2.2, 2.15, 2.1, 2.05 } do
				local x = FLOOR_FROM + 4 + long / 2 + (i - 1) * (long + pocket)
				table.insert(parts, crusher(x, 0, Kit.WIDTH, 0, period, 0.2 * i, long))
			end
			floor(parts, hallTo, length, 1, "jelly", 2)
			return Kit.section(length, 1, parts)
		end,
	},
}

return M
