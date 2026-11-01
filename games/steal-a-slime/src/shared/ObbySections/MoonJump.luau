--!strict
--[[
	Moon Jump (obby idea 28, docs/obby-variants/28.json; contract/obby-sections.md)

	Low gravity bubbles: inside a `moon` zone (a see-through bubble dome, ObbyMoves carries 1 - gravity of your
	weight) your own jump floats much higher and further, so the gaps and steps here are too big for a normal jump.
	Moon jumps always start from your own jump, never a pad or a column.

	How the checks see it (tests/ObbyCheck): a jump that starts inside a bubble reaches GAP_MAX / gravity across and
	RISE_MAX / gravity up, so every moon gap is sized to that limit (the real float goes about 40 % further; that spare
	is the same one the 6-stud GAP_MAX keeps on a normal 8.7-stud jump). Every bubble box reaches from below its islands
	to over the highest arc (7.2 / gravity up plus a head), so gravity never changes mid-flight unless a variant wants
	it to (Bubble Edge).

	Hazards and the fairness runner: the runner models a normal jump (7.2 up), so a goo hedge standing in a moon gap
	would read as a wall it can never pass. Hedges and walls here therefore sink below the floor (a `path` on y with a
	hold at each end) for a tier-sized window; when they are up they stand taller than the moon arc at that point, so
	the timing is real, not decor. Ceilings, roof bars and the floating blobs of the hard variants sit above the normal
	jump band, where only the moon arc reaches; tests/obby/MoonJump.spec checks those with a real-arc sim. Every
	variant has a red goo pit or a timed hazard (contract §10).

	Moon Pulse is simplified: zones have no on / off in the kit, so the bubble stays and its landing islands blink on
	the beat instead (a `flip` snapped to 6 beats: lit 2.4 s, gone 1.2 s, each a third of a bar after the one before).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part

local PAD = 10 -- the entry pad's length
local PIT_DROP = 8 -- the goo pit's top under the lowest island
local SIGN = "sign:LOW GRAVITY"
-- Moon Pulse: the blinking islands' phases. The first is lit for 0 .. 2.4 s of the 3.6 s bar, the second from
-- 3.0 s on: off the first in its last ~0.95 s, a 1.55 s float lands you on the second while it is lit.
local PULSE_PHASE = { 0, 1 / 6 }

-- How high a jump floats at `gravity` (studs of the feet over the take-off).
local function apex(gravity: number): number
	return Kit.JUMP_HEIGHT / gravity
end

-- A walking platform from x0 to x0 + long, top `top`, centred on z, `wide` across.
local function island(
	parts: { Part },
	x0: number,
	long: number,
	top: number,
	z: number,
	wide: number,
	tone: number,
	extra: { [string]: any }?
): Part
	local e: { [string]: any } = { tone = tone }
	for k, v in (extra or {}) :: { [string]: any } do
		e[k] = v
	end
	local p = Kit.slab(x0 + long / 2, top, z, long, wide, "jelly", e)
	table.insert(parts, p)
	return p
end

-- The entry pad (x 0..long, top 0) with the low gravity sign.
local function entry(parts: { Part }, long: number?, wide: number?, z: number?): Part
	return island(parts, 0, long or PAD, 0, z or 0, wide or Kit.WIDTH, 1, { marker = SIGN })
end

-- A moon bubble over x0..x1 for islands whose tops run from `low` to `high`: tall enough for the whole arc (plus a
-- head and 2 to spare), and reaching a third of that under the lowest island so the dome's widest part sits near the
-- islands.
local function bubble(parts: { Part }, x0: number, x1: number, gravity: number, low: number, high: number)
	local top = high + apex(gravity) + Kit.HEAD + 2
	local bottom = low - (top - low) / 3
	table.insert(
		parts,
		Kit.prop({ x1 - x0, top - bottom, Kit.WIDTH }, { (x0 + x1) / 2, (top + bottom) / 2, 0 }, "moon", {
			ghost = true,
			zone = { kind = "moon", gravity = gravity },
		})
	)
end

-- A red goo pit (a thin sheet) over x0..x1 with its top at `top`.
local function pit(parts: { Part }, x0: number, x1: number, top: number)
	table.insert(parts, Kit.hazard({ x1 - x0, 1, Kit.WIDTH }, { (x0 + x1) / 2, top - 0.5, 0 }))
end

-- A lane-wide goo wall `thick` along x, centred on x, standing `top` over the floor when it is up (it reaches 2 under
-- the floor). It sinks `down` and comes back (a path with `hold` s at each end), so it is gone from the jump for a
-- tier-sized window each `period`.
local function sinker(
	parts: { Part },
	x: number,
	thick: number,
	top: number,
	down: number,
	period: number,
	hold: number,
	phase: number
)
	local tall = top + 2
	table.insert(
		parts,
		Kit.hazard({ thick, tall, Kit.WIDTH }, { x, top - tall / 2, 0 }, {
			motion = {
				kind = "path",
				points = { { 0, 0, 0 }, { 0, -down, 0 } },
				period = period,
				hold = hold,
				phase = phase,
			},
		})
	)
end

-- Glowing rim strips along an island's near and far edges (Moon Night): ghost decor.
local function rims(parts: { Part }, p: Part)
	local x0, x1 = p.pos[1] - p.size[1] / 2, p.pos[1] + p.size[1] / 2
	local top = p.pos[2] + p.size[2] / 2
	for _, x in { x0 + 0.2, x1 - 0.2 } do
		table.insert(parts, Kit.prop({ 0.4, 0.2, p.size[3] }, { x, top + 0.1, p.pos[3] }, "glow", { ghost = true }))
	end
end

local M = {}
M.id = "MoonJump"
M.name = "Moon Jump"
M.idea = 28

M.variants = {
	{
		-- One bubble at half gravity over three 12-stud gaps (the checks' moon limit, twice a normal jump) onto
		-- 9 x 10 islands, red goo pit below.
		name = "First Float",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local g, gap, long, wide = 0.5, 12, 9, 10
			local parts = {}
			entry(parts)
			local x = PAD
			for i = 1, 2 do
				x += gap
				island(parts, x, long, 0, 0, wide, 1 + i % 3)
				x += long
			end
			x += gap
			island(parts, x, PAD, 0, 0, wide, 1)
			local length = x + PAD
			bubble(parts, 0, length, g, 0, 0)
			pit(parts, 0, length, -PIT_DROP)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Climb at half gravity: four 9 x 10 islands each 7 higher than the last (the checks' moon rise, twice a normal
		-- jump) across 10-stud gaps, so the float has to go up and out. The draft's +9 is over the limit (3.5 / 0.5).
		name = "Moon Steps",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local g, gap, long, wide, step = 0.5, 10, 9, 10, 7
			local parts = {}
			entry(parts)
			local x, top = PAD, 0
			for i = 1, 4 do
				x += gap
				top += step
				island(parts, x, long, top, 0, wide, 1 + i % 3)
				x += long
			end
			bubble(parts, 0, x, g, 0, top)
			pit(parts, 0, x, -PIT_DROP)
			return Kit.section(x, top, parts)
		end,
	},
	{
		-- Two goo hedges in the middle of 13-stud gaps at 45 % gravity. Up, a hedge stands 14 high, over the float's
		-- path at that point; it sinks under the floor for about 1.5 s a cycle (about 2 s under the float's path). Wait for it, then float over.
		name = "Goo Hedge",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local g, gap, long = 0.45, 13, 10
			local parts = {}
			entry(parts)
			local x = PAD
			for i = 1, 2 do
				sinker(parts, x + gap / 2, 3, 17, 20, 4.4, 1.75, if i == 1 then 0 else 0.5)
				x += gap
				island(parts, x, long, 0, 0, long, 1 + i)
				x += long
			end
			bubble(parts, 0, x, g, 0, 0)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- Two huge leaps at 30 % gravity (a jump 24 high, 1.8 s in the air): 20 studs onto a 10 x 10 island, then 18
		-- studs and 6 up onto the exit. The draft's 22 is over the checks' moon reach (6 / 0.3 = 20).
		name = "Long Leap",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local g, land = 0.3, 10
			local parts = {}
			entry(parts)
			local a = PAD + 20
			island(parts, a, land, 0, 0, land, 2)
			local f = a + land + 18
			island(parts, f, PAD, 6, 0, land, 1)
			local length = f + PAD
			bubble(parts, 0, length, g, 0, 6)
			pit(parts, 0, length, -PIT_DROP)
			return Kit.section(length, 6, parts)
		end,
	},
	{
		-- A small bubble over each 12-stud gap with plain ground between: the 6-stud hop in the middle is a normal
		-- jump (the full GAP_MAX), so you feel the gravity change at the bubble's edge.
		name = "Bubble, Ground, Bubble",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local g, gap, hop, long, wide = 0.5, 12, 6, 8, 10
			local parts = {}
			entry(parts)
			local a = PAD + gap -- island A (outside both bubbles but for its near 3 studs)
			island(parts, a, long, 0, 0, wide, 2)
			local b = a + long + hop -- island B, in the second bubble
			island(parts, b, long, 0, 0, wide, 3)
			local f = b + long + gap
			island(parts, f, PAD, 0, 0, wide, 1)
			local length = f + PAD
			bubble(parts, 0, a + 3, g, 0, 0) -- ends 1 short of island A's middle
			bubble(parts, b - 2, length, g, 0, 0)
			pit(parts, 0, length, -PIT_DROP)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Islands zig-zag 7 off centre at 40 % gravity; a goo pillar taller than the float stands on the straight line
		-- between each pair and sways 3 side to side, so you curve every arc round it, on the side it leaves open.
		name = "Steer Round",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local g, gap, long, off = 0.4, 14, 10, 7
			local parts = {}
			local pillarTop = apex(g) + Kit.HEAD + 3
			entry(parts, long, long, -off)
			local x = long
			for i = 1, 3 do
				local side = if i % 2 == 1 then 1 else -1
				table.insert(
					parts,
					Kit.hazard({ 4, pillarTop + 6, 4 }, { x + gap / 2, (pillarTop - 6) / 2, 0 }, {
						motion = { kind = "slide", axis = "z", amp = 3, period = 3, phase = (i - 1) / 3 },
					})
				)
				x += gap
				island(parts, x, long, 0, side * off, long, 1 + i % 3)
				x += long
			end
			bubble(parts, 0, x, g, 0, 0)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- A goo wall stands 2 in front of each 8-long island across a 15-stud gap at 35 % gravity. Up, it is 22 high,
		-- over the top of the float; it sinks for about 1.1 s (about 1.5 s under the float's path). A full-speed float from the edge overshoots the island,
		-- so you drop over the wall and pull back onto the island tucked behind it. The second wall sinks only 0.34 s
		-- after the first while a hop between them takes about 1.5 s: hop on at once (or mash jump) and it stands in
		-- your way, so you wait on the first island for it.
		name = "Over and Back",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local g, gap, long, wall = 0.35, 15, 8, 2
			local parts = {}
			entry(parts)
			local x = PAD
			for i = 1, 2 do
				x += gap
				sinker(parts, x - 2 - wall / 2, wall, 22, 25, 3.4, 1.35, if i == 1 then 0 else 0.1)
				island(parts, x, long, 0, 0, 10, 1 + i)
				x += long
			end
			bubble(parts, 0, x, g, 0, 0)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- Each island has its own bubble at 40 % that ends 10 into the 15-stud gap after it: float out, then normal
		-- gravity takes over and you drop fast onto an 8-long island 10 lower. Only a jump from the last 3.5 studs
		-- reaches it; an early one falls short. Three drops.
		name = "Bubble Edge",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local g, gap, long, drop, edge = 0.4, 15, 8, 10, 6
			local parts = {}
			entry(parts)
			bubble(parts, 0, PAD + edge, g, 0, 0)
			local x, top = PAD, 0
			for i = 1, 3 do
				x += gap
				top -= drop
				island(parts, x, if i < 3 then long else PAD, top, 0, 10, 1 + i % 3)
				if i < 3 then
					bubble(parts, x, x + long + edge, g, top, top)
					x += long
				else
					x += PAD
				end
			end
			pit(parts, 0, x, top - PIT_DROP)
			return Kit.section(x, top, parts)
		end,
	},
	{
		-- Three 9 x 9 islands slide 7.5 side to side (3.5 s, alternating) over 17-stud gaps at 35 % gravity: the long
		-- float lets you watch the one ahead and steer to meet it.
		name = "Drifting Islands",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local g, gap, long, pad = 0.35, 17, 9, 8
			local parts = {}
			entry(parts, pad)
			local x = pad
			for i = 1, 3 do
				x += gap
				island(parts, x, long, 0, 0, long, 1 + i % 3, {
					motion = {
						kind = "slide",
						axis = "z",
						amp = 7.5,
						period = 3.5,
						phase = if i % 2 == 0 then 0.5 else 0,
					},
					marker = "arrows",
				})
				x += long
			end
			x += gap - 1
			island(parts, x, pad, 0, 0, 10, 1)
			x += pad
			bubble(parts, 0, x, g, 0, 0)
			pit(parts, 0, x, -PIT_DROP)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- A lane-wide goo bar sweeps 28 up and down (4 s) through the middle of each 14-stud gap at 40 % gravity, right
		-- across the float's path: go when it is low and sail over it, or when it is high and float under it.
		name = "Bobbing Goo",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local g, gap, long = 0.4, 14, 10
			local parts = {}
			entry(parts)
			local x = PAD
			for i = 1, 2 do
				table.insert(
					parts,
					Kit.hazard({ 4, 4, Kit.WIDTH }, { x + gap / 2, 18, 0 }, {
						motion = { kind = "slide", axis = "y", amp = 14, period = 4, phase = if i == 1 then 0 else 0.5 },
					})
				)
				x += gap
				island(parts, x, long, 0, 0, long, 1 + i)
				x += long
			end
			bubble(parts, 0, x, g, 0, 0)
			pit(parts, 0, x, -PIT_DROP)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- Two bubbles: half gravity over two 12-stud gaps, then a quarter gravity over one 24-stud gap onto an 8-long
		-- pad. The same jump goes twice as far in the second, and a full-speed one from the edge overshoots the pad.
		name = "Two Moons",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local a = PAD + 12
			island(parts, a, 9, 0, 0, 10, 2)
			local b = a + 9 + 12
			island(parts, b, 9, 0, 0, 10, 3)
			local f = b + 9 + 24
			island(parts, f, 8, 0, 0, 10, 1, { marker = "sign:LOWER GRAVITY" })
			local length = f + 8
			bubble(parts, 0, b + 2, 0.5, 0, 0) -- ends 2.5 short of the last take-off island's middle
			bubble(parts, b + 2, length, 0.25, 0, 0)
			pit(parts, 0, length, -PIT_DROP)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Dark inside the bubble (a Lights Out zone): only the islands' rims glow, so you judge the long, slow arc by a
		-- few lit edges. Four 15-stud gaps at 40 % gravity onto 9-long islands, two of them climbing 8.
		name = "Moon Night",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local g, gap, long = 0.4, 15, 9
			local parts = {}
			rims(parts, entry(parts))
			local x, top = PAD, 0
			for i, up in { 8, 0, 8, 0 } do
				x += gap
				top += up
				rims(parts, island(parts, x, long, top, 0, 10, 1 + i % 3))
				x += long
			end
			bubble(parts, 0, x, g, 0, top)
			table.insert(
				parts,
				Kit.prop(
					{ x, 50, Kit.WIDTH },
					{ x / 2, 12, 0 },
					"dark",
					{ ghost = true, zone = { kind = "dark", light = 8 } }
				)
			)
			pit(parts, 0, x, -PIT_DROP)
			return Kit.section(x, top, parts)
		end,
	},
	{
		-- Simplified (a zone has no on / off in the kit): the bubble stays at 35 % and its two 8 x 9 landing islands
		-- blink on the beat, lit 2.4 s and gone 1.2 s. The second lights 3 s after the first, so from the first you
		-- go in the last second it is lit (about a second before the next lights up) or one of them is gone under you.
		-- Three 17-stud gaps.
		name = "Moon Pulse",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local g, gap, long = 0.35, 17, 8
			local parts = {}
			entry(parts)
			local x = PAD
			for i = 1, 2 do
				x += gap
				island(parts, x, long, 0, 0, 9, 1 + i, {
					beat = 6,
					motion = { kind = "flip", duty = 4 / 6, period = Kit.beat(6), phase = PULSE_PHASE[i] },
				})
				x += long
			end
			x += gap
			island(parts, x, PAD, 0, 0, 9, 1)
			x += PAD
			bubble(parts, 0, x, g, 0, 0)
			pit(parts, 0, x, -PIT_DROP)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- A red goo roof at 14 over the middle of every 16-stud gap at 35 % gravity (a 20-high float): jump from the
		-- skylight over the last few studs of each 8-long island, or your tall arc hits the roof going up or coming down.
		name = "Skylights",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local g, gap, long, roof = 0.35, 16, 8, 14
			local parts = {}
			entry(parts)
			local x = PAD
			for i = 1, 3 do
				-- the roof over gap x + 7 .. x + 13: clear of a jump from the last few studs of the island going up and
				-- coming down (see the spec)
				table.insert(parts, Kit.hazard({ 6, 1, Kit.WIDTH }, { x + 10, roof + 0.5, 0 }))
				x += gap
				island(parts, x, if i < 3 then long else PAD, 0, 0, 10, 1 + i % 3)
				x += if i < 3 then long else PAD
			end
			bubble(parts, 0, x, g, 0, 0)
			pit(parts, 0, x, -PIT_DROP)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- A long float at 25 % gravity (2.2 s in the air) between a red goo floor 4 under the islands and goo ceiling
		-- bars at 18 over each gap's middle; three 24-stud gaps onto 8 x 8 islands. A full-speed jump from the edge
		-- overshoots: jump early and fly over the bar, or brake in the air.
		name = "Goo Sandwich",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local g, gap, long = 0.25, 24, 8
			local parts = {}
			entry(parts)
			local x = PAD
			for i = 1, 3 do
				table.insert(parts, Kit.hazard({ 8, 1, Kit.WIDTH }, { x + 13, 18.5, 0 }))
				x += gap
				island(parts, x, long, 0, 0, long, 1 + i % 3)
				x += long
			end
			bubble(parts, 0, x, g, 0, 0)
			pit(parts, 0, x, -4)
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- One enormous float at 20 % gravity (36 high, 2.7 s in the air) over a 30-stud gap while three goo blobs slide
		-- 8.5 side to side through the arc (3 s); land on an 8 x 10 pad. The entry pad is 14 long and a float is about
		-- 41 studs, so you run in a few studs first and jump from its middle: one the moment you step on (or mashing
		-- jump) comes down in the goo just short of the pad.
		name = "Last Leap",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local g, gap, land, pad = 0.2, 30, 8, 14
			local parts = {}
			entry(parts, pad)
			island(parts, pad + gap, land, 0, 0, 10, 2)
			local length = pad + gap + land
			-- x, y, phase: each blob crosses the lane a little after the one before, so one gap in the three opens
			-- for about 0.85 s (tests/obby/MoonJump.spec)
			for _, blob in { { 18, 31, 0 }, { 28, 38, 0.8 }, { 37, 32, 0.6 } } do
				table.insert(
					parts,
					Kit.hazard({ 7, 7, 7 }, { blob[1], blob[2], 0 }, {
						shape = "ball",
						motion = { kind = "slide", axis = "z", amp = 8.5, period = 3, phase = blob[3] },
					})
				)
			end
			bubble(parts, 0, length, g, 0, 0)
			pit(parts, 0, length, -PIT_DROP)
			return Kit.section(length, 0, parts)
		end,
	},
} :: { Kit.Variant }

return M
