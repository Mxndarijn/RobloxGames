--!strict
--[[
	Aim the Cannon (obby idea 26, docs/obby-variants/26.json; contract/obby-sections.md)

	A fat goo cannon sweeps its barrel left and right (`sweep` on a `cannon` part). Walk into the barrel, watch the
	dotted aim line (ObbyMoves draws it from the real arc), jump to fire: the shot follows a fixed arc for the aim at
	that moment. A miss ends in the void or in red goo (back to the start pad). Every safe island wears a gold `star`
	as its target. Later variants add a goo moat and a goo pool that show a miss, a goo wall with a hole (fixed or
	sliding), islands that drift, an island that breathes on the beat, a seat that floods with goo 3 s after you climb
	in, and chains of three and four cannons (in Four Fast Shots every seat is hot: no barrel to rest in).

	The arc: a cannon of `power` studs / s, `arc` degrees up, fires from the barrel's centre; the check (tests/
	ObbyCheck) lands it where it comes down to the target's top. The power is solved here for the distance from the
	barrel to the target's landing spot, so the landing circle of a cannon runs through its target: the aim (the
	sweep) is the only thing that decides a hit. Ranges never reach a later step (no overshooting a stage).

	Fire windows (the seconds per pass the landing spot sits inside a target, 1 stud in from its edges, clear of a
	barrel standing on it, and with the arc clear of every goo box, measured on the island's pose at landing time) are
	tuned per contract §10 and bounded by tests/obby/AimTheCannon.spec (the longest window at least the floor,
	the median pass at most the ceiling): easy 0.55..0.9 s, medium 0.38..0.6 s, hard 0.25..0.4 s (tightened in review).

	Kit gaps (simplified): no pitch motion (Near or Far rides its cannon on a rail instead; Two
	Axes moves its island back and forth instead), no catch cannon (Cannon to Cannon lands on small perches with the
	next barrel on them), no seat drop on a cannon that also sweeps (Hot Seat floods its seat with rising goo).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local BARREL = { 4, 3, 4 } -- the cannon: long (aim axis) x tall x wide
local PAD_LONG = 10 -- the start pad, x 0..10
local PAD_WIDE = 10
local CANNON_X = 7 -- the first barrel's centre on the start pad (its back at 5: you walk into it from behind)
local EXIT_GAP = 4 -- the hop from a moving island onto a fixed exit slab
local EXIT_LONG = 6
local GOO_TOP = -0.3 -- a goo moat or pool sits just under the floors next to it (shows the miss, never a floor)
local GOO_THICK = 0.6

-- Speed (studs / s) that carries a shot `arc` degrees up a horizontal `dist` to land `drop` studs below the barrel's
-- centre (negative: higher), as the check flies it.
local function powerFor(dist: number, drop: number, arc: number): number
	local a = math.rad(arc)
	local c, s = math.cos(a), math.sin(a)
	local function range(p: number): number
		local vy = p * s
		local disc = vy * vy + 2 * Kit.GRAVITY * drop
		if disc < 0 then
			return 0
		end
		return p * c * (vy + math.sqrt(disc)) / Kit.GRAVITY
	end
	local lo, hi = 1, 400
	for _ = 1, 80 do
		local mid = (lo + hi) / 2
		if range(mid) < dist then
			lo = mid
		else
			hi = mid
		end
	end
	return math.floor((lo + hi) / 2 * 1000 + 0.5) / 1000
end

export type Aim = {
	amp: number, -- degrees each way of the sweep
	move: number, -- seconds from one end to the other ("per side")
	hold: number?, -- seconds held at each end
	phase: number?,
	arc: number?, -- degrees up (default 45)
	yaw: number?, -- the sweep's centre (degrees, + turns towards -z / left)
}

-- A sweeping cannon whose barrel centre stands on a floor of top `top` at (x, z), fired at the landing spot
-- `target` = { x, top, z }.
local function cannon(
	x: number,
	top: number,
	z: number,
	target: { number },
	o: Aim,
	extra: { [string]: any }?
): Kit.Part
	local arc = o.arc or 45
	local cy = top + BARREL[2] / 2
	local dist = math.sqrt((target[1] - x) ^ 2 + (target[3] - z) ^ 2)
	local hold = if o.hold and o.hold > 0 then o.hold else nil
	local part = Kit.prop(BARREL, { x, cy, z }, "cannon", {
		step = true,
		yaw = o.yaw,
		cannon = { power = powerFor(dist, cy - target[2], arc), arc = arc },
		motion = {
			kind = "sweep",
			amp = o.amp,
			period = 2 * o.move + 2 * (hold or 0),
			hold = hold,
			phase = o.phase,
		},
	})
	for k, v in (extra or {}) :: { [string]: any } do
		(part :: any)[k] = v
	end
	return part
end

-- The start pad (x 0..PAD_LONG) with its first cannon centred on z `cz`, aimed at `target`.
local function start(parts: { Kit.Part }, cz: number, target: { number }, o: Aim, extra: { [string]: any }?): Kit.Part
	table.insert(parts, Kit.slab(PAD_LONG / 2, 0, cz, PAD_LONG, PAD_WIDE, "jelly", { tone = 1 }))
	local c = cannon(CANNON_X, 0, cz, target, o, extra)
	table.insert(parts, c)
	return c
end

-- A target island (a star floats over it) centred on (x, z), `sx` long and `sz` wide, top `top`.
local function island(x: number, top: number, z: number, sx: number, sz: number, extra: { [string]: any }?): Kit.Part
	local part = Kit.slab(x, top, z, sx, sz, "jelly", { tone = 2, marker = "star" })
	for k, v in (extra or {}) :: { [string]: any } do
		(part :: any)[k] = v
	end
	return part
end

-- A landing deck `long` x `wide` whose landing spot (the part in front of the next barrel) is centred on (lx, z);
-- the next barrel stands on its far end. Returns the deck, the barrel's centre x and the deck's far edge.
local function deck(lx: number, top: number, z: number, land: number, wide: number): (Kit.Part, number, number)
	local x0 = lx - land / 2
	local x1 = x0 + land + BARREL[1]
	return island((x0 + x1) / 2, top, z, x1 - x0, wide), x1 - BARREL[1] / 2, x1
end

-- A full-width exit slab from x0 (EXIT_LONG long, top `top`): the hop off a moving island.
local function exit(parts: { Kit.Part }, x0: number, top: number): number
	table.insert(parts, Kit.slab(x0 + EXIT_LONG / 2, top, 0, EXIT_LONG, Kit.WIDTH, "jelly", { tone = 3 }))
	return x0 + EXIT_LONG
end

-- A flat sheet of goo x0..x1 by z0..z1 just under the floors (a moat or pool that shows your miss).
local function goo(x0: number, x1: number, z0: number, z1: number, top: number?): Kit.Part
	local t = (top or 0) + GOO_TOP
	return Kit.hazard({ x1 - x0, GOO_THICK, z1 - z0 }, { (x0 + x1) / 2, t - GOO_THICK / 2, (z0 + z1) / 2 })
end

-- A goo wall across the lane at x, from y0 to y1, covering z0..z1 (1 stud thick).
local function gooWall(x: number, z0: number, z1: number, y0: number, y1: number, extra: { [string]: any }?): Kit.Part
	return Kit.hazard({ 1, y1 - y0, z1 - z0 }, { x, (y0 + y1) / 2, (z0 + z1) / 2 }, extra)
end

-- Red goo under a hot seat (a barrel at (x, z) on a floor of top `top` that is `trigger = group`): it starts 3.5 under
-- the floor (clear of a seated character's feet, 1.5 under it), waits 1.5 s, then climbs 1 stud / s, so it touches the
-- feet (with ObbyFx's 0.5-stud pad) 3.0 s after you climb in.
local function seatFlood(x: number, top: number, z: number, group: string): Kit.Part
	return Kit.hazard({ 5, 2.5, 5 }, { x, top - 3.5 - 1.25, z }, {
		start = group,
		motion = { kind = "rise", speed = 1, delay = 1.5, stop = 6 },
	})
end

local WALL_LOW, WALL_HIGH = -6, 18 -- a goo wall's bottom and top: every arc crosses it inside that

local M = {}
M.id = "AimTheCannon"
M.name = "Aim the Cannon"
M.idea = 26

M.variants = {
	{
		-- One slow cannon pausing at each end; a big island dead ahead, passed twice a sweep.
		name = "First Shot",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local land = { 37, 0, 0 }
			start(parts, 0, land, { amp = 40, move = 2.6, hold = 0.4 })
			table.insert(parts, island(37, 0, 0, 12, 14))
			return Kit.section(43, 0, parts)
		end,
	},
	{
		-- The island is out to the left where the barrel pauses: wait for the end of the sweep and fire in the pause.
		name = "Pick a Side",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local land = { 35, 0, -6 }
			start(parts, 6, land, { amp = 16, move = 2.8, hold = 0.4 })
			table.insert(parts, island(35, 0, -6, 12, 12))
			return Kit.section(41, 0, parts)
		end,
	},
	{
		-- A steep lob up onto a ledge 12 studs higher: the dotted line climbs.
		name = "Lob Up",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local land = { 31, 12, 0 }
			start(parts, 0, land, { amp = 35, move = 2.6, arc = 60 })
			table.insert(parts, island(31, 12, 0, 12, 10))
			return Kit.section(37, 12, parts)
		end,
	},
	{
		-- Two islands, left and right, both lead on: two chances a sweep.
		name = "Either Way",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local land = { 33, 0, -7 }
			start(parts, 0, land, { amp = 40, move = 3.0, hold = 0.3 })
			table.insert(parts, island(33, 0, -7, 10, 10))
			table.insert(parts, island(33, 0, 7, 10, 10, { route = "right" }))
			table.insert(parts, Kit.slab(46, 0, 0, 8, Kit.WIDTH, "jelly", { tone = 3 }))
			return Kit.section(50, 0, parts)
		end,
	},
	{
		-- A short shot onto an island with a second cannon on it; walk in and take the second slow shot.
		name = "Two Hop",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local land1 = { 27, 0, -5 }
			start(parts, 0, land1, { amp = 35, move = 2.2 })
			local d1, c2x = deck(27, 0, -5, 8, 10)
			table.insert(parts, d1)
			local land2 = { 53, 0, 3 }
			table.insert(parts, cannon(c2x, 0, -5, land2, { amp = 35, move = 2.2, phase = 0.3 }))
			table.insert(parts, island(53, 0, 3, 10, 10))
			return Kit.section(58, 0, parts)
		end,
	},
	{
		-- The island sits in a moat of red goo: a short or wide shot splashes into goo, so you see the miss.
		name = "Goo Moat",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local land = { 37, 0, 0 }
			start(parts, 0, land, { amp = 40, move = 2.7, hold = 0.3 })
			table.insert(parts, island(37, 0, 0, 12, 12))
			table.insert(parts, goo(22, 31, -Kit.HALF, Kit.HALF))
			table.insert(parts, goo(31, 43, -Kit.HALF, -6))
			table.insert(parts, goo(31, 43, 6, Kit.HALF))
			return Kit.section(43, 0, parts)
		end,
	},
	{
		-- No pause at the ends and a faster sweep; the island is off to the right, so you fire mid-swing.
		name = "Quick Swing",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local land = { 33, 0, 5 }
			start(parts, 0, land, { amp = 45, move = 2.0 })
			table.insert(parts, island(33, 0, 5, 10, 10))
			return Kit.section(38, 0, parts)
		end,
	},
	{
		-- The barrel rides a rail forward and back instead of nodding: fire too early (too far back) and you drop
		-- into the red pool in front of the island, too late and you fly past it. You aim for distance.
		name = "Near or Far",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local rest = 18 -- the barrel's centre at the middle of its rail (it rides 9..27)
			local reach = 30
			table.insert(parts, Kit.slab(PAD_LONG / 2, 0, 0, PAD_LONG, PAD_WIDE, "jelly", { tone = 1 }))
			local c = cannon(rest, 0, 0, { rest + reach, 0, 0 }, { amp = 0, move = 1 })
			c.motion = { kind = "slide", axis = "x", amp = 9, period = 3.0, phase = 0.75 }
			c.marker = "ghostStop"
			table.insert(parts, c)
			table.insert(parts, goo(29, 43, -Kit.HALF, Kit.HALF))
			table.insert(parts, island(rest + reach, 0, 0, 10, 12))
			return Kit.section(53, 0, parts)
		end,
	},
	{
		-- Three cannons in a row, each sweeping at its own speed: a new rhythm every shot.
		name = "Cannon Chain",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 29, 0, -4 }, { amp = 40, move = 2.0 })
			local d1, c2x = deck(29, 0, -4, 8, 10)
			table.insert(parts, d1)
			local land2 = { c2x + 24, 0, 4 }
			table.insert(parts, cannon(c2x, 0, -4, land2, { amp = 40, move = 1.8, phase = 0.4 }))
			local d2, c3x = deck(land2[1], 0, 4, 8, 10)
			table.insert(parts, d2)
			local land3 = { c3x + 24, 0, 0 }
			table.insert(parts, cannon(c3x, 0, 4, land3, { amp = 40, move = 1.9, phase = 0.7 }))
			table.insert(parts, island(land3[1], 0, 0, 10, 10))
			return Kit.section(land3[1] + 5, 0, parts)
		end,
	},
	{
		-- The island rides a shuttle across the lane, holding at three stops: fire at the stop the aim is passing.
		name = "Drifting Island",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 37, 0, 0 }, { amp = 40, move = 2.3 })
			table.insert(
				parts,
				island(37, 0, -7, 10, 10, {
					marker = "ghostStop",
					motion = {
						kind = "path",
						points = { { 0, 0, 0 }, { 0, 0, 7 }, { 0, 0, 14 } },
						hold = 1.0,
						period = 7,
					},
				})
			)
			local length = exit(parts, 42 + EXIT_GAP, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A red goo wall across the lane with one hole: the dotted line turns red where the shot would hit it.
		name = "Hole in the Wall",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 37, 0, -4 }, { amp = 40, move = 2.6 })
			local wx = CANNON_X + 14
			table.insert(parts, gooWall(wx, -Kit.HALF, -8, WALL_LOW, WALL_HIGH))
			table.insert(parts, gooWall(wx, 0, Kit.HALF, WALL_LOW, WALL_HIGH))
			table.insert(parts, island(37, 0, -4, 12, 12))
			return Kit.section(43, 0, parts)
		end,
	},
	{
		-- Three shots with almost no ground between: each lands on a small perch right behind the next barrel.
		name = "Cannon to Cannon",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 27, 0, -3 }, { amp = 40, move = 2.0 })
			local p1, c2x = deck(27, 0, -3, 6, 8)
			table.insert(parts, p1)
			local land2 = { c2x + 20, 0, 3 }
			table.insert(parts, cannon(c2x, 0, -3, land2, { amp = 40, move = 1.9, phase = 0.35 }))
			local p2, c3x = deck(land2[1], 0, 3, 6, 8)
			table.insert(parts, p2)
			local land3 = { c3x + 20, 0, 0 }
			table.insert(parts, cannon(c3x, 0, 3, land3, { amp = 40, move = 1.8, phase = 0.8 }))
			table.insert(parts, island(land3[1], 0, 0, 10, 10))
			return Kit.section(land3[1] + 5, 0, parts)
		end,
	},
	{
		-- The island breathes on the beat: full size on the tick, down to 6 wide between. Fire so you land on a tick
		-- while the aim is on it.
		name = "Breathing Island",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 37, 0, 0 }, { amp = 35, move = 2.1 })
			table.insert(
				parts,
				island(37, 0, 0, 14, 14, { beat = 2.5, motion = { kind = "shrink", min = 6 / 14, period = 1.5 } })
			)
			local length = exit(parts, 44 + EXIT_GAP, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Climbing in starts the clock: red goo wells up through the seat and floods it 3 s later, so take the first
		-- good aim instead of waiting for a perfect one.
		name = "Hot Seat",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 35, 0, 6 }, { amp = 40, move = 1.6, hold = 0.3 }, { trigger = "seat", marker = "cracks" })
			table.insert(parts, seatFlood(CANNON_X, 0, 0, "seat"))
			table.insert(parts, island(35, 0, 6, 12, 12))
			return Kit.section(41, 0, parts)
		end,
	},
	{
		-- Three cannons and every landing island drifts across the lane: time the barrel and the island together,
		-- three times in a row. A short hop from each island onto the next barrel's deck.
		name = "Moving Chain",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local function drifter(x: number, period: number, phase: number): Kit.Part
				return island(x, 0, 0, 9, 9, {
					marker = "ghostStop",
					motion = { kind = "slide", axis = "z", amp = 6, period = period, phase = phase },
				})
			end
			local aim = { amp = 35, move = 1.6 }
			start(parts, 0, { 27, 0, 0 }, aim)
			table.insert(parts, drifter(27, 2.6, 0))
			local x = 31.5 + 3 -- the deck: a 3-stud hop past the island
			table.insert(parts, Kit.slab(x + 3, 0, 0, 6, 10, "jelly", { tone = 3 }))
			local c2x = x + 4
			table.insert(parts, cannon(c2x, 0, 0, { c2x + 20, 0, 0 }, { amp = 35, move = 1.6, phase = 0.3 }))
			table.insert(parts, drifter(c2x + 20, 3.2, 0.4))
			x = c2x + 24.5 + 3
			table.insert(parts, Kit.slab(x + 3, 0, 0, 6, 10, "jelly", { tone = 3 }))
			local c3x = x + 4
			table.insert(parts, cannon(c3x, 0, 0, { c3x + 20, 0, 0 }, { amp = 35, move = 1.6, phase = 0.6 }))
			table.insert(parts, drifter(c3x + 20, 2.9, 0.75))
			local length = exit(parts, c3x + 24.5 + EXIT_GAP, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The barrel sweeps left-right while the high ledge slides back and forth: the shot's reach is fixed, so fire
		-- when the aim is on the ledge and the ledge is at the shot's distance (no pitch motion in the kit).
		name = "Two Axes",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 37, 8, 0 }, { amp = 35, move = 2.0, arc = 50 })
			table.insert(
				parts,
				island(37, 8, 0, 8, 8, {
					marker = "ghostStop",
					motion = { kind = "slide", axis = "x", amp = 8, period = 3.1 },
				})
			)
			table.insert(parts, Kit.slab(54, 8, 0, 6, Kit.WIDTH, "jelly", { tone = 3 }))
			return Kit.section(57, 8, parts)
		end,
	},
	{
		-- The hole in the goo wall slides between two stops while the barrel sweeps: the aim, the hole and the island
		-- must all line up when you fire.
		name = "Sliding Hole",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			start(parts, 0, { 39, 0, 4 }, { amp = 35, move = 1.8 })
			local wx = CANNON_X + 16
			table.insert(parts, gooWall(wx, -Kit.HALF, -8, WALL_LOW, WALL_HIGH))
			table.insert(parts, gooWall(wx, 8, Kit.HALF, WALL_LOW, WALL_HIGH))
			-- The plug: 8 wide, holding 1 s over the left half of the hole, then over the right half.
			table.insert(
				parts,
				gooWall(wx, -8, 0, WALL_LOW, WALL_HIGH, {
					marker = "ghostStop",
					motion = { kind = "path", points = { { 0, 0, 0 }, { 0, 0, 8 } }, hold = 1.0, period = 3.2 },
				})
			)
			table.insert(parts, island(39, 0, 4, 12, 10))
			return Kit.section(45, 0, parts)
		end,
	},
	{
		-- Four cannons, fast sweeps, zig-zag islands; the last shot must clear the hole in a goo wall. Every seat is hot
		-- (goo wells up 3 s after you climb in, as in Hot Seat): no barrel to rest in on the way.
		name = "Four Fast Shots",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local function hot(n: number): { [string]: any }
				return { trigger = `seat{n}`, marker = "cracks" }
			end
			start(parts, 0, { 27, 0, -4 }, { amp = 35, move = 1.2 }, hot(1))
			table.insert(parts, seatFlood(CANNON_X, 0, 0, "seat1"))
			local d1, c2x = deck(27, 0, -4, 8, 8)
			table.insert(parts, d1)
			local land2 = { c2x + 21, 0, 4 }
			table.insert(parts, cannon(c2x, 0, -4, land2, { amp = 35, move = 1.3, phase = 0.3 }, hot(2)))
			table.insert(parts, seatFlood(c2x, 0, -4, "seat2"))
			local d2, c3x = deck(land2[1], 0, 4, 8, 8)
			table.insert(parts, d2)
			local land3 = { c3x + 21, 0, -4 }
			table.insert(parts, cannon(c3x, 0, 4, land3, { amp = 35, move = 1.2, phase = 0.55 }, hot(3)))
			table.insert(parts, seatFlood(c3x, 0, 4, "seat3"))
			local d3, c4x = deck(land3[1], 0, -4, 8, 8)
			table.insert(parts, d3)
			local land4 = { c4x + 18, 0, 0 }
			table.insert(parts, cannon(c4x, 0, -4, land4, { amp = 35, move = 1.2, phase = 0.8 }, hot(4)))
			table.insert(parts, seatFlood(c4x, 0, -4, "seat4"))
			local wx = c4x + 9
			table.insert(parts, gooWall(wx, -Kit.HALF, -4, WALL_LOW, WALL_HIGH))
			table.insert(parts, gooWall(wx, 4, Kit.HALF, WALL_LOW, WALL_HIGH))
			table.insert(parts, island(land4[1], 0, 0, 8, 10))
			return Kit.section(land4[1] + 4, 0, parts)
		end,
	},
}

return M
