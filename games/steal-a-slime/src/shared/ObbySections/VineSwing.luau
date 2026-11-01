--!strict
--[[
	Vine Swing (obby idea 15, docs/obby-variants/15.json; contract/obby-sections.md)

	Green goo ropes swing over a red goo pit: jump at the knob on a rope's end to grab it (ObbyMoves' vine
	controller), ride it, and jump to let go with the rope's speed. The knob is the `vine` step (a small goo ball
	with handprints, so "green goo = grab it" reads as on Climb's ladders); the rope above it and the rail it hangs
	from are ghost decor that move with it.

	Along-course swings: the kit's `swing` only swings across the course (z), so a rope that swings along the course
	is a `path` loop over its pendulum arc (forward and back, rising at both ends) and hangs from a curved rail that
	follows the arc. A rope that swings across the lane (Side Swing, Zigzag Vines) is a real `swing`.

	Every knob hangs HANG studs over the pad it is let go onto (a hanging player's feet just over that pad). Grab
	reach is wider on easy ropes (REACH). The distances (pad edge to rope, rope to rope, rope to landing) are tuned
	per contract §10 on the hand-over windows, which tests/obby/VineSwing.spec measures with the same grab and
	release rules as tests/ObbyCheck: easy 1.4..2.0 s, medium 1.0..1.4 s, hard 0.75..1.0 s.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local KNOB = 1.8 -- the grab knob (a ball) at the rope's end: the vine step
local HANG = 6 -- studs from a pad's top up to the bottom of the knob over it, at rest
local PIT = -4 -- top of the red goo pit under every chain (above the fall reset, so you see it get you)
local ENTRY = 10 -- the entry pad's length
local REACH = table.freeze({ easy = 4, medium = 3.5, hard = 3 })

export type Rope = {
	x: number, -- the knob's rest x (bottom of the swing)
	z: number?,
	ends: number?, -- the knob's bottom at rest (HANG by default)
	arm: number, -- pivot to knob centre
	amp: number, -- degrees each way
	period: number,
	phase: number?,
	reach: number,
	across: boolean?, -- a real swing across the lane (z)
	slide: { number }?, -- { x, z, swings, slides }: a composite path, the anchor slides x / z studs
}

-- The pendulum arc as path offsets: forward to +amp, back through the bottom to -amp, and back (loop).
local function arcPoints(arm: number, amp: number): { Kit.Vec }
	local a = math.rad(amp)
	local out = {}
	for _, f in { 0, 1 / 3, 2 / 3, 1, 2 / 3, 1 / 3, 0, -1 / 3, -2 / 3, -1, -2 / 3, -1 / 3 } do
		local th = a * f
		table.insert(out, { arm * math.sin(th), arm * (1 - math.cos(th)), 0 })
	end
	return out
end

-- A swing along the course while the anchor slides `sx` along / `sz` across: `swings` swings and `slides` slides a
-- period, sampled as a path loop.
local function slidePoints(
	arm: number,
	amp: number,
	sx: number,
	sz: number,
	swings: number,
	slides: number
): { Kit.Vec }
	local out = {}
	local n = 48
	for k = 0, n - 1 do
		local u = k / n
		local th = math.rad(amp) * math.sin(2 * math.pi * swings * u)
		local s = math.sin(2 * math.pi * slides * u)
		table.insert(out, { arm * math.sin(th) + sx * s, arm * (1 - math.cos(th)), sz * s })
	end
	return out
end

local function motionOf(r: Rope): Kit.Motion
	if r.across then
		return { kind = "swing", amp = r.amp, arm = r.arm, period = r.period, phase = r.phase }
	end
	local slide = r.slide
	local points = if slide
		then slidePoints(r.arm, r.amp, slide[1], slide[2], slide[3], slide[4])
		else arcPoints(r.arm, r.amp)
	return { kind = "path", points = points, loop = true, period = r.period, phase = r.phase }
end

-- One rope: the knob (the vine step), the rope above it and the rail or pivot it hangs from.
local function rope(parts: { Kit.Part }, r: Rope)
	local z = r.z or 0
	local ends = r.ends or HANG
	local m = motionOf(r)
	table.insert(
		parts,
		Kit.prop({ KNOB, KNOB, KNOB }, { r.x, ends + KNOB / 2, z }, "blob", {
			shape = "ball",
			step = true,
			vine = { reach = r.reach },
			motion = m,
			marker = "handprints",
		})
	)
	local long = r.arm - KNOB / 2 -- knob top to the pivot
	local top = ends + KNOB + long -- the rope's top (pivot height) at rest
	local ropeMotion: Kit.Motion = table.clone(m)
	if r.across then
		ropeMotion.arm = long / 2
	end
	table.insert(
		parts,
		Kit.prop({ 0.6, long, 0.6 }, { r.x, top - long / 2, z }, "goo", { ghost = true, motion = ropeMotion })
	)
	local slide = r.slide
	if r.across then
		table.insert(parts, Kit.prop({ 1.6, 1.2, 1.6 }, { r.x, top + 0.6, z }, "post", { ghost = true }))
	elseif slide then
		-- a frame the anchor slides on: over the whole range the rope's top covers
		local reachX = r.arm * math.sin(math.rad(math.abs(r.amp))) + math.abs(slide[1]) + 0.6
		local reachZ = math.abs(slide[2]) + 0.6
		local up = r.arm * (1 - math.cos(math.rad(r.amp)))
		table.insert(
			parts,
			Kit.prop({ 2 * reachX, 0.4, 2 * reachZ }, { r.x, top + up + 0.3, z }, "post", { ghost = true })
		)
	else
		-- a curved rail along the rope top's arc: three bars
		local a = math.rad(r.amp)
		local function at(f: number): (number, number)
			return r.x + r.arm * math.sin(a * f), top + r.arm * (1 - math.cos(a * f)) + 0.3
		end
		for _, seg in { { -1, -1 / 3 }, { -1 / 3, 1 / 3 }, { 1 / 3, 1 } } do
			local x0, y0 = at(seg[1])
			local x1, y1 = at(seg[2])
			local dx, dy = x1 - x0, y1 - y0
			table.insert(
				parts,
				Kit.prop({ math.sqrt(dx * dx + dy * dy) + 0.6, 0.4, 1 }, { (x0 + x1) / 2, (y0 + y1) / 2, z }, "post", {
					ghost = true,
					roll = math.deg(math.atan2(dy, dx)),
				})
			)
		end
	end
end

-- A pad from x0 to x1 with its top at `top`, `wide` across (default the lane), centred on z.
local function pad(
	parts: { Kit.Part },
	x0: number,
	x1: number,
	top: number,
	wide: number?,
	z: number?,
	extra: { [string]: any }?
)
	table.insert(parts, Kit.slab((x0 + x1) / 2, top, z or 0, x1 - x0, wide or Kit.WIDTH, "jelly", extra))
end

-- The entry pad (x 0..ENTRY, top 0).
local function entry(parts: { Kit.Part }, extra: { [string]: any }?)
	local e: { [string]: any } = { tone = 1 }
	for k, v in (extra or {}) :: { [string]: any } do
		e[k] = v
	end
	pad(parts, 0, ENTRY, 0, nil, nil, e)
end

-- The red goo pit from x0 to x1 (the whole lane), its top `top` (PIT by default).
local function pit(parts: { Kit.Part }, x0: number, x1: number, top: number?)
	local t = top or PIT
	table.insert(parts, Kit.hazard({ x1 - x0, 2, Kit.WIDTH }, { (x0 + x1) / 2, t - 1, 0 }))
end

-- Red goo strips flush with a pad's top all round it (x0..x1, z0..z1), `w` wide: miss the pad, land in goo.
local function ring(parts: { Kit.Part }, x0: number, x1: number, z0: number, z1: number, top: number, w: number)
	local y = top - 0.05 - 0.5
	local zc = (z0 + z1) / 2
	table.insert(parts, Kit.hazard({ w, 1, z1 - z0 + 2 * w }, { x0 - w / 2, y, zc }))
	table.insert(parts, Kit.hazard({ w, 1, z1 - z0 + 2 * w }, { x1 + w / 2, y, zc }))
	table.insert(parts, Kit.hazard({ x1 - x0, 1, w }, { (x0 + x1) / 2, y, z0 - w / 2 }))
	table.insert(parts, Kit.hazard({ x1 - x0, 1, w }, { (x0 + x1) / 2, y, z1 + w / 2 }))
end

-- Along-course ropes at `xs` (the same arm, swing and period), phases taken in turn from `phases`.
local function ropes(
	parts: { Kit.Part },
	tier: string,
	xs: { number },
	arm: number,
	amp: number,
	period: number,
	phases: { number }
)
	for i, x in xs do
		rope(parts, {
			x = x,
			arm = arm,
			amp = amp,
			period = period,
			phase = phases[(i - 1) % #phases + 1],
			reach = REACH[tier],
		})
	end
end

local M = {}
M.id = "VineSwing"
M.name = "Vine Swing"
M.idea = 15

M.variants = {
	{
		-- One slow rope over a short goo pit onto a wide pad: it teaches the whole move.
		name = "First Swing",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 25.5)
			ropes(parts, "easy", { 21.25 }, 12, 30, 3.7, { 0 })
			local length = 37.5
			pad(parts, 25.5, length, 0, 12, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Two ropes that swing together: let go of the first at its front, the second swings on with you.
		name = "Two in Step",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 34)
			ropes(parts, "easy", { 21, 30 }, 12, 30, 3.5, { 0 })
			local length = 46
			pad(parts, 34, length, 0, 12, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Rope, a wide island to land and breathe, then a second rope: each swing is a fresh start.
		name = "Rest Island",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 24.25)
			ropes(parts, "easy", { 20.5 }, 11, 30, 3.35, { 0 })
			pad(parts, 24.25, 36.25, 0, 10, nil, { tone = 2 })
			pit(parts, 36.25, 50.5)
			ropes(parts, "easy", { 46.75 }, 11, 30, 3.35, { 0.5 })
			local length = 60.5
			pad(parts, 50.5, length, 0, nil, nil, { tone = 3 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- One very long, slow rope with a huge arc: easy to grab, a long time to pick the moment to let go.
		name = "Long Lazy Vine",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 30.25)
			ropes(parts, "easy", { 23.5 }, 18, 35, 4.4, { 0 })
			local length = 42.25
			pad(parts, 30.25, length, 0, 10, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Each rope hangs 3 studs lower than the last: letting go early still drops you onto the next one.
		name = "Swing Down",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local drop = 3
			local rise = -2 * drop
			local exit = 46.75
			pit(parts, ENTRY, exit, rise + PIT)
			for i, x in { 20.25, 31.75, 43.25 } do
				rope(parts, {
					x = x,
					ends = HANG - (i - 1) * drop,
					arm = 10,
					amp = 30,
					period = 3.2,
					phase = if i % 2 == 0 then 0.5 else 0,
					reach = REACH.easy,
				})
			end
			local length = 56.75
			pad(parts, exit, length, rise, nil, nil, { tone = 2 })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The ropes swing across the lane: ride one sideways, let go onto a pad at the lane's edge, walk on.
		name = "Side Swing",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local reach = REACH.easy
			-- the entry pad and the side pads hug opposite lane edges, 10 apart corner to corner: too far to jump, so
			-- only the rope gets you across (and a 4-stud hole to everything in line, against the walker)
			pad(parts, 0, ENTRY, 0, 8, -8, { tone = 1 })
			-- no goo pit here: the side hops would read as unfair to the hazard runner; you fall and reset
			rope(parts, { x = 19, arm = 11, amp = 35, period = 3.2, reach = reach, across = true })
			pad(parts, 16, 24, 0, 8, 8, { tone = 2 })
			rope(parts, { x = 33.5, arm = 11, amp = 35, period = 3.2, phase = 0.5, reach = reach, across = true })
			pad(parts, 30, 38, 0, 8, -8, { tone = 2 })
			local length = 52.5
			pad(parts, 42.5, length, 0, nil, nil, { tone = 3 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three ropes back to back, swinging against each other: let go just as the next one comes at you.
		name = "Three Vine Chain",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 55)
			ropes(parts, "medium", { 21.5, 35.75, 50 }, 11, 35, 3.0, { 0, 0.5 })
			local length = 65
			pad(parts, 55, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Short, fast ropes: the moment to let go is short and comes often.
		name = "Quick Vines",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 54)
			ropes(parts, "medium", { 19.5, 30, 40.5, 51 }, 7, 40, 2.15, { 0, 0.5 })
			local length = 64
			pad(parts, 54, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A small pad between two ropes, framed by red goo: let go too early or too late and you land in goo.
		name = "Narrow Landing",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 53)
			ropes(parts, "medium", { 22 }, 12, 35, 3.2, { 0 })
			pad(parts, 27.5, 35.5, 0, 8, nil, { tone = 2 })
			ring(parts, 27.5, 35.5, -4, 4, 0, 3)
			ropes(parts, "medium", { 47.5 }, 12, 35, 3.2, { 0.5 })
			local length = 63
			pad(parts, 53, length, 0, nil, nil, { tone = 3 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Each rope hangs higher than the last: let go on the upswing to gain height, then hop up to the exit.
		name = "Vine Climb",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local climb = 2.5
			local xs = { 21.5, 36, 50.5 }
			local exit = 55.25
			pit(parts, ENTRY, exit)
			for i, x in xs do
				rope(parts, {
					x = x,
					ends = HANG + (i - 1) * climb,
					arm = 10,
					amp = 40,
					period = 3.0,
					phase = if i % 2 == 0 then 0.5 else 0,
					reach = REACH.medium,
				})
			end
			-- the landing sits 4.5 under the last knob (a release high on the upswing), then a hop to the top
			local landing = HANG + 2 * climb - 4.5
			pad(parts, exit, 63.25, landing, nil, nil, { tone = 2 })
			local length, rise = 73.25, 10
			pad(parts, 67.25, length, rise, nil, nil, { tone = 3 })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The second rope's anchor slides across the lane while it swings: wait on the first until it is in line.
		name = "Sliding Anchor",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 42
			pit(parts, ENTRY, exit)
			ropes(parts, "medium", { 21.75 }, 11, 35, 3.2, { 0 })
			-- 3 swings and 2 slides of 6 studs either side every 9.6 s
			rope(parts, {
				x = 36.25,
				arm = 11,
				amp = 35,
				period = 9.6,
				phase = 0.5 / 3,
				reach = REACH.medium,
				slide = { 0, 6, 3, 2 },
			})
			local length = 52
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A red goo bar hangs between two ropes: let go high and late to fly over it instead of through it.
		name = "Over the Goo Bar",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 44.25
			pit(parts, ENTRY, exit)
			ropes(parts, "medium", { 22.25, 38.25 }, 12, 40, 3.2, { 0, 0.5 })
			-- 4 tall, its top 4 under the knobs: let go low and your feet are under its top
			table.insert(parts, Kit.hazard({ 2, 4, 16 }, { 30.25, HANG - 6, 0 }))
			local length = 54.25
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Ropes swing across the lane, each a little behind the last: ride one to the side, catch the next as it
		-- gets there, and zigzag over.
		name = "Zigzag Vines",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			-- the entry pad on the left half: the first rope only comes in reach as it swings over to you
			pad(parts, 0, ENTRY, 0, 8, -8, { tone = 1 })
			local exit = 47.85
			pit(parts, ENTRY, exit)
			for i, x in { 19.25, 27.75, 36.25, 44.75 } do
				rope(parts, {
					x = x,
					arm = 10,
					amp = 40,
					period = 3.2,
					phase = -(i - 1) * 0.2,
					reach = REACH.medium,
					across = true,
				})
			end
			local length = 57.85
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The last rope throws you into a goo ladder on a high wall: let go on the upswing, climb out the top.
		name = "Vine to Ladder",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local wallAt = 43.75
			pit(parts, ENTRY, wallAt - 2)
			ropes(parts, "medium", { 21.75 }, 11, 40, 3.1, { 0 })
			local high = HANG + 2.5
			rope(parts, { x = 36.75, ends = high, arm = 11, amp = 40, period = 3.1, phase = 0.5, reach = REACH.medium })
			-- the ladder's foot is under the knob, so a hanging player's body meets it; the wall's top stays under
			-- the knob's top, so hanging on the rope next to it is well above the fall reset
			local bottom, rise = high - 5, high + 1.5
			table.insert(
				parts,
				Kit.prop({ 2, rise - bottom, 10 }, { wallAt - 1, (bottom + rise) / 2, 0 }, "goo", {
					shape = "truss",
					step = true,
					marker = "handprints",
				})
			)
			local length = 53.75
			local deep = rise - PIT
			table.insert(
				parts,
				Kit.prop({ length - wallAt, deep, Kit.WIDTH }, { (wallAt + length) / 2, rise - deep / 2, 0 }, "jelly", {
					step = true,
					tone = 2,
				})
			)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Five ropes over red goo with alternating swings and no rest: one bad release and you start over.
		name = "Five Vine Run",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 89.75)
			ropes(parts, "hard", { 21.75, 37.25, 52.75, 68.25, 83.75 }, 10, 40, 2.75, { 0, 0.5 })
			local length = 99.75
			pad(parts, 89.75, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Four ropes of different lengths, each on its own speed: the good moment shifts, read every rope fresh.
		name = "Drifting Beat",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 78
			pit(parts, ENTRY, exit)
			local arms = { 9, 11, 13, 10 }
			local periods = { 2.6, 3.1, 2.55, 3.5 }
			for i, x in { 21.25, 36.75, 54, 71.25 } do
				rope(parts, {
					x = x,
					arm = arms[i],
					amp = 40,
					period = periods[i],
					phase = if i % 2 == 0 then 0.5 else 0,
					reach = REACH.hard,
				})
			end
			local length = 88
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The anchors slide along the course while the ropes swing: the gap to the next rope grows and shrinks.
		name = "Pulling Anchors",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 70
			pit(parts, ENTRY, exit)
			for i, x in { 24, 43, 62 } do
				-- 4 swings (3.1 s) and 3 slides of 2 studs either way (4.13 s) in a 12.4 s period; every other
				-- rope mirrors its neighbour, so the gap between two anchors runs 12..20
				local sign = if i % 2 == 0 then -1 else 1
				rope(parts, {
					x = x,
					arm = 11,
					amp = 35 * sign,
					period = 12.4,
					reach = REACH.hard,
					slide = { 2 * sign, 0, 4, 3 },
				})
			end
			local length = 80
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three fast ropes end over a small, low pad ringed by red goo: let go on the downswing or overshoot.
		name = "Pinpoint Drop",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local low = -2
			pit(parts, ENTRY, 66.75, low + PIT)
			for i, x in { 21.25, 35.75, 50.25 } do
				rope(parts, {
					x = x,
					ends = low + HANG,
					arm = 9,
					amp = 40,
					period = 2.55,
					phase = if i % 2 == 0 then 0.5 else 0,
					reach = REACH.hard,
				})
			end
			pad(parts, 55.75, 63.75, low, 8, nil, { tone = 2 })
			ring(parts, 55.75, 63.75, -4, 4, low, 3)
			local length = 76.75
			pad(parts, 66.75, length, low, nil, nil, { tone = 3 })
			return Kit.section(length, low, parts)
		end,
	},
	{
		-- Red goo floods up under the ropes from the moment you step on: no time to wait for a perfect swing.
		name = "Snapping Vine",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts, { trigger = "snap" })
			local exit = 74.25
			ropes(parts, "hard", { 21.75, 37.25, 52.75, 68.25 }, 10, 40, 2.75, { 0, 0.5 })
			-- the flood: from the pit up to a hanging player's feet (5.5 under the knob) 9.3 s after the trigger,
			-- 1.25 s after the slowest run that takes every first good release (tests/obby/VineSwing.spec)
			local stop = HANG - 5.5 - PIT
			table.insert(
				parts,
				Kit.hazard({ exit - ENTRY - 1, 2, Kit.WIDTH }, { (ENTRY + exit) / 2, PIT - 1, 0 }, {
					motion = { kind = "rise", speed = 0.66, delay = 2.5, stop = stop },
					start = "snap",
				})
			)
			local length = 84.25
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
}

return M
