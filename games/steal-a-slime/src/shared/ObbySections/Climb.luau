--!strict
--[[
	Climb (obby idea 8, docs/obby-variants/8.json; contract/obby-sections.md)

	Ladders up the course: open lime lattice ladders (TrussParts, shape "truss", look "goo") are the only things you
	can climb; plain grey pillars and the tower are not. Red see-through drips hang under a dark nozzle (the warning),
	fall straight down the ladder and vanish into a dark drain cup, then the next one swells. Some ladders slide
	across the lane, hang over the void, or crack and fall away a moment after you grab them (`trigger` + `drop`).

	Kit rules every variant follows (tests/ObbyCheck):
	  * A ladder is a 2 x 2 x N truss (N even: a TrussPart's real size). You get on it from a step within 1.5 studs
	    (a short leap over the void at most: the kit has no longer "grab" jump) and off it at its top onto a step
	    within 2 studs whose top is at the ladder's top.
	  * A drip is a `path` (loop + jump) hazard ball: `hold` s at the nozzle (visible: the tell), a fast fall down the
	    climber's side of the ladder, `hold` s hidden in the drain, then back to the nozzle at once. The nozzle sits
	    over the highest step near it plus a head (so the checks see it as clear while it waits); the drain sits under
	    the step you climb from.
	  * Every walking line meets a hole of 4+ studs (mostly the 5-stud hop in from the entry pad): a real Roblox
	    character walking into a truss climbs it, so a ladder is never what stops a straight walk.

	Timing (tests/obby/Climb.spec measures it with a climber at CLIMB studs / s, see there): a drip's window is the
	time you have to set off up a ladder stretch and reach its top without the drip meeting you; tuned per §10
	(easy 1.4..2.0 s, medium 1.0..1.45 s, hard 0.75..1.05 s).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part

local TRUSS = 2 -- a TrussPart's cross-section
local ENTRY_LONG = 8 -- the entry pad, full lane width
local ENTRY_GAP = 5 -- the hop in from the entry pad: too long to walk over (ObbyCheck.walkStop)
local IN_FROM = ENTRY_LONG + ENTRY_GAP
local DRIP = 2 -- drip ball size
local DRIP_SPEED = 36 -- studs / s a drip falls
local NOZZLE_CLEAR = 6.3 -- a waiting drip's centre over the highest step near it: its bottom is a head (5) over it
local DRAIN_DROP = 2.4 -- a drained drip's centre under the step you climb from (hidden in the cup under that slab)

local M = {}
M.id = "Climb"
M.name = "Climb"
M.idea = 8

-- Helpers ------------------------------------------------------------------------------------------------------

local function add(parts: { Part }, ...: Part)
	for _, p in { ... } do
		table.insert(parts, p)
	end
end

-- A floor slab from x0 to x1 (top `top`), centred on z, `wide` across.
local function floor(x0: number, x1: number, top: number, z: number, wide: number, tone: number?): Part
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "jelly", { tone = tone or 1 })
end

-- A plain grey pillar (a step: you stand on its top) reaching down to y = -8.
local function pillar(x0: number, x1: number, top: number, z: number, wide: number): Part
	local depth = top + 8
	return Kit.prop({ x1 - x0, depth, wide }, { (x0 + x1) / 2, top - depth / 2, z }, "pad", { step = true })
end

-- A floating block (a step) `depth` thick.
local function block(x0: number, x1: number, top: number, z: number, wide: number, depth: number): Part
	return Kit.prop({ x1 - x0, depth, wide }, { (x0 + x1) / 2, top - depth / 2, z }, "jelly", { step = true, tone = 2 })
end

-- A ladder centred on (x, z) from y0 to y1.
local function ladder(x: number, z: number, y0: number, y1: number, extra: { [string]: any }?): Part
	assert((y1 - y0) % 2 == 0, "a truss is an even number of studs tall")
	local part = Kit.prop({ TRUSS, y1 - y0, TRUSS }, { x, (y0 + y1) / 2, z }, "goo", { shape = "truss", step = true })
	if extra then
		for k, v in extra do
			(part :: any)[k] = v
		end
	end
	return part
end

-- The entry pad (full lane width, top 0, x 0..8).
local function entry(parts: { Part })
	add(parts, floor(0, ENTRY_LONG, 0, 0, Kit.WIDTH, 1))
end

--[[
	A drip on (x, z): a ball waiting at `top` (centre) under a dark nozzle, falling to `bottom` (centre) inside a dark
	drain cup, every `period` s at `phase`. The fall takes (top - bottom) / speed s; the rest is split between the
	wait at the nozzle and the wait in the drain.
]]
local function drip(
	parts: { Part },
	x: number,
	z: number,
	top: number,
	bottom: number,
	period: number,
	phase: number,
	speed: number?
)
	local fall = (top - bottom) / (speed or DRIP_SPEED)
	local hold = (period - fall) / 2
	assert(hold > 0.2, "drip period too short for its fall")
	add(
		parts,
		Kit.hazard({ DRIP, DRIP, DRIP }, { x, top, z }, {
			shape = "ball",
			motion = {
				kind = "path",
				points = { { 0, 0, 0 }, { 0, bottom - top, 0 } },
				loop = true,
				jump = true,
				hold = hold,
				period = period,
				phase = phase,
			},
		}),
		Kit.prop({ 2.6, 1.4, 2.6 }, { x, top + DRIP / 2 + 0.7, z }, "post", { ghost = true }),
		Kit.prop({ 2.8, 2.6, 2.8 }, { x, bottom, z }, "post", { ghost = true })
	)
end

-- A goo glob (8 wide, so you can't step round it) dropping onto a pillar top at x every `period` s; it hides inside
-- the pillar between drops.
local function glob(parts: { Part }, x: number, z: number, top: number, period: number, phase: number)
	local high, low = top + NOZZLE_CLEAR, top - DRAIN_DROP
	local fall = (high - low) / DRIP_SPEED
	local hold = (period - fall) / 2
	assert(hold > 0.2, "glob period too short for its fall")
	add(
		parts,
		Kit.hazard({ 3, 2, 8 }, { x, high, z }, {
			motion = {
				kind = "path",
				points = { { 0, 0, 0 }, { 0, low - high, 0 } },
				loop = true,
				jump = true,
				hold = hold,
				period = period,
				phase = phase,
			},
		}),
		Kit.prop({ 3.6, 1.2, 8.4 }, { x, high + 1.6, z }, "post", { ghost = true })
	)
end

-- A crumbling ladder piece on clock `group`: it cracks and falls away `at` s after the clock starts (back when you are
-- reset to the start pad). With `trigger`, touching this piece starts the clock.
local function crumble(x: number, z: number, y0: number, y1: number, group: string, at: number, trigger: boolean): Part
	return ladder(x, z, y0, y1, {
		trigger = if trigger then group else nil,
		start = group,
		motion = { kind = "drop", at = at, period = 1 },
		marker = "cracks",
	})
end

-- A ladder riding between its rest and `dz` across the lane, `hold` s at each end, `move` s each way.
local function slider(x: number, z: number, y0: number, y1: number, dz: number, hold: number, move: number): Part
	return ladder(x, z, y0, y1, {
		motion = {
			kind = "path",
			points = { { 0, 0, 0 }, { 0, 0, dz } },
			hold = hold,
			period = 2 * hold + 2 * move,
		},
		marker = "rail",
	})
end

--[[
	The tower spiral (Tower Spiral, Leaning Tower Storm): a plain 12 x 12 tower at x 27..39 with an 8 x 8 corner
	ledge at each corner, `laps` times round, `step` studs up per ladder. Each ladder stands in the 4-stud strip
	between two corners along a face, against the next corner's edge, so at its top you step over onto that corner.
	Returns the parts and the ladders' climber-side face points { x, z } per face (front, right, back, left).
]]
local TOWER_X0, TOWER_X1 = 27, 39
local CORNERS = { -- centre x, z of each corner ledge in climbing order: front-right, back-right, back-left, front-left
	{ 27, 6 },
	{ 39, 6 },
	{ 39, -6 },
	{ 27, -6 },
}
-- Ladder centre and drip point (the climber's side of the ladder) for the ladder up to corner k.
local LADDERS = {
	{ x = 22, z = 7, dx = 21, dz = 7 }, -- base -> front-right (only the first lap; later laps come from front-left)
	{ x = 33.5, z = 7, dx = 32.5, dz = 7 }, -- front-right -> back-right, right face
	{ x = 40, z = -0.5, dx = 40, dz = 0.5 }, -- back-right -> back-left, back face
	{ x = 32.5, z = -7, dx = 33.5, dz = -7 }, -- back-left -> front-left, left face
}
local LAP_LADDER = { x = 25, z = 0, dx = 25, dz = -1 } -- front-left -> front-right, front face (second lap)

local function tower(parts: { Part }, laps: number, step: number): (number, { [string]: { number } })
	add(parts, floor(IN_FROM, 21, 0, 0, 16, 2))
	local y = 0
	for lap = 1, laps do
		for k = 1, 4 do
			local l = if k == 1 and lap > 1 then LAP_LADDER else LADDERS[k]
			add(parts, ladder(l.x, l.z, y, y + step))
			y += step
			local c = CORNERS[k]
			add(parts, floor(c[1] - 4, c[1] + 4, y, c[2], 8, (k % 3) + 1))
		end
	end
	local depth = y + 8
	add(
		parts,
		Kit.prop(
			{ TOWER_X1 - TOWER_X0, depth, 12 },
			{ (TOWER_X0 + TOWER_X1) / 2, y - depth / 2, 0 },
			"pad",
			{ step = true }
		)
	)
	add(parts, floor(43, 51, y, 0, 16, 3)) -- a 4-stud hop off the roof
	return y,
		{
			right = { LADDERS[2].dx, LADDERS[2].dz },
			back = { LADDERS[3].dx, LADDERS[3].dz },
			left = { LADDERS[4].dx, LADDERS[4].dz },
		}
end

-- Crumbling Rungs: seconds from grabbing a piece to it falling (an 8-stud piece takes 0.86 s to climb off; ObbyCheck.timers wants 1.84).
local CRUMBLE_AT = 1.85

-- Sliding Ladder: the ladder's wait by the ledge and move, and the phase that drops its drip as it arrives.
local SLIDE_HOLD, SLIDE_MOVE, SLIDE_DRIP_PHASE = 2.64, 0.7, 0.446

-- Variants -----------------------------------------------------------------------------------------------------

M.variants = {
	{
		-- Two ladders with a ledge and one 5-stud jump between them; each ladder has its own drip, half a beat apart.
		name = "First Rungs",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				ladder(9, 0, 0, 8),
				floor(10, 18, 8, 0, 10, 2),
				floor(23, 31, 8, 0, 10, 3),
				ladder(32, 0, 8, 18),
				floor(33, 44, 18, 0, 12, 1)
			)
			drip(parts, 8, 0, 8 + NOZZLE_CLEAR, -DRAIN_DROP, 3, 0.5)
			drip(parts, 31, 0, 18 + NOZZLE_CLEAR, 8 - DRAIN_DROP, 3, 0)
			return Kit.section(44, 18, parts)
		end,
	},
	{
		-- Hop up three plain pillars (+3 each, 5-stud gaps), then climb the ladder on the tall last pillar's face.
		name = "Pillar Steps",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				pillar(13, 21, 3, 0, 8),
				pillar(26, 34, 6, 0, 8),
				pillar(39, 47, 9, 0, 8),
				ladder(49, 0, 9, 21),
				pillar(50, 60, 21, 0, 8)
			)
			drip(parts, 48, 0, 21 + NOZZLE_CLEAR, 9 - DRAIN_DROP, 3.2, 0)
			return Kit.section(60, 21, parts)
		end,
	},
	{
		-- Round a plain square tower: a short ladder along each face to the next corner ledge, four turns, then
		-- over the roof. Two faces drip, half a beat apart.
		name = "Tower Spiral",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local top, faces = tower(parts, 1, 6)
			drip(parts, faces.right[1], faces.right[2], top + NOZZLE_CLEAR, 6 - DRAIN_DROP, 2.5, 0)
			drip(parts, faces.back[1], faces.back[2], top + NOZZLE_CLEAR, 12 - DRAIN_DROP, 2.5, 0.5)
			return Kit.section(51, top, parts)
		end,
	},
	{
		-- One tall ladder with one slow drip: wait beside it on the wide floor, watch the drop splat, then climb.
		name = "First Drip",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(IN_FROM, 23, 0, 0, 14, 2), ladder(24, 0, 0, 12), floor(25, 40, 12, 0, 12, 3))
			drip(parts, 23, 0, 12 + NOZZLE_CLEAR, -DRAIN_DROP, 3.2, 0)
			return Kit.section(40, 12, parts)
		end,
	},
	{
		-- Two grey columns side by side: only the one with lime rungs climbs; the plain one is just a wall.
		name = "Rungs or Plain",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 25, 0, 0, Kit.WIDTH, 2),
				ladder(24, 7, 0, 10),
				pillar(25, 33, 10, 7, 8),
				floor(37, 47, 10, 0, Kit.WIDTH, 3)
			)
			-- the plain column: same grey, no rungs (not a step: you can't get up it)
			add(parts, Kit.prop({ 8, 18, 8 }, { 29, 1, -7 }, "pad"))
			drip(parts, 23, 7, 10 + NOZZLE_CLEAR, -DRAIN_DROP, 3, 0)
			return Kit.section(47, 10, parts)
		end,
	},
	{
		-- Three ladders stacked up a shaft with a ledge between each, every one under its own drip on its own beat.
		name = "Drip Shaft",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 21, 0, 0, 12, 2),
				ladder(22, 0, 0, 8),
				floor(23, 31, 8, 0, 10, 3),
				ladder(32, 0, 8, 16),
				floor(33, 41, 16, 0, 10, 1),
				ladder(42, 0, 16, 24),
				floor(43, 53, 24, 0, 12, 2)
			)
			for i, phase in { 0, 0.33, 0.66 } do
				local foot = (i - 1) * 8
				drip(parts, 11 + 10 * i, 0, foot + 8 + NOZZLE_CLEAR, foot - DRAIN_DROP, 2.33, phase)
			end
			return Kit.section(53, 24, parts)
		end,
	},
	{
		-- One 20-stud ladder under a drip; two side notches let you step out of the drip's line and wait.
		name = "Ladder Notches",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 23, 0, 0, 12, 2),
				ladder(24, 0, 0, 8),
				floor(17, 25, 8, 6, 8, 3),
				ladder(24, 0, 8, 14),
				floor(17, 25, 14, -6, 8, 1),
				ladder(24, 0, 14, 20),
				floor(25, 40, 20, 0, 12, 2)
			)
			drip(parts, 23, 0, 20 + NOZZLE_CLEAR, -DRAIN_DROP, 2.3, 0)
			return Kit.section(40, 20, parts)
		end,
	},
	{
		-- The ladder rides across the lane and waits at each end; a drip falls down it just as it arrives by your
		-- ledge: let the drip pass, then leap in and climb before the ladder leaves.
		name = "Sliding Ladder",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 21, 0, -7, 8, 2),
				slider(23.5, -7, 0, 10, 14, SLIDE_HOLD, SLIDE_MOVE),
				floor(24.5, 36, 10, 0, Kit.WIDTH, 3)
			)
			drip(parts, 22.5, -7, 10 + NOZZLE_CLEAR, -DRAIN_DROP, 2 * (SLIDE_HOLD + SLIDE_MOVE), SLIDE_DRIP_PHASE)
			return Kit.section(36, 10, parts)
		end,
	},
	{
		-- Ladders hanging over the void, their feet under the ledge: leap off the edge into the rungs, twice, each
		-- under its own drip.
		name = "Leap and Grab",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 23, 0, 0, 12, 2),
				ladder(25.5, 0, -4, 8),
				floor(26.5, 34.5, 8, 0, 10, 3),
				ladder(37, 0, 4, 16),
				floor(38, 50, 16, 0, 12, 1)
			)
			drip(parts, 24.5, 0, 8 + NOZZLE_CLEAR, -DRAIN_DROP, 2.33, 0.5)
			drip(parts, 36, 0, 16 + NOZZLE_CLEAR, 2, 2.33, 0)
			return Kit.section(50, 16, parts)
		end,
	},
	{
		-- Each ladder takes you up and out to a ledge at the lane's edge, zigzagging with sky under every ledge; all
		-- four ladders drip, a quarter beat apart.
		name = "Over the Edge",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 21, 0, 0, 8, 2),
				ladder(22, 3, 0, 6),
				floor(23, 31, 6, 7, 8, 3),
				ladder(32, 3, 6, 12),
				floor(33, 41, 12, -1, 8, 1),
				ladder(42, -4, 12, 18),
				floor(43, 51, 18, -8, 8, 2),
				ladder(52, -4, 18, 24),
				floor(53, 63, 24, 0, Kit.WIDTH, 3)
			)
			drip(parts, 21, 3, 6 + NOZZLE_CLEAR, -DRAIN_DROP, 2.1, 0.75)
			drip(parts, 31, 3, 12 + NOZZLE_CLEAR, 6 - DRAIN_DROP, 2.1, 0)
			drip(parts, 41, -4, 18 + NOZZLE_CLEAR, 12 - DRAIN_DROP, 2.1, 0.25)
			drip(parts, 51, -4, 24 + NOZZLE_CLEAR, 18 - DRAIN_DROP, 2.1, 0.5)
			return Kit.section(63, 24, parts)
		end,
	},
	{
		-- Pillars with short ladders up their faces; goo globs drop onto the pillar tops on a beat. Wait at the
		-- ladder's top until one splats, then run across to the next ladder.
		name = "Drip Rain Pillars",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 21, 0, 0, 12, 2),
				ladder(22, 0, 0, 6),
				pillar(23, 31, 6, 0, 8),
				ladder(32, 0, 6, 12),
				pillar(33, 41, 12, 0, 8),
				ladder(42, 0, 12, 18),
				pillar(43, 51, 18, 0, 8),
				ladder(52, 0, 18, 24),
				pillar(53, 63, 24, 0, 8)
			)
			for i, phase in { 0, 0.33, 0.66 } do
				glob(parts, 17 + 10 * i, 0, 6 * i, 1.55, phase)
			end
			return Kit.section(63, 24, parts)
		end,
	},
	{
		-- Three ladder pieces with stone ledges between; each cracks and falls 1.85 s after you grab it, and the top
		-- two have drips: read the drip from the ledge, then climb without stopping.
		name = "Crumbling Rungs",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 21, 0, 0, 12, 2),
				crumble(22, 0, 0, 8, "c1", CRUMBLE_AT, true),
				pillar(23, 31, 8, 0, 10),
				crumble(32, 0, 8, 16, "c2", CRUMBLE_AT, true),
				pillar(33, 41, 16, 0, 10),
				crumble(42, 0, 16, 24, "c3", CRUMBLE_AT, true),
				floor(43, 53, 24, 0, 12, 3)
			)
			drip(parts, 31, 0, 16 + NOZZLE_CLEAR, 8 - DRAIN_DROP, 2.33, 0.5)
			drip(parts, 41, 0, 24 + NOZZLE_CLEAR, 16 - DRAIN_DROP, 2.33, 0)
			return Kit.section(53, 24, parts)
		end,
	},
	{
		-- A 24-stud ladder under a fast drip with one rest notch halfway: climb each half in one go between drops.
		name = "Drip Gauntlet",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 23, 0, 0, 12, 2),
				ladder(24, 0, 0, 12),
				floor(17, 25, 12, 6, 8, 3),
				ladder(24, 0, 12, 24),
				floor(25, 40, 24, 0, 12, 1)
			)
			drip(parts, 23, 0, 24 + NOZZLE_CLEAR, -DRAIN_DROP, 2.53, 0)
			return Kit.section(40, 24, parts)
		end,
	},
	{
		-- Two ladders over the void sliding opposite ways; they meet in the middle and wait together: grab the
		-- first, climb, leap across to the second and climb off before they part.
		name = "Sliding Pair",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				floor(IN_FROM, 21, 0, 0, 8, 2),
				slider(23.5, 0, 0, 8, 7, 2.72, 0.5),
				slider(27, 0, 6, 16, -7, 2.72, 0.5),
				floor(28, 40, 16, 0, Kit.WIDTH, 3)
			)
			return Kit.section(40, 16, parts)
		end,
	},
	{
		-- Floating blocks, each with a ladder hanging under its front edge: leap off one top into the next ladder,
		-- three times over the void, each ladder under its own fast drip.
		name = "Hanging Ladders",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(
				parts,
				ladder(10.5, 0, -2, 4),
				block(11.5, 19.5, 4, 0, 8, 2),
				ladder(22, 0, 2, 8),
				block(23, 31, 8, 0, 8, 2),
				ladder(33.5, 0, 6, 12),
				block(34.5, 42.5, 12, 0, 8, 2),
				floor(47.5, 57.5, 12, 0, 12, 3) -- a 5-stud jump to the exit
			)
			-- Over the void the checks give the runner a jump's height (Kit.JUMP_HEIGHT) over the last floor: the
			-- nozzle waits above that.
			for i, x in { 9.5, 21, 32.5 } do
				local board = (i - 1) * 4
				drip(parts, x, 0, board + Kit.JUMP_HEIGHT + NOZZLE_CLEAR, board - DRAIN_DROP, 1.6, (i - 1) / 3)
			end
			return Kit.section(57.5, 12, parts)
		end,
	},
	{
		-- The tower spiral twice round with 4-stud ladders, and drips down two faces: each drip crosses both laps,
		-- so read each face's beat twice.
		name = "Leaning Tower Storm",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local top, faces = tower(parts, 2, 4)
			drip(parts, faces.right[1], faces.right[2], top + NOZZLE_CLEAR, 4 - DRAIN_DROP, 1.6, 0)
			drip(parts, faces.left[1], faces.left[2], top + NOZZLE_CLEAR, 12 - DRAIN_DROP, 1.6, 0.5)
			return Kit.section(51, top, parts)
		end,
	},
	{
		-- One tall ladder of four crumbling pieces and no ledges under a drip: grabbing the bottom piece starts the
		-- collapse, piece by piece from the bottom just under your feet, so read the drip first and then climb
		-- without a stop.
		name = "Crumble Gauntlet",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(IN_FROM, 23, 0, 0, 12, 2))
			-- Falls 0.15 s apart (as close as ObbyCheck.timers allows), the top piece 0.52 s after a non-stop climber is
			-- off it: the collapse chases you up.
			for k, at in { 1.97, 2.12, 2.27, 2.81 } do
				add(parts, crumble(24, 0, (k - 1) * 6, k * 6, "g", at, k == 1))
			end
			add(parts, floor(25, 40, 24, 0, 12, 1))
			drip(parts, 23, 0, 24 + NOZZLE_CLEAR, -DRAIN_DROP, 3.94, 0)
			return Kit.section(40, 24, parts)
		end,
	},
}

return M
