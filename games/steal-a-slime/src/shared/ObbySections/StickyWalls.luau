--!strict
--[[
	Sticky Walls (obby idea 22, docs/obby-variants/22.json; contract/obby-sections.md)

	Dripping lime goo walls (`sticky`, look "sticky" + handprints) catch you in the air: you hold on and slide down at
	the wall's `sticky.fall` speed, and Jump throws you off, away from the face and up (ObbyMoves). Plain stone ("pad"
	look) next to the goo does not grip. Every section is a gap too wide to jump, crossed or climbed by wall hops.

	Geometry: walls run along the course (x) on the left (z < 0) or right (z > 0) of the lane, so a jump off throws
	you across the lane and you steer forward. A corridor's walls sit at z = +-CORRIDOR_Z (inner faces 10 apart), a
	chimney's at z = +-CHIMNEY_Z (9 apart). The checks (tests/ObbyCheck) measure a hop as the edge-to-edge gap from
	above: at most ObbyCheck.STICKY_REACH (about 11 studs) wall to wall and wall to floor, at most a jump (6) from a
	floor to a wall. A hop carries you only about half as far forward as across (thrown 30 studs / s across, steered
	at walking speed), so consecutive walls overlap or leave at most 5 studs of air along x, and an exit pad starts
	within about 4 studs of where the last wall ends.

	Stone patches (Patchy Walls, Goo Gauntlet, One Shot): the goo wall runs the whole corridor and plain stone
	STONE_THICK deep covers its face except at the patches, so the patches are goo recesses. Against the stone your
	root is further from the goo than ObbyMoves' grip reach (half the root's width + STICK_REACH = 2.2 studs), so
	only the recesses grip.

	The fairness runner of ObbyCheck follows floors and sidesteps 8 studs / s; it can't hop across the lane. So in
	every variant with red goo, one side's goo (the left) runs unbroken from the entry pad's end to the exit pad and
	the runner can follow it through the hazard stretch (Wall Steps, whose walls leave open air, has its red goo in
	strips under each wall instead). Red goo below the path never blocks that runner, so its windows don't measure
	these sections: the real timing is how long a wall holds you (height / slide speed), bounded per tier in
	tests/obby/StickyWalls.spec.

	Every variant opens on a 10-stud entry pad and has nothing to walk on after it: the walls are the only way over
	(the walk-forward check finds every line falling or hitting a wall or red goo). Goo Corridor's fall lands on a
	belt that carries you back to two steps up to its start in its first half (its design) and red goo in its second;
	every other variant has red goo.

	Kit translations: the sticky controller grips any goo part whatever its motion state, so dry goo is never the
	goo itself: it is plain stone (STONE_THICK, deeper than the grip reach) closing over the goo face. Drying Goo and
	Goo Gauntlet's middle patch use a `flip` stone skin (solid = dry, blinks before it opens); Quick Dry's walls are
	`trigger`s whose clock drops a stone shutter (a `path` `once`) over them 1 s after the first touch, for 3 s. Red
	drops are red balls on a one-way `path` loop (`jump` back to the top) sliding down the goo face; a "sheet" is a
	row of them too close together for a character to fit between.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local ENTRY_LONG = 10 -- the entry pad, x 0..10, full lane width
local WALL_THICK = 1 -- a goo wall's thickness across the lane
local CORRIDOR_Z = 5.5 -- corridor wall centres: inner faces 10 apart
local CHIMNEY_Z = 5 -- chimney wall centres: inner faces 9 apart
local PATCH_FACE = 5.5 -- stone-patch variants: goo inner faces 11 apart
local STONE_THICK = 1.5 -- stone in front of the goo: deeper than the grip reach past a root's side (1.2)
local POOL_THICK = 0.6 -- red goo pool slab
local POOL_TOP = -5.5 -- red goo under most walls: just below where the walls end
local DRIP_SIZE = 1.6 -- a red drop's diameter

local function with(part: Kit.Part, extra: { [string]: any }?): Kit.Part
	for k, v in (extra or {}) :: { [string]: any } do
		(part :: any)[k] = v
	end
	return part
end

-- A goo wall along x from x0 to x1 centred on z, bottom..top, sliding you down at `fall` studs / s: a path step.
local function goo(
	x0: number,
	x1: number,
	z: number,
	bottom: number,
	top: number,
	fall: number,
	extra: { [string]: any }?
): Kit.Part
	return with(
		Kit.prop({ x1 - x0, top - bottom, WALL_THICK }, { (x0 + x1) / 2, (bottom + top) / 2, z }, "sticky", {
			step = true,
			sticky = { fall = fall },
			marker = "handprints",
		}),
		extra
	)
end

-- A goo wall on `side` (-1 left, +1 right) of a stone-patch corridor, x0..x1.
local function patchGoo(
	x0: number,
	x1: number,
	side: number,
	bottom: number,
	top: number,
	fall: number,
	extra: { [string]: any }?
): Kit.Part
	return goo(x0, x1, side * (PATCH_FACE + WALL_THICK / 2), bottom, top, fall, extra)
end

-- Plain stone over the goo face on `side` from x0 to x1, except at `holes` ({ { a, b } } along x, in order).
local function stoneFace(
	parts: { Kit.Part },
	side: number,
	x0: number,
	x1: number,
	holes: { { number } },
	bottom: number,
	top: number
)
	local z = side * (PATCH_FACE - STONE_THICK / 2)
	local from = x0
	local function piece(a: number, b: number)
		if b - a > 0.01 then
			table.insert(
				parts,
				Kit.prop(
					{ b - a, top - bottom, STONE_THICK },
					{ (a + b) / 2, (bottom + top) / 2, z },
					"pad",
					{ tone = 1 }
				)
			)
		end
	end
	for _, h in holes do
		piece(from, h[1])
		from = h[2]
	end
	piece(from, x1)
end

-- A red goo pool (top `top`) over x0..x1, z0..z1 (default the whole lane).
local function pool(x0: number, x1: number, top: number, z0: number?, z1: number?): Kit.Part
	local a, b = z0 or -Kit.HALF, z1 or Kit.HALF
	return Kit.hazard({ x1 - x0, POOL_THICK, b - a }, { (x0 + x1) / 2, top - POOL_THICK / 2, (a + b) / 2 })
end

-- A red drop (diameter `size`, default DRIP_SIZE) sliding down the goo face at z `face` on `side` from `top` down
-- `fall` studs, every `period` s.
local function drip(
	x: number,
	face: number,
	side: number,
	top: number,
	fall: number,
	period: number,
	phase: number,
	size: number?
): Kit.Part
	local d = size or DRIP_SIZE
	local z = face - side * d / 2 -- touching the face, on the corridor side
	return Kit.hazard({ d, d, d }, { x, top - d / 2, z }, {
		shape = "ball",
		motion = {
			kind = "path",
			points = { { 0, 0, 0 }, { 0, -fall, 0 } },
			loop = true,
			jump = true,
			hold = 0.25,
			period = period,
			phase = phase,
		},
	})
end

--[[
	A sheet of drops: SHEET_DROP-wide red drops side by side along a goo wall x0..x1 (face z `face`, `side`), all on
	the same beat, so no gap between them fits a character (2 wide): the whole wall is swept every `period` s and you
	stick just after a sheet has passed your height.
]]
local SHEET_DROP = 2.4
local SHEET_STEP = 3.2 -- centre to centre: 0.8 between drops, narrower than a character
local function sheet(
	parts: { Kit.Part },
	x0: number,
	x1: number,
	face: number,
	side: number,
	top: number,
	bottom: number,
	period: number,
	phase: number
)
	local n = math.floor((x1 - x0) / SHEET_STEP + 0.5)
	local first = (x0 + x1) / 2 - (n - 1) * SHEET_STEP / 2
	for i = 1, n do
		local x = first + (i - 1) * SHEET_STEP
		table.insert(parts, drip(x, face, side, top, top - bottom - SHEET_DROP, period, phase, SHEET_DROP))
	end
end

--[[
	Dry goo, built so it works with the sticky controller as it is: a slab of plain stone (STONE_THICK, deeper than
	the grip reaches) right in front of a goo face from x0 to x1 on `side` at face z `face`. While the stone is solid
	the goo behind it can't grip (that is the "dry, grey" state); `extra` gives it its motion (a `flip` on a beat, or
	a `path` shutter on a trigger's clock).
]]
local function cover(
	x0: number,
	x1: number,
	face: number,
	side: number,
	bottom: number,
	top: number,
	extra: { [string]: any }?
): Kit.Part
	local z = face - side * STONE_THICK / 2
	return with(
		Kit.prop({ x1 - x0, top - bottom, STONE_THICK }, { (x0 + x1) / 2, (bottom + top) / 2, z }, "pad", { tone = 1 }),
		extra
	)
end

local function entry(parts: { Kit.Part }, z0: number?, z1: number?)
	local a, b = z0 or -Kit.HALF, z1 or Kit.HALF
	table.insert(parts, Kit.slab(ENTRY_LONG / 2, 0, (a + b) / 2, ENTRY_LONG, b - a, "jelly", { tone = 1 }))
end

-- The exit pad from x0 to `length`, top `rise`.
local function exit(parts: { Kit.Part }, x0: number, length: number, rise: number, z0: number?, z1: number?)
	local a, b = z0 or -Kit.HALF, z1 or Kit.HALF
	table.insert(parts, Kit.slab((x0 + length) / 2, rise, (a + b) / 2, length - x0, b - a, "jelly", { tone = 3 }))
end

--[[
	A chimney: `n` goo walls alternating left / right (left first) at +-CHIMNEY_Z, each 2 * `stepX` long (so each
	side's walls meet end to end), the next starting `stepX` further and `stepY` higher, `tall` each. When the last
	wall is a right one, the last left wall runs on to the chimney's end, so the left side is unbroken. Returns the x
	where the chimney ends and the last wall's top.
]]
local function chimney(
	parts: { Kit.Part },
	n: number,
	x0: number,
	bottom0: number,
	tall: number,
	stepX: number,
	stepY: number,
	fall: number
): (number, number)
	local long = 2 * stepX
	local xEnd = x0 + (n - 1) * stepX + long
	local lastLeft = if n % 2 == 1 then n else n - 1
	local topEnd = bottom0
	for i = 1, n do
		local side = if i % 2 == 1 then -1 else 1
		local a = x0 + (i - 1) * stepX
		local b = if i == lastLeft then xEnd else a + long
		local bottom = bottom0 + (i - 1) * stepY
		table.insert(parts, goo(a, b, side * CHIMNEY_Z, bottom, bottom + tall, fall))
		topEnd = bottom + tall
	end
	return xEnd, topEnd
end

-- A pick-the-hole screen: a red sheet parallel to the course at z = SCREEN_Z, x0..x1, from `low` to `high` with a
-- HOLE-tall hole from `hole0` (both halves share `motion` when it moves).
local SCREEN_Z = -1
local HOLE = 7 -- a character is 5 tall: 7 leaves a stud over and under while you fly through
local function screen(
	parts: { Kit.Part },
	x0: number,
	x1: number,
	low: number,
	hole0: number,
	high: number,
	motion: Kit.Motion?
)
	local cx = (x0 + x1) / 2
	table.insert(
		parts,
		Kit.hazard({ x1 - x0, hole0 - low, 1 }, { cx, (low + hole0) / 2, SCREEN_Z }, { motion = motion })
	)
	local h1 = hole0 + HOLE
	table.insert(
		parts,
		Kit.hazard({ x1 - x0, high - h1, 1 }, { cx, (h1 + high) / 2, SCREEN_Z }, {
			motion = if motion then table.clone(motion) else nil,
		})
	)
end

-- A stone shutter parked SHUTTER_PARK above a goo face that the wall's own `trigger` clock drops over it: wet for
-- SHUTTER_WET s after you first touch the wall, then dry (covered) for SHUTTER_DRY s, then it lifts and stays up
-- until you are reset to the start.
local SHUTTER_PARK = 8
local SHUTTER_WET = 1
local SHUTTER_DRY = 3
local SHUTTER_MOVE = 0.3 -- seconds each way
local function shutter(group: string, x0: number, x1: number, face: number, side: number, bottom: number, top: number)
	local drop = top - bottom + SHUTTER_PARK
	-- legs: rest -> down (after the wet hold), then held covered, then back up; every leg starts with a hold
	local hold = SHUTTER_WET
	local covered = { 0, -drop, 0 }
	local legsCovered = math.max(math.floor(SHUTTER_DRY / hold + 0.5), 1)
	local points = { { 0, 0, 0 } }
	for _ = 1, legsCovered do
		table.insert(points, covered)
	end
	table.insert(points, { 0, 0, 0 })
	return cover(x0, x1, face, side, top + SHUTTER_PARK, top + SHUTTER_PARK + (top - bottom), {
		start = group,
		motion = {
			kind = "path",
			points = points,
			hold = hold,
			once = true,
			period = hold * (#points - 1) + 2 * SHUTTER_MOVE,
		},
	})
end

local M = {}
M.id = "StickyWalls"
M.name = "Sticky Walls"
M.idea = 22

M.variants = {
	{
		-- One short goo wall along the left of an 18-stud gap (too wide to jump) over red goo: jump at the wall,
		-- stick, jump off across and forward onto the far pad before you slide off its bottom.
		name = "First Stick",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 44
			local parts = {}
			entry(parts)
			table.insert(parts, goo(10, 24, -11, -3, 7, 2))
			exit(parts, 28, length, 0)
			table.insert(parts, pool(10, 28, POOL_TOP))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Two goo walls 40 long, 10 apart: zigzag four hops between them. A fall in the first half lands on a belt
		-- that carries you back to two steps up to the corridor start; in the second half it is red goo.
		name = "Goo Corridor",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 64
			local parts = {}
			entry(parts)
			local fall = 2
			table.insert(parts, goo(10, 30, -CORRIDOR_Z, -2, 8, fall))
			table.insert(parts, goo(10, 30, CORRIDOR_Z, -2, 8, fall))
			table.insert(parts, goo(30, 50, -CORRIDOR_Z, -2, 8, fall))
			table.insert(parts, goo(30, 50, CORRIDOR_Z, -2, 8, fall))
			exit(parts, 54, length, 0)
			-- the safe floor under the first half: a belt back to the start, then two steps up onto the entry pad
			table.insert(
				parts,
				Kit.prop(
					{ 20, 1, Kit.WIDTH },
					{ 24, -8.5, 0 },
					"belt",
					{ tone = 2, conveyor = { -20, 0, 0 }, marker = "chevrons" }
				)
			)
			table.insert(parts, Kit.prop({ 2, 1, Kit.WIDTH }, { 11, -3.2, 0 }, "jelly", { tone = 2 }))
			table.insert(parts, Kit.prop({ 2, 1, Kit.WIDTH }, { 13, -5.9, 0 }, "jelly", { tone = 2 }))
			-- the second half: red goo at the belt's level
			table.insert(parts, pool(34, 54, -8))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The course drops down a 24-deep shaft (walls 9 apart): each wall catches you and slows the fall, three
		-- catches down to a small pad standing in a red pool.
		name = "Sticky Brakes",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 44, -24
			local parts = {}
			entry(parts)
			table.insert(parts, goo(12, 24, -CHIMNEY_Z, -8, 6, 2.5))
			table.insert(parts, goo(18, 30, CHIMNEY_Z, -16, -3, 2.5))
			table.insert(parts, goo(24, 36, -CHIMNEY_Z, -23, -11, 2.5))
			-- the pad fills the shaft between the wall faces: 8 long, 9 across
			local face = CHIMNEY_Z - WALL_THICK / 2
			exit(parts, 36, length, rise, -face, face)
			table.insert(parts, pool(10, length, rise - 0.5))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A short chute of two close walls (9 apart): each jump off climbs more than you slide, three hops up to a
		-- ledge 10 above the entry.
		name = "Up the Chute",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 46, 10
			local parts = {}
			entry(parts)
			local xEnd = chimney(parts, 3, 10, -4, 12, 5, 4, 2)
			exit(parts, xEnd, length, rise)
			table.insert(parts, pool(10, xEnd, POOL_TOP))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Three short walls on alternating sides with open air between them: aim at each wall in turn. Red goo
		-- right under each wall catches a slide off its bottom.
		name = "Wall Steps",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 70
			local parts = {}
			entry(parts)
			local walls = { { 12, 22, -5 }, { 27, 37, 5 }, { 42, 52, -5 } }
			for _, w in walls do
				table.insert(parts, goo(w[1], w[2], w[3], -4, 7, 2))
			end
			exit(parts, 57, length, 0)
			for _, w in walls do
				table.insert(parts, pool(w[1] + 1.5, w[2] - 1.5, POOL_TOP))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Plain stone walls with three goo patches (4 long, 11 apart across): hit stone and you slide straight
		-- down into the red, so you aim every hop at the next patch.
		name = "Patchy Walls",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 52
			local parts = {}
			entry(parts)
			local bottom, top, fall = -3, 7, 3
			local p1, p2, p3 = { 14, 18 }, { 22, 26 }, { 30, 34 }
			local wallTo = 37
			table.insert(parts, patchGoo(10, 26, -1, bottom, top, fall)) -- behind p1
			table.insert(parts, patchGoo(10, wallTo, 1, bottom, top, fall)) -- behind p2
			table.insert(parts, patchGoo(26, wallTo, -1, bottom, top, fall)) -- behind p3
			exit(parts, wallTo, length, 0)
			stoneFace(parts, -1, 10, wallTo, { p1, p3 }, bottom, top)
			stoneFace(parts, 1, 10, wallTo, { p2 }, bottom, top)
			table.insert(parts, pool(10, wallTo, POOL_TOP))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A sheet of red drops sweeps down every wall on its own beat (no gap between drops fits you): stick just
		-- after a sheet has gone past and jump off before the next one catches you.
		name = "Goo Drip",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 54
			local parts = {}
			entry(parts)
			local bottom, top, fall = -4, 10, 2
			local face = CORRIDOR_Z - WALL_THICK / 2
			local walls = { { 12, 24, -1, 0 }, { 18, 30, 1, 1 / 3 }, { 24, 36, -1, 2 / 3 } }
			for _, w in walls do
				table.insert(parts, goo(w[1], w[2], w[3] * CORRIDOR_Z, bottom, top, fall))
			end
			exit(parts, 40, length, 0)
			for _, w in walls do
				sheet(parts, w[1], w[2], w[3] * face, w[3], top, bottom, 2.2, w[4])
			end
			table.insert(parts, pool(10, 40, POOL_TOP))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- These walls barely hold (7 studs / s, about 1.4 s a wall) over a red floor at their feet: jump off almost
		-- as soon as you stick.
		name = "Fast Slide",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 52
			local parts = {}
			entry(parts)
			local bottom, top, fall = -5, 5, 7
			table.insert(parts, goo(12, 23, -CORRIDOR_Z, bottom, top, fall))
			table.insert(parts, goo(18, 28, CORRIDOR_Z, bottom, top, fall))
			table.insert(parts, goo(23, 34, -CORRIDOR_Z, bottom, top, fall))
			exit(parts, 38, length, 0)
			table.insert(parts, pool(10, 38, bottom))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A red screen runs down the middle of the lane with one 7-tall hole; slide down the goo wall until you are
		-- level with it, then jump through onto the pad behind it.
		name = "Pick Your Height",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 40, -2
			local parts = {}
			entry(parts, -Kit.HALF, -4)
			table.insert(parts, goo(8, length, -10.5, -4, 13, 2))
			exit(parts, 14, length, rise, 0, Kit.HALF)
			screen(parts, 6, length, -12, 0, 26, nil)
			table.insert(parts, pool(10, length, -6, -Kit.HALF, -2))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The right wall breathes in and out (gap 8 to 16, held 0.6 s at each end, every 2.8 s): jump across when it comes close.
		name = "Breathing Wall",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 58
			local parts = {}
			entry(parts)
			local bottom, top, fall = -3, 5, 2
			local breathe: Kit.Motion = {
				kind = "path",
				points = { { 0, 0, 0 }, { 0, 0, 8 } },
				hold = 0.6,
				period = 2.8,
			}
			table.insert(parts, goo(12, 24, -10.5, bottom, top, fall))
			table.insert(parts, goo(16, 28, -1.5, bottom, top, fall, { motion = table.clone(breathe) }))
			table.insert(parts, goo(24, 40, -10.5, bottom, top, fall))
			table.insert(parts, goo(28, 40, -1.5, bottom, top, fall, { motion = table.clone(breathe) }))
			exit(parts, 44, length, 0)
			table.insert(parts, pool(10, 44, POOL_TOP))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The goo dries on a beat: a grey stone skin closes over each wall for 1.8 s of every 3 (blinking before
		-- it opens), the three walls out of step. Dry goo can't hold you, so time each jump to land on wet goo.
		name = "Drying Goo",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 54
			local parts = {}
			entry(parts)
			local bottom, top, fall = -4, 9, 2
			local face = CORRIDOR_Z - WALL_THICK / 2
			local walls = { { 12, 24, -1, 0 }, { 18, 30, 1, 1 / 3 }, { 24, 36, -1, 2 / 3 } }
			for _, w in walls do
				table.insert(parts, goo(w[1], w[2], w[3] * CORRIDOR_Z, bottom, top, fall))
			end
			exit(parts, 40, length, 0)
			for _, w in walls do
				table.insert(
					parts,
					cover(w[1], w[2], w[3] * face, w[3], bottom, top, {
						motion = { kind = "flip", period = 3, duty = 1.8 / 3, phase = w[4] },
					})
				)
			end
			table.insert(parts, pool(10, 40, POOL_TOP))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A tall chimney (walls 9 apart) you zigzag up in five hops to a ledge 18 above the entry: keep the rhythm,
		-- every slow hop loses height.
		name = "Long Chimney",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 50, 18
			local parts = {}
			entry(parts)
			local xEnd = chimney(parts, 5, 10, -4, 12, 4, 4, 2.5)
			exit(parts, xEnd, length, rise)
			table.insert(parts, pool(10, xEnd, POOL_TOP))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Each goo wall dries 1 s after you touch it: a stone shutter parked above it slams down over the goo for
		-- 3 s. Stick, aim, go; there is no waiting on a wall.
		name = "Quick Dry",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 58
			local parts = {}
			entry(parts)
			local bottom, top, fall = -4, 9, 2
			local face = CORRIDOR_Z - WALL_THICK / 2
			local walls = { { 12, 26, -1 }, { 20, 32, 1 }, { 26, 40, -1 } }
			for i, w in walls do
				table.insert(parts, goo(w[1], w[2], w[3] * CORRIDOR_Z, bottom, top, fall, { trigger = `dry{i}` }))
			end
			exit(parts, 44, length, 0)
			for i, w in walls do
				table.insert(parts, shutter(`dry{i}`, w[1], w[2], w[3] * face, w[3], bottom, top))
			end
			table.insert(parts, pool(10, 44, POOL_TOP))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The bottom 4 studs of every goo wall are red goo: a slow hop slides you into it.
		name = "Red Toes",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 56
			local parts = {}
			entry(parts)
			local toe, top, fall = 0, 7, 3.5
			local walls = {
				{ 12, 26, -CORRIDOR_Z },
				{ 20, 32, CORRIDOR_Z },
				{ 26, 40, -CORRIDOR_Z },
			}
			for _, w in walls do
				table.insert(parts, goo(w[1], w[2], w[3], toe, top, fall))
			end
			exit(parts, 44, length, 0)
			for _, w in walls do
				-- the red toe stands a little proud of the goo on both faces, so a slide reaches it
				table.insert(
					parts,
					Kit.hazard({ w[2] - w[1], 4, WALL_THICK + 0.6 }, { (w[1] + w[2]) / 2, toe - 2, w[3] })
				)
			end
			table.insert(parts, pool(10, 44, -6))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A tall, fast chimney (4 studs / s) with big red drops sliding down every wall on their own beats:
		-- six hops up 22 with no time to rest.
		name = "Chimney Drip",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, rise = 50, 22
			local parts = {}
			entry(parts)
			local n, stepX, stepY, tall = 6, 3.5, 4, 12
			local xEnd = chimney(parts, n, 10, -4, tall, stepX, stepY, 4)
			exit(parts, xEnd, length, rise)
			local face = CHIMNEY_Z - WALL_THICK / 2
			-- big red drops on every wall, falling its height on their own beats: one in the middle of each left wall,
			-- two (a quarter and three quarters along) on each right one
			for i = 1, n do
				local side = if i % 2 == 1 then -1 else 1
				local a = 10 + (i - 1) * stepX
				local top = -4 + (i - 1) * stepY + tall
				for _, f in (if side < 0 then { 0.5 } else { 0.25, 0.75 }) :: { number } do
					local x = a + 2 * stepX * f
					local period = 2 + 0.2 * (i % 3)
					table.insert(
						parts,
						drip(x, side * face, side, top, tall - SHEET_DROP, period, (i * 0.37) % 1, SHEET_DROP)
					)
				end
			end
			table.insert(parts, pool(10, xEnd, POOL_TOP))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Like Pick Your Height, but the hole in the red screen shuttles up and down 8 studs: slide, watch, and jump
		-- the moment it lines up.
		name = "Moving Window",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, rise = 40, -4
			local parts = {}
			entry(parts, -Kit.HALF, -4)
			table.insert(parts, goo(8, length, -10.5, -6, 14, 2.5))
			exit(parts, 14, length, rise, 0, Kit.HALF)
			screen(parts, 6, length, -20, -2, 30, {
				kind = "path",
				points = { { 0, 0, 0 }, { 0, 8, 0 } },
				hold = 0.4,
				period = 3.4,
			})
			table.insert(parts, pool(10, length, -8, -Kit.HALF, -2))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A long stone corridor: five small goo patches (4 long), two red drops, and the middle patch dries on a
		-- beat (a stone plug fills it 1.5 s of every 2.4), so you can't stop there.
		name = "Goo Gauntlet",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 66
			local parts = {}
			entry(parts)
			local bottom, top, fall = -3, 7, 3
			local p = {} -- patches 1..5, 4 long, 8 apart along x; odd ones right, even ones left
			for i = 1, 5 do
				local x0 = 13 + (i - 1) * 8
				p[i] = { x0, x0 + 4 }
			end
			local wallTo = p[5][2] + 3
			table.insert(parts, patchGoo(10, p[3][1], 1, bottom, top, fall)) -- behind p1
			table.insert(parts, patchGoo(10, 33, -1, bottom, top, fall)) -- behind p2
			table.insert(parts, patchGoo(p[3][1], p[3][2], 1, bottom, top, fall)) -- behind p3
			table.insert(parts, patchGoo(33, wallTo, -1, bottom, top, fall)) -- behind p4
			table.insert(parts, patchGoo(p[3][2], wallTo, 1, bottom, top, fall)) -- behind p5
			exit(parts, wallTo, length, 0)
			stoneFace(parts, 1, 10, wallTo, { p[1], p[3], p[5] }, bottom, top)
			stoneFace(parts, -1, 10, wallTo, { p[2], p[4] }, bottom, top)
			-- p3's plug: stone that fills the recess while it is dry
			table.insert(
				parts,
				cover(p[3][1], p[3][2], PATCH_FACE, 1, bottom, top, {
					motion = { kind = "flip", period = 2.4, duty = 1.5 / 2.4, phase = 0.25 },
				})
			)
			local drop = top - bottom - DRIP_SIZE
			table.insert(parts, drip((p[2][1] + p[2][2]) / 2, -PATCH_FACE, -1, top, drop, 2.2, 0))
			table.insert(parts, drip((p[4][1] + p[4][2]) / 2, -PATCH_FACE, -1, top, drop, 2.4, 0.4))
			table.insert(parts, drip((p[5][1] + p[5][2]) / 2, PATCH_FACE, 1, top, drop, 2.6, 0.7))
			table.insert(parts, pool(10, wallTo, -5))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Tiny goo patches (3 long) on short stone walls over red goo, sliding 6 studs / s: every stick is one
		-- touch and an instant jump.
		name = "One Shot",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 46
			local parts = {}
			entry(parts)
			local bottom, top, fall = -2, 5, 6
			local p1, p2, p3 = { 13, 16 }, { 20, 23 }, { 27, 30 }
			local wallTo = 33
			table.insert(parts, patchGoo(10, 23, -1, bottom, top, fall)) -- behind p1
			table.insert(parts, patchGoo(10, wallTo, 1, bottom, top, fall)) -- behind p2
			table.insert(parts, patchGoo(23, wallTo, -1, bottom, top, fall)) -- behind p3
			exit(parts, wallTo, length, 0)
			stoneFace(parts, -1, 10, wallTo, { p1, p3 }, bottom, top)
			stoneFace(parts, 1, 10, wallTo, { p2 }, bottom, top)
			table.insert(parts, pool(10, wallTo, -3.5))
			return Kit.section(length, 0, parts)
		end,
	},
}

return M
