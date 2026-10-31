--!strict
--[[
	Rising Goo (obby idea 12, docs/obby-variants/12.json; contract/obby-sections.md)

	Red see-through goo fills the bottom of a tower and rises after you: climb before it reaches your feet. Touching
	the goo sends you back to the start pad (it is a `hazard`). The goo starts on the per-player clock "goo", which the
	first step (or the arch in Head Start Gate) starts when you touch it, and resets with every reset.

	The goo is built from `rise` parts. One rise part goes up at one speed after a delay, up to a stop. A goo surface
	that pauses, surges or speeds up is several rise parts stacked in the same pool, each starting a little lower and
	a little narrower (no z-fighting) and timed so the highest of them traces the planned curve: a pause is the next
	part starting later, a surge or a faster stretch is a steeper part catching up from below. That only works while
	the speed never drops between pauses (`flood` asserts it), so "slow between surges" is a full pause here.

	Fairness: tests/ObbyCheck.timers walks the steps at 16 studs / s (0.15 s per jump) from the trigger and needs every
	step clear of the goo 1 s after the runner leaves it. tests/obby/RisingGoo.spec adds a slower runner (0.3 s per
	jump, ladders at 8 studs / s, waiting for moving ledges) and measures the "slack": how many seconds that runner can
	dawdle at the bottom and still make it. The speeds below are tuned so the slack fits the tier (contract §10).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local GOO = "goo" -- the start group every flood reads
local GOO_TOP = -1.5 -- the goo surface at rest: just under the entry floor (its bottom is at -1)
local GOO_FLOOR = 6 -- studs of goo kept under the surface when a flood has risen all the way
local NUDGE = 0.1 -- each stacked flood part sits this much lower and narrower than the one before

-- One stretch of a flood plan: rise at `v` studs / s up to surface height `to`, or `wait` seconds.
type Seg = { v: number?, to: number?, wait: number? }

local function tone(k: number): number
	return k % 3 + 1
end

-- A walking-path platform from x0 to x1 with its top at `top`, centred on z, `w` across.
local function step(x0: number, x1: number, top: number, z: number, w: number, look: string?, extra: { [string]: any }?)
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, w, look or "jelly", extra)
end

--[[
	The goo pool over x0..x1 (the whole lane across): its surface starts at GOO_TOP, `delay` s after the "goo" clock
	starts, and follows `plan`. Returns the time and height where the plan ends.
]]
local function flood(parts: { Kit.Part }, x0: number, x1: number, delay: number, plan: { Seg }): (number, number)
	local t, h = delay, GOO_TOP
	local n, lastV = 0, 0
	for _, seg in plan do
		if seg.wait then
			t += seg.wait
			lastV = 0
		else
			local v, to = seg.v :: number, seg.to :: number
			assert(v >= lastV - 1e-9, "RisingGoo flood: the speed may only grow between pauses")
			assert(to > h, "RisingGoo flood: a stretch must rise")
			local base = GOO_TOP - NUDGE * n
			local inset = NUDGE / 2 * n
			-- The part's line passes (t, h) at speed v: it left its rest height `(h - base) / v` s earlier.
			local start = t - (h - base) / v
			assert(start >= -1e-9, "RisingGoo flood: a part would have to start before the clock")
			local stop = to - base
			local deep = stop + GOO_FLOOR
			table.insert(
				parts,
				Kit.hazard(
					{ x1 - x0 - 2 * inset, deep, Kit.WIDTH - 2 * inset },
					{ (x0 + x1) / 2, base - deep / 2, 0 },
					{
						motion = { kind = "rise", speed = v, delay = math.max(start, 0), stop = stop },
						start = GOO,
					}
				)
			)
			t += (to - h) / v
			h, lastV, n = to, v, n + 1
		end
	end
	return t, h
end

-- A glowing high-water line along both lane edges at height y, x0..x1 (where a flood stops).
local function highWater(parts: { Kit.Part }, x0: number, x1: number, y: number)
	for _, z in { -Kit.HALF + 0.25, Kit.HALF - 0.25 } do
		table.insert(
			parts,
			Kit.prop({ x1 - x0, 0.3, 0.5 }, { (x0 + x1) / 2, y, z }, "glow", { ghost = true, tone = 1 })
		)
	end
end

-- A glowing rim plate under a rest ledge: the goo pauses just under it.
local function restRing(parts: { Kit.Part }, x0: number, x1: number, top: number, z: number, w: number)
	table.insert(
		parts,
		Kit.prop({ x1 - x0 + 1.2, 0.3, w + 1.2 }, { (x0 + x1) / 2, top - 0.5, z }, "glow", { ghost = true, tone = 1 })
	)
end

--[[
	Surge warning rails: a glowing rail up each lane edge from (x0, y0) to (x1, y1) that lights up on the goo clock
	while cycle < duty (a glow-only flip: it stays put). `period` = calm + surge, lit from `warn` s before each surge
	(the first surge `first` s after the clock starts) until it ends.
]]
local function surgeRails(
	parts: { Kit.Part },
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	period: number,
	first: number,
	warn: number,
	surge: number
)
	local dx, dy = x1 - x0, y1 - y0
	local length = math.sqrt(dx * dx + dy * dy)
	local litFrom = (first - warn) % period
	for _, z in { -Kit.HALF + 0.3, Kit.HALF - 0.3 } do
		table.insert(
			parts,
			Kit.prop({ length, 0.4, 0.4 }, { (x0 + x1) / 2, (y0 + y1) / 2 + 1, z }, "glow", {
				ghost = true,
				tone = 1,
				roll = math.deg(math.atan2(dy, dx)),
				start = GOO,
				motion = {
					kind = "flip",
					solid = true,
					period = period,
					duty = (warn + surge) / period,
					phase = (1 - litFrom / period) % 1,
				},
			})
		)
	end
end

-- A climbable truss ladder at x0..x0+2, from `bottom` to `bottom + height`, `w` across, centred on z.
local function ladder(x0: number, bottom: number, height: number, z: number, w: number): Kit.Part
	return Kit.prop({ 2, height, w }, { x0 + 1, bottom + height / 2, z }, "truss", { shape = "truss", step = true })
end

---------------------------------------------------------------------------
-- Variants
---------------------------------------------------------------------------

local M = {}
M.id = "RisingGoo"
M.name = "Rising Goo"
M.idea = 12

M.variants = {
	{
		-- A wide stair whose steps sit left and right, 5-stud jumps; the goo creeps up behind you. Draft 0.8 studs / s
		-- starting 3 s in; tuned up to 2.0 so the chase is felt (contract §10).
		name = "Slow Stairs",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 7 do
				table.insert(
					parts,
					step(
						14 * k,
						14 * k + 9,
						2.5 * k,
						if k % 2 == 0 then -4 else 4,
						10,
						"jelly",
						{ tone = tone(k), trigger = if k == 0 then GOO else nil }
					)
				)
			end
			local length, rise = 107, 17.5
			flood(parts, 0, length, 3.5, { { v = 2.0, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Five steps up; the goo rises just high enough to be scary and stops at a glowing high-water line, a stud
		-- under the fifth step. (Draft 0.9 studs / s; tuned up, starting 4 s in.)
		name = "Low Tide",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 5 do
				table.insert(
					parts,
					step(
						16 * k,
						16 * k + 12,
						3 * k,
						0,
						12,
						"jelly",
						{ tone = tone(k), trigger = if k == 0 then GOO else nil }
					)
				)
			end
			local length, rise = 92, 15
			local line = 11
			flood(parts, 0, length, 3.5, { { v = 2.3, to = line } })
			highWater(parts, 0, length, line)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The goo rises in three pushes and waits 3 s just under each of two wide rest ledges (glowing rims).
		name = "Rest Ledges",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			-- { long, wide, rest }
			local plan: { { any } } = {
				{ 8, 10 },
				{ 8, 10 },
				{ 8, 10 },
				{ 12, 12, true },
				{ 8, 10 },
				{ 8, 10 },
				{ 12, 12, true },
				{ 8, 10 },
				{ 8, 10 },
			}
			local x, rests = 0, {}
			for k, p in plan do
				local top = 2.5 * (k - 1)
				local long, wide = p[1] :: number, p[2] :: number
				table.insert(
					parts,
					step(x, x + long, top, 0, wide, "jelly", { tone = tone(k), trigger = if k == 1 then GOO else nil })
				)
				if p[3] then
					restRing(parts, x, x + long, top, 0, wide)
					table.insert(rests, top)
				end
				x += long + 3
			end
			local length = x - 3
			local rise = 2.5 * (#plan - 1)
			flood(parts, 0, length, 3.8, {
				{ v = 3.5, to = rests[1] - 1 },
				{ wait = 3 },
				{ v = 3.5, to = rests[2] - 1 },
				{ wait = 3 },
				{ v = 3.5, to = rise - 1 },
			})
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A ramp up the right side, a landing across the far end, back down the left side climbing, a landing across
		-- the near end, and up the right side again over the first ramp: 1.5 turns round a long pillar, four 3-stud
		-- gaps. Holding forward walks off the far landing.
		name = "Spiral Ramp",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 57, 20
			local parts = {
				Kit.ramp(0, 0, 44, 6, 7, 10, "jelly", { tone = 1, trigger = GOO }),
				step(47, 57, 6.5, 0, Kit.WIDTH, "jelly", { tone = 2 }),
				Kit.ramp(17, 13, 44, 7, -7, 10, "jelly", { tone = 3 }),
				step(4, 14, 13.5, 0, Kit.WIDTH, "jelly", { tone = 1 }),
				Kit.ramp(17, 14, 57, 20, 7, 10, "jelly", { tone = 2 }),
				Kit.prop({ 27, 33, 3 }, { 30.5, 21 - 33 / 2, 0 }, "post"),
			}
			flood(parts, 0, length, 2.4, { { v = 1.9, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- No chase: the goo goes up and down on a tide over the low walkway. Cross it at low tide, then climb above
		-- the glowing high-water line. Draft: a 6-stud tide on a 10 s cycle; a 5.5 s cycle leaves a 1.45 s window.
		name = "Tide Pool",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 70, 6.5
			local parts = {
				step(0, 8, 0, 0, Kit.WIDTH, "jelly", { tone = 1 }),
				step(11, 35, -2.5, 0, 14, "jelly", { tone = 2 }),
				step(38, 46, 0.5, 0, 12, "jelly", { tone = 3 }),
				step(49, 57, 3.5, 0, 12, "jelly", { tone = 1 }),
				step(60, 70, 6.5, 0, 12, "jelly", { tone = 2 }),
			}
			local mid, amp, deep = -3.5, 3, 6
			table.insert(
				parts,
				Kit.hazard({ 30, deep, Kit.WIDTH }, { 23, mid - deep / 2, 0 }, {
					motion = { kind = "slide", axis = "y", amp = amp, period = 5.5 },
				})
			)
			highWater(parts, 8, 38, mid + amp)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A wide pad with a glowing arch: the goo only starts when you run through the arch, after a 3-tick countdown,
		-- so you choose when the chase begins.
		name = "Head Start Gate",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {
				step(0, 16, 0, 0, Kit.WIDTH, "jelly", { tone = 1 }),
				Kit.prop({ 1, 10, 1 }, { 10.5, 5, -Kit.HALF + 0.5 }, "post"),
				Kit.prop({ 1, 10, 1 }, { 10.5, 5, Kit.HALF - 0.5 }, "post"),
				Kit.prop({ 1, 1, Kit.WIDTH }, { 10.5, 9.5, 0 }, "glow", { tone = 1, marker = "sign:3..2..1" }),
				Kit.prop({ 1, 9, Kit.WIDTH - 2 }, { 10.5, 4.5, 0 }, "glow", { ghost = true, tone = 1, trigger = GOO }),
			}
			for k = 1, 7 do
				local x0 = 20 + 13 * (k - 1)
				table.insert(
					parts,
					step(x0, x0 + 9, 3 * k, if k % 2 == 0 then -2 else 2, 12, "jelly", { tone = tone(k) })
				)
			end
			local length, rise = 107, 21
			flood(parts, 0, length, 3.5, { { v = 2.4, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Big shelves zigzag left and right as they climb: easy jumps, but you turn at every shelf.
		name = "Wide Switchback",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 5 do
				local z = if k % 2 == 0 then -7 else 7
				table.insert(
					parts,
					step(
						8 * k,
						8 * k + 12,
						3 * k,
						z,
						10,
						"jelly",
						{ tone = tone(k), trigger = if k == 0 then GOO else nil }
					)
				)
			end
			local length, rise = 52, 15
			flood(parts, 0, length, 3.5, { { v = 2.3, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A closed shaft: ledges stick out of the left and right walls and you jump across, back and forth, 5 studs a
		-- jump, with the goo close under you.
		name = "Zigzag Shaft",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 9 do
				local z = if k % 2 == 0 then -6.5 else 6.5
				table.insert(
					parts,
					step(
						4 * k,
						4 * k + 8,
						3 * k,
						z,
						8,
						"jelly",
						{ tone = tone(k), trigger = if k == 0 then GOO else nil }
					)
				)
			end
			local length, rise = 44, 27
			for _, z in { -Kit.HALF + 0.5, Kit.HALF - 0.5 } do
				table.insert(parts, Kit.prop({ length, rise + 12, 1 }, { length / 2, rise / 2, z }, "post"))
			end
			flood(parts, 0, length, 2.25, { { v = 2.65, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The fixed steps run out halfway; the rest are rafts resting at different heights that float up on the goo
		-- once it reaches them. Ride one up until you can hop to the next. The goo covers the last fixed step soon
		-- after it lifts the first raft.
		name = "Float Up",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 4 do
				table.insert(
					parts,
					step(
						11 * k,
						11 * k + 8,
						2.5 * k,
						0,
						12,
						"jelly",
						{ tone = tone(k), trigger = if k == 0 then GOO else nil }
					)
				)
			end
			local delay, v = 1.5, 1.4
			local final = 24 -- every raft's top once the goo stops (2.5 under the exit ledge)
			local gooStop = final - 1.5
			for k = 1, 4 do
				local top = 7 + 5 * (k - 1) -- rest top; the raft floats once the goo is 1.5 under it
				local hold = delay + (top - 1.5 - GOO_TOP) / v
				local up = final - top
				local x0 = 56 + 7 * (k - 1)
				table.insert(
					parts,
					step(x0, x0 + 10, top, if k % 2 == 1 then -7 else 7, 10, "plank", {
						tone = tone(k),
						start = GOO,
						motion = {
							kind = "path",
							points = { { 0, 0, 0 }, { 0, up, 0 } },
							once = true,
							hold = hold,
							period = hold + up / v,
						},
					})
				)
			end
			local length, rise = 96, final + 2.5
			table.insert(parts, step(84, 96, rise, -7, 10, "jelly", { tone = 3 }))
			flood(parts, 0, length, delay, { { v = v, to = gooStop } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Three ladders between ledges and a 5-stud jump after each: a ladder is slow and there is nowhere to dodge.
		name = "Ladder Dash",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				step(0, 8, 0, 0, 12, "jelly", { tone = 1, trigger = GOO }),
			}
			local x, top = 8, 0
			for k = 1, 3 do
				table.insert(parts, ladder(x + 1, top, 8, 0, 8))
				top += 8
				table.insert(parts, step(x + 3, x + 11, top, 0, 12, "jelly", { tone = tone(k) }))
				top += 2
				table.insert(parts, step(x + 16, x + 24, top, 0, 12, "jelly", { tone = tone(k + 1) }))
				x += 24
			end
			local length, rise = x, top
			flood(parts, 0, length, 1, { { v = 1.8, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The goo rests 2.8 s, then surges 9 studs in 2 s (draft: calm 5 s, 4 studs / s); glowing rails up the lane edges light up 1.5 s before each surge.
		-- Climb in the calm, be high when it comes.
		name = "Surge",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 8 do
				table.insert(
					parts,
					step(12 * k, 12 * k + 8, 3 * k, if k % 2 == 0 then -2 else 2, 12, "jelly", {
						tone = tone(k),
						trigger = if k == 0 then GOO else nil,
					})
				)
			end
			local length, rise = 104, 24
			local calm, surge, v = 2.8, 2, 4.5
			local plan: { Seg } = {}
			local h = GOO_TOP
			while h < rise - 1 - 1e-6 do
				if #plan > 0 then
					table.insert(plan, { wait = calm })
				end
				h = math.min(h + v * surge, rise - 1)
				table.insert(plan, { v = v, to = h })
			end
			flood(parts, 0, length, calm, plan)
			surgeRails(parts, 0, 0, length, rise, calm + surge, calm, 1.5, surge)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The ledges slide in and out of the left and right walls; jump when the next one is out, while the goo climbs.
		name = "Sliding Ledges",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				step(0, 4, 0, 0, Kit.WIDTH, "jelly", { tone = 1, trigger = GOO }),
			}
			for k = 1, 7 do
				local right = k % 2 == 1
				table.insert(
					parts,
					step(4 * k, 4 * k + 8, 3 * k, if right then 5.75 else -5.75, 8, "jelly", {
						tone = tone(k),
						motion = {
							kind = "slide",
							axis = "z",
							amp = if right then -2.25 else 2.25,
							period = 3,
							phase = 0.15 * k,
						},
					})
				)
			end
			local length, rise = 44, 24
			table.insert(parts, step(36, 44, rise, 0, Kit.WIDTH, "jelly", { tone = 2 }))
			flood(parts, 0, length, 1.6, { { v = 1.9, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Not a tower: a long basin of low steps (1.5 up each) that fills from behind, band by band, so the goo closes in
		-- from behind and below.
		name = "Flooding Basin",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local pitch = 9.5
			for k = 0, 8 do
				table.insert(
					parts,
					step(pitch * k, pitch * k + 7, 1.5 * k, if k % 2 == 0 then -1 else 1, 14, "jelly", {
						tone = tone(k),
						trigger = if k == 0 then GOO else nil,
					})
				)
			end
			local length, rise = pitch * 8 + 7, 12
			local first, every, v = 1.8, 0.5, 2.5
			for k = 0, 7 do
				-- one band per step, from its start to the next step's start, rising over it a stud
				flood(
					parts,
					pitch * k + 0.05,
					pitch * (k + 1) - 0.05,
					first + every * k,
					{ { v = v, to = 1.5 * k + 1 } }
				)
			end
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Twelve steps 30 degrees apart circle a central pillar, 2.5 up each, then a bridge over the pillar's top. You
		-- keep losing sight of the goo.
		name = "Spiral Tower",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local cx, r = 23, 8
			local parts = {
				step(0, 10, 0, 0, Kit.WIDTH, "jelly", { tone = 1, trigger = GOO }),
			}
			for k = 1, 11 do
				local angle = 180 + 30 * k
				local a = math.rad(angle)
				table.insert(
					parts,
					Kit.slab(
						cx + r * math.cos(a),
						2.5 * k,
						r * math.sin(a),
						8,
						4,
						"jelly",
						{ tone = tone(k), yaw = -angle }
					)
				)
			end
			-- the twelfth (back at the start's side, 30 up) is square: you turn off it onto the bridge
			table.insert(parts, Kit.slab(cx - r, 30, -1.5, 8, 8, "jelly", { tone = 3 }))
			local length, rise = 40, 32
			table.insert(parts, step(21, length, rise, 0, 8, "jelly", { tone = 2 }))
			table.insert(parts, Kit.prop({ 5, 41, 5 }, { cx, 29 - 41 / 2, 0 }, "post"))
			flood(parts, 0, length, 2, { { v = 3.6, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A sparkling valve on a side ledge partway up: touch it and the gate over a launch pad further up opens; the
		-- pad throws you two steps up. The detour pays off if you take it early. (Kit gap: the draft's valve paused the
		-- goo for 5 s; the kit has no pause on touch, so the valve opens a shortcut instead.)
		name = "Drain Valve",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			local function main(k: number)
				local x0 = 11 * (k - 1)
				table.insert(
					parts,
					step(
						x0,
						x0 + 8,
						3 * (k - 1),
						6,
						12,
						"jelly",
						{ tone = tone(k), trigger = if k == 1 then GOO else nil }
					)
				)
			end
			for k = 1, 3 do
				main(k)
			end
			-- the valve ledge beside step 3, one jump to the side, and its valve
			table.insert(parts, step(22, 30, 7.5, -8, 8, "goo", { tone = 1, route = "valve" }))
			table.insert(parts, Kit.prop({ 1.5, 1.5, 1.5 }, { 26, 10, -8 }, "key", { key = "valve" }))
			for k = 4, 5 do
				main(k)
			end
			-- the launch pad beside step 6 (as high as step 5) under its gate: it throws you onto step 8
			table.insert(
				parts,
				step(55, 63, 12, -8, 8, "spring", {
					route = "valve",
					marker = "rings3",
					motion = { kind = "bounce", power = 72, throw = { 28, 0, 10 } },
				})
			)
			table.insert(
				parts,
				Kit.prop({ 8, 10, 8 }, { 59, 17, -8 }, "gate", { gate = { group = "valve", need = 1 } })
			)
			for k = 6, 10 do
				main(k)
			end
			local length, rise = 107, 27
			flood(parts, 0, length, 2, { { v = 2.5, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A tight, steep climb: 3.5 up and 5 across every jump, with the goo almost as fast as you.
		name = "Fast Flood",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 9 do
				table.insert(
					parts,
					step(11 * k, 11 * k + 8, 3.5 * k, if k % 2 == 0 then -6 else 6, 8, "jelly", {
						tone = tone(k),
						trigger = if k == 0 then GOO else nil,
					})
				)
			end
			local length, rise = 107, 31.5
			flood(parts, 0, length, 1.5, { { v = 2.7, to = rise - 1 } })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A tall stair of 14 steps where the goo starts lazy and keeps speeding up: the top half is a sprint.
		name = "Speeding Flood",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 13 do
				table.insert(
					parts,
					step(7 * k, 7 * k + 8, 3 * k, if k % 2 == 0 then -6.5 else 6.5, 8, "jelly", {
						tone = tone(k),
						trigger = if k == 0 then GOO else nil,
					})
				)
			end
			local length, rise = 99, 39
			-- 1.0 -> 1.9 -> 3.0 studs / s, 3 s each, then flat out at 3.0 (faster than you climb)
			local h, plan = GOO_TOP, {}
			for _, v in { 1.0, 1.9 } do
				h += v * 3
				table.insert(plan, { v = v, to = h })
			end
			table.insert(plan, { v = 3.0, to = rise - 1 })
			flood(parts, 0, length, 1, plan)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The goo rises in quick swells, 1.5 s up and 1.5 s still, every 3 s: jump up while it holds. (Kit gap: a rise
		-- can't also fall back, so the draft's up-and-down wave is a swell-and-hold rhythm.)
		name = "Wave Rise",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			for k = 0, 9 do
				table.insert(
					parts,
					step(11 * k, 11 * k + 8, 3 * k, if k % 2 == 0 then -3 else 3, 10, "jelly", {
						tone = tone(k),
						trigger = if k == 0 then GOO else nil,
					})
				)
			end
			local length, rise = 107, 27
			local swell, still, v = 1.5, 1.5, 5.2
			local plan: { Seg } = {}
			local h = GOO_TOP
			while h < rise - 1 - 1e-6 do
				if #plan > 0 then
					table.insert(plan, { wait = still })
				end
				h = math.min(h + v * swell, rise - 1)
				table.insert(plan, { v = v, to = h })
			end
			flood(parts, 0, length, 2.4, plan)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Ladders and short jumps mixed under fast surges: be off each ladder and up high before the warning ends.
		-- (Ladders are 6 tall: a truss is sized in 2-stud steps. Between surges the goo holds still.)
		name = "Surge Ladders",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {
				step(0, 8, 0, 0, 12, "jelly", { tone = 1, trigger = GOO }),
			}
			local x, top = 8, 0
			for k = 1, 3 do
				table.insert(parts, ladder(x + 1, top, 6, 0, 8))
				top += 6
				table.insert(parts, step(x + 3, x + 11, top, 0, 12, "jelly", { tone = tone(k) }))
				top += 3
				table.insert(parts, step(x + 15, x + 23, top, 0, 12, "jelly", { tone = tone(k + 1) }))
				x += 23
			end
			local length, rise = x, top
			local calm, surge, v = 2, 2, 5.3
			local plan: { Seg } = {}
			local h = GOO_TOP
			while h < rise - 1 - 1e-6 do
				if #plan > 0 then
					table.insert(plan, { wait = calm })
				end
				h = math.min(h + v * surge, rise - 1)
				table.insert(plan, { v = v, to = h })
			end
			flood(parts, 0, length, calm, plan)
			surgeRails(parts, 0, 0, length, rise, calm + surge, calm, 1.5, surge)
			return Kit.section(length, rise, parts)
		end,
	},
}

return M
