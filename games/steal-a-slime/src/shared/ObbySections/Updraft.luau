--!strict
--[[
	Updraft (obby idea 5, docs/obby-variants/5.json; contract/obby-sections.md)

	See-through wind columns (`lift` motion) carry you up to high ledges: a dark fan at the bottom, rising leaves, a
	ring at the top. A capped column (`cap`) holds you hovering instead of throwing you out of its top; a bright frame
	shows where your feet hover. Timed columns (`duty`) fade their swirl 0.8 s before they cut out. A wind tunnel is a
	low capped lift laid along the course (it holds you up over a gap) with a forward `gust` over the same box.

	Walk-forward rule (§9, §11): the first column of every variant floats HOP (3.5) studs over the pad you enter it
	from, with nothing under it, and a 2.5-stud kerb on the pad's end in front of it. Walking stays under the column
	(a standing root is about 3 over the floor) and the kerb stops a walker cold: you have to jump in. Catch the Fall
	is the one column you drop into from above; its exit ledge is beside it, so riding straight up and on misses.

No mashing (§9): a rider holding forward and jumping on every landing crosses a column in half a second and drifts
straight on. So the way on out of a column (a ledge, the next column, a tunnel) sits on the other side of the lane
from it, at least 2 studs across: no straight line runs from the pad through the column to it. You steer across
while you rise or hover.

	Heights: ObbyFx's lift acts on the root (about ROOT = 3 over the feet). An uncapped column's rider tops out at
	top - ROOT + power^2 / 2g with the feet; a capped one hovers the feet at `bottom + cap - ROOT`. Every exit ledge
	sits at least a stud under that (tests/obby/Updraft.spec checks it), though ObbyCheck measures from `top` / `cap`.

	Timed columns: the on-time minus the ride (height / power, or a tunnel's length / its gust) is the window per §10
	(easy 1.4..2.0 s, medium 1.0..1.4, hard 0.75..1.0); tests/obby/Updraft.spec checks it.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local PAD = 10 -- the entry pad: x 0..PAD
local HOP = Kit.RISE_MAX -- a first column's bottom over the pad top: under it you walk, a jump gets you in
local KERB = 2.5 -- the kerb in front of a first column: taller than a step-up, an easy hop
local LIFT = 30 -- default column speed (studs / s)
local GUST = 24 -- forward push in a wind tunnel (over WalkSpeed 16, so it really carries you)
local ROOT = 3 -- feet to the root part a lift acts on
local POST_DEPTH = 10 -- a fan's post reaches this far under its fan

type Parts = { Kit.Part }

export type Column = {
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	bottom: number,
	top: number,
	power: number?,
	hover: number?, -- the root's hover height (absolute): sets `cap`
	on: number?, -- seconds on (timed column)
	off: number?, -- seconds off
	phase: number?,
	post: boolean?, -- a thin post under the fan (columns floating over the void)
	tunnel: boolean?, -- a wind tunnel along the course: fan plate on its start face, no post
	solidFan: boolean?, -- the fan is a floor you can land on (Catch the Fall's pit)
}

-- The motion of a column.
local function liftMotion(c: Column): Kit.Motion
	local m: Kit.Motion = { kind = "lift", power = c.power or LIFT }
	if c.hover then
		m.cap = c.hover - c.bottom
	end
	if c.on and c.off then
		m.period = c.on + c.off
		m.duty = c.on / (c.on + c.off)
		m.phase = c.phase or 0
	end
	return m
end

-- A wind column (the step) plus its fan, its post and, when capped, the hover frame where the feet stop.
local function column(parts: Parts, c: Column)
	local w, d = c.x1 - c.x0, c.z1 - c.z0
	local cx, cz = (c.x0 + c.x1) / 2, (c.z0 + c.z1) / 2
	table.insert(
		parts,
		Kit.prop({ w, c.top - c.bottom, d }, { cx, (c.bottom + c.top) / 2, cz }, "wind", {
			ghost = true,
			step = true,
			motion = liftMotion(c),
		})
	)
	if c.tunnel then
		local h = c.top - c.bottom
		table.insert(
			parts,
			Kit.prop({ 0.6, h - 1, d - 1 }, { c.x0 + 0.3, (c.bottom + c.top) / 2, cz }, "fan", {
				ghost = true,
			})
		)
	elseif c.solidFan then
		table.insert(parts, Kit.prop({ w, 1, d }, { cx, c.bottom - 0.5, cz }, "fan"))
	else
		table.insert(parts, Kit.prop({ w - 1, 0.6, d - 1 }, { cx, c.bottom - 0.3, cz }, "fan", { ghost = true }))
		if c.post then
			table.insert(
				parts,
				Kit.prop({ 1, POST_DEPTH, 1 }, { cx, c.bottom - 0.6 - POST_DEPTH / 2, cz }, "post", { ghost = true })
			)
		end
	end
	if c.hover then
		-- A bright frame round the column where your feet hover.
		local y = c.hover - ROOT
		local t = 0.3
		table.insert(parts, Kit.prop({ w, 0.2, t }, { cx, y, c.z0 + t / 2 }, "glow", { ghost = true, tone = 1 }))
		table.insert(parts, Kit.prop({ w, 0.2, t }, { cx, y, c.z1 - t / 2 }, "glow", { ghost = true, tone = 1 }))
		table.insert(
			parts,
			Kit.prop({ t, 0.2, d - 2 * t }, { c.x0 + t / 2, y, cz }, "glow", { ghost = true, tone = 1 })
		)
		table.insert(
			parts,
			Kit.prop({ t, 0.2, d - 2 * t }, { c.x1 - t / 2, y, cz }, "glow", { ghost = true, tone = 1 })
		)
	end
end

-- A forward gust over the same box as a tunnel column (same timing).
local function gust(parts: Parts, c: Column, power: number)
	local m: Kit.Motion = { kind = "gust", axis = "x", power = power }
	if c.on and c.off then
		m.period = c.on + c.off
		m.duty = c.on / (c.on + c.off)
		m.phase = c.phase or 0
	end
	table.insert(
		parts,
		Kit.prop(
			{ c.x1 - c.x0, c.top - c.bottom, c.z1 - c.z0 },
			{ (c.x0 + c.x1) / 2, (c.bottom + c.top) / 2, (c.z0 + c.z1) / 2 },
			"wind",
			{ ghost = true, motion = m }
		)
	)
end

-- The entry pad (x 0..PAD, top 0, the whole lane).
local function entry(parts: Parts)
	table.insert(parts, Kit.slab(PAD / 2, 0, 0, PAD, Kit.WIDTH, "jelly", { tone = 1 }))
end

-- The kerb on the pad's end in front of a first column spanning z0..z1 (a body wider each side).
local function kerb(parts: Parts, z0: number, z1: number)
	local a, b = math.max(z0 - 1, -Kit.HALF), math.min(z1 + 1, Kit.HALF)
	table.insert(parts, Kit.wall(PAD - 0.5, (a + b) / 2, b - a, KERB, false, { tone = 2 }))
end

-- A ledge (a step) from x0 to x1 and z0 to z1 with its top at `top`.
local function ledge(parts: Parts, x0: number, x1: number, z0: number, z1: number, top: number, tone: number?)
	table.insert(parts, Kit.slab((x0 + x1) / 2, top, (z0 + z1) / 2, x1 - x0, z1 - z0, "jelly", { tone = tone or 3 }))
end

-- First Breeze and Blink Column: the ledge runs on the far half of the lane up to here, then the whole lane.
local SIDE_TO = 28
-- First Breeze's goo bar on the ledge, as wide as the lane (seconds a turn).
local BREEZE_SPIN = 3.5
-- Blink Column's spinning bar (seconds a turn).
local BLINK_SPIN = 2.5
-- Drifting Column's column comes on 0.6 s before the drifting ledge is back in front of it (at t = 4.4 of 5 s).
local DRIFT_PHASE = 1 - 4.4 / 5
-- Moving Exit's column comes on at t = 3.6 of the 6 s lift cycle, as the moving ledge sinks to its low point.
local EXIT_PHASE = 1 - 3.6 / 6
-- Goo Ring Climb's shelves stick `deep` into the column and slide in and out by `amp` every `period` s, each one
-- `lag` of a cycle after the one below.
local RING = { deep = 6, amp = 2, period = 2, lag = 0.25 }
-- Spinner Shaft's propeller (seconds a turn).
local SPINNER = 3
-- Hover Shelf's goo bar sinks into the shelf's front: up `hold` s, down `hold` s, 0.4 s moving each way (about 1.9 s
-- under your feet).
local HOVER_DOOR = { hold = 1.6, period = 4 }

-- The usual opening: pad, kerb, and a first column floating HOP over the pad right after it.
local function opening(parts: Parts, c: Column)
	entry(parts)
	kerb(parts, c.z0, c.z1)
	c.bottom = HOP
	c.post = true
	column(parts, c)
end

local M = {}
M.id = "Updraft"
M.name = "Updraft"
M.idea = 5

M.variants = {
	{
		-- One tall column: hop in, float up, drift across onto the high ledge on the other half of the lane, then
		-- slip past a goo bar as wide as the lane spinning round on it.
		name = "First Breeze",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 45, 12
			local parts: Parts = {}
			opening(parts, { x0 = PAD, x1 = PAD + 8, z0 = -10, z1 = -2, bottom = HOP, top = rise + 4 })
			-- The ledge starts on the other half of the lane: steer across as you rise (straight on misses it).
			ledge(parts, PAD + 9, SIDE_TO, 0, Kit.HALF, rise)
			ledge(parts, SIDE_TO, length, -Kit.HALF, Kit.HALF, rise)
			table.insert(
				parts,
				Kit.hazard({ 22, 2, 1.5 }, { 32.5, rise + 1, 0 }, { motion = { kind = "spin", period = BREEZE_SPIN } })
			)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A slow, wide column off to one side: you rise gently and steer across to the ledge on the other side. It
		-- cuts out for a moment, so hop in just after it comes back.
		name = "Lazy Lift",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 40, 14
			local parts: Parts = {}
			opening(parts, {
				x0 = PAD,
				x1 = PAD + 12,
				z0 = -Kit.HALF,
				z1 = 0,
				bottom = HOP,
				top = rise + 5,
				power = 14,
				on = 2.6,
				off = 1.4,
			})
			ledge(parts, PAD + 13, length, 2, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The column holds you hovering 2 over the ledge's height; the ledge is on the other half of the lane and a
		-- goo bar stands on its front edge, sinking into it for a moment: wait in the hover, step across while it
		-- is down.
		name = "Hover Shelf",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 38, 10
			local parts: Parts = {}
			local x1 = PAD + 8
			opening(parts, {
				x0 = PAD,
				x1 = x1,
				z0 = -10,
				z1 = -2,
				bottom = HOP,
				top = rise + 7,
				hover = rise + 2 + ROOT,
			})
			-- The shelf is on the other half of the lane: drift across in the hover, step on while the bar on its front sinks into it.
			ledge(parts, x1 + 2, length, 0, Kit.HALF, rise)
			table.insert(
				parts,
				Kit.hazard({ 1.5, 6, 14 }, { x1 + 3.5, rise + 3, 5 }, {
					motion = {
						kind = "path",
						points = { { 0, 0, 0 }, { 0, -8, 0 } },
						hold = HOVER_DOOR.hold,
						period = HOVER_DOOR.period,
					},
				})
			)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Walk off the pad and drop into a column below: the wind brakes your fall and carries you up, and you step
		-- sideways onto the ledge beside it. It cuts out for a moment: jump in while it runs, or drop into the void.
		name = "Catch the Fall",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 52
			local parts: Parts = {}
			entry(parts)
			local x0 = PAD + 4
			column(parts, {
				x0 = x0,
				x1 = x0 + 10,
				z0 = -9,
				z1 = 1,
				bottom = -13,
				top = 1,
				on = 2.1,
				off = 1.6,
				post = true,
			})
			-- The ledge starts beside the column's far half: 10 past the pad, out of a jump's reach.
			ledge(parts, x0 + 6, 44, 3, Kit.HALF, -2, 2)
			ledge(parts, 46, length, -Kit.HALF, Kit.HALF, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Over a safe floor: hop into column A, which holds you hovering, then step sideways into column B when it
		-- comes on and ride it 12 higher to the ledge. B is too high to jump into from the floor.
		name = "Hand-Off",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 42, 22
			local parts: Parts = {}
			local floorTo = 32
			table.insert(parts, Kit.slab(floorTo / 2, 0, 0, floorTo, Kit.WIDTH, "jelly", { tone = 1 }))
			local x0, x1 = 12, 20
			table.insert(parts, Kit.wall(x0 - 0.5, -7.5, 9, KERB, false, { tone = 2 }))
			column(parts, { x0 = x0, x1 = x1, z0 = -Kit.HALF, z1 = -4, bottom = HOP, top = 15, hover = 13.5 })
			column(parts, { x0 = x0, x1 = x1, z0 = -3, z1 = 5, bottom = 11.5, top = rise + 4, on = 2.1, off = 1.6 })
			ledge(parts, x1 + 1, length, -3, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A wind tunnel along the course over a 12-stud gap: hop in, it holds you up and blows you forward; steer
		-- round the goo block sliding from side to side in the middle, and out of its side onto the far ledge on
		-- the other half of the lane.
		name = "First Crosswind",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 40
			local parts: Parts = {}
			local tunnel: Column = {
				x0 = PAD,
				x1 = PAD + 14,
				z0 = -10,
				z1 = -2,
				bottom = HOP,
				top = HOP + 6.5,
				hover = HOP + 3,
				tunnel = true,
			}
			entry(parts)
			kerb(parts, tunnel.z0, tunnel.z1)
			column(parts, tunnel)
			gust(parts, tunnel, GUST)
			-- The far ledge is on the other half of the lane: steer out of the tunnel's side over it.
			ledge(parts, PAD + 12, length, 0, Kit.HALF, 0)
			table.insert(
				parts,
				Kit.hazard({ 2, 6.5, 4 }, { PAD + 6, HOP + 3.25, -6 }, {
					motion = { kind = "slide", axis = "z", amp = 3, period = 2.5 },
				})
			)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The column switches off on a timer; the swirl fades first. A slower ride: start it just as it comes on. Up
		-- top (across on the other half of the lane) a goo bar as wide as the lane spins round: slip past it between
		-- two sweeps.
		name = "Blink Column",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 46, 14
			local parts: Parts = {}
			opening(parts, {
				x0 = PAD,
				x1 = PAD + 8,
				z0 = -10,
				z1 = -2,
				bottom = HOP,
				top = rise + 4,
				power = 20,
				on = 1.85,
				off = 1.5,
			})
			ledge(parts, PAD + 9, SIDE_TO, 0, Kit.HALF, rise)
			ledge(parts, SIDE_TO, length, -Kit.HALF, Kit.HALF, rise)
			table.insert(
				parts,
				Kit.hazard({ 22, 2, 1.5 }, { 32, rise + 1, 0 }, { motion = { kind = "spin", period = BLINK_SPIN } })
			)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Two columns side by side take turns: hover in A, and while both run (1.2 s) step sideways into B before A
		-- fades (about a second). B starts too high to jump into from the pad, a stud past A's side.
		name = "Relay Fans",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 36, 20
			local parts: Parts = {}
			opening(parts, {
				x0 = PAD,
				x1 = PAD + 8,
				z0 = -10,
				z1 = -2,
				bottom = HOP,
				top = 14.5,
				hover = 13,
				on = 3.05,
				off = 0.95,
			})
			-- B starts a stud past A's side: no straight line runs through both.
			column(parts, {
				x0 = PAD,
				x1 = PAD + 8,
				z0 = -1,
				z1 = 7,
				bottom = 11.5,
				top = rise + 4,
				on = 3.05,
				off = 0.95,
				phase = 0.5,
			})
			ledge(parts, PAD + 9, length, -4, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Hover at the top while a ledge drifts back and forth across the lane, pausing at each end: step onto it
		-- when it lines up with you, ride it across to the far ledge. The column only runs while the ledge comes
		-- by (same 5 s beat), so hop in as it comes on; hover too long and it drops you. The far ledge only meets
		-- the drifting one at the end of its trip: ride it all the way.
		name = "Drifting Column",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 46, 12
			local parts: Parts = {}
			opening(parts, {
				x0 = PAD,
				x1 = PAD + 8,
				z0 = -10,
				z1 = -2,
				bottom = HOP,
				top = rise + 7,
				hover = rise + 2 + ROOT,
				on = 1.8,
				off = 3.2,
				phase = DRIFT_PHASE,
			})
			table.insert(
				parts,
				Kit.slab(PAD + 14.5, rise, -6, 10, 8, "jelly", {
					tone = 2,
					motion = { kind = "path", points = { { 0, 0, 0 }, { 0, 0, 12 } }, hold = 1, period = 5 },
					marker = "rail",
				})
			)
			ledge(parts, 31, length, 4, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The exit ledge is a lift going up and down beside the column. The column only runs while the ledge is low
		-- (same 6 s beat): hop in as it comes on, step off onto the ledge, ride it up and jump to the far ledge
		-- near the top of its trip.
		name = "Moving Exit",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 44, 16
			local parts: Parts = {}
			opening(parts, {
				x0 = PAD,
				x1 = PAD + 8,
				z0 = -4,
				z1 = 4,
				bottom = HOP,
				top = 15,
				hover = 13.5,
				on = 1.6,
				off = 4.4,
				phase = EXIT_PHASE,
			})
			table.insert(
				parts,
				Kit.slab(PAD + 14.5, 9, 0, 10, Kit.WIDTH, "jelly", {
					tone = 2,
					motion = { kind = "slide", axis = "y", amp = 4, period = 6 },
					marker = "arrows",
				})
			)
			ledge(parts, 31, length, -Kit.HALF, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A wide, slow column with red goo shelves sticking in from three sides, one above the other, each sliding in
		-- and out: spiral round them as you rise, and hop in when the gaps line up.
		name = "Goo Ring Climb",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 40, 18
			local parts: Parts = {}
			local x0, x1 = PAD, PAD + 12
			opening(parts, { x0 = x0, x1 = x1, z0 = -6, z1 = 6, bottom = HOP, top = rise + 5, power = 12 })
			ledge(parts, x1 + 1, length, -Kit.HALF, Kit.HALF, rise)
			local r = RING
			local deep = r.deep
			local function pulse(axis: string, phase: number): Kit.Motion
				return { kind = "slide", axis = axis, amp = r.amp, period = r.period, phase = phase }
			end
			table.insert(
				parts,
				Kit.hazard({ 12, 1, deep }, { (x0 + x1) / 2, 7.5, -6 + deep / 2 }, { motion = pulse("z", 0) })
			)
			table.insert(parts, Kit.hazard({ deep, 1, 12 }, { x1 - deep / 2, 13.5, 0 }, { motion = pulse("x", r.lag) }))
			table.insert(
				parts,
				Kit.hazard({ 12, 1, deep }, { (x0 + x1) / 2, 19.5, 6 - deep / 2 }, { motion = pulse("z", 2 * r.lag) })
			)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Ride up and across onto a shelf on the other half of the lane, hop into a wind tunnel that holds you up and
		-- blows you over a 16-stud gap. It blinks: go as it comes on.
		name = "Crosswind Shelf",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 56, 10
			local parts: Parts = {}
			-- The shelf is on the other half of the lane from the column: steer across as you rise.
			opening(parts, { x0 = PAD, x1 = PAD + 8, z0 = -10, z1 = -2, bottom = HOP, top = rise + 5 })
			ledge(parts, PAD + 9, PAD + 17, 0, Kit.HALF, rise, 2)
			local tunnel: Column = {
				x0 = PAD + 16,
				x1 = PAD + 34,
				z0 = 0,
				z1 = 12,
				bottom = rise + HOP,
				top = rise + 10,
				hover = rise + 6,
				tunnel = true,
				on = 1.85,
				off = 1.5,
			}
			column(parts, tunnel)
			gust(parts, tunnel, GUST)
			ledge(parts, PAD + 33, length, -Kit.HALF, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Three columns climb a tower, each ledge on the other side from the last: you turn round in the air every
		-- ride. The upper two blink out of step.
		name = "Zigzag Tower",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 62
			local parts: Parts = {}
			opening(parts, { x0 = PAD, x1 = PAD + 8, z0 = -5, z1 = 3, bottom = HOP, top = 14 })
			ledge(parts, PAD, 27, 4, Kit.HALF, 10, 2)
			column(
				parts,
				{ x0 = 28, x1 = 36, z0 = -2, z1 = 6, bottom = 13.5, top = 24, on = 1.45, off = 1.2, post = true }
			)
			ledge(parts, 28, 46, -Kit.HALF, -3, 20, 3)
			column(parts, {
				x0 = 47,
				x1 = 55,
				z0 = -6,
				z1 = 2,
				bottom = 23.5,
				top = 34,
				on = 1.45,
				off = 1.2,
				phase = 0.5,
				post = true,
			})
			ledge(parts, 47, length, 3, Kit.HALF, 30, 1)
			return Kit.section(length, 30, parts)
		end,
	},
	{
		-- A red goo propeller (a cross of two paddles) spins through the middle of a slow column: hop in so you pass
		-- its height between two blades, and steer across to the ledge on the other side of the lane. (Tightened
		-- from the draft's single bar, which a rider can always dodge.)
		name = "Spinner Shaft",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, rise = 40, 16
			local parts: Parts = {}
			local x0, x1 = PAD, PAD + 12
			-- The ledge is on the other side of the lane from the column: steer across as you rise.
			opening(parts, { x0 = x0, x1 = x1, z0 = -10, z1 = 2, bottom = HOP, top = rise + 4.5, power = 14 })
			ledge(parts, x1 + 1, length, 4, Kit.HALF, rise)
			for _, yaw in { 0, 90 } do
				table.insert(
					parts,
					Kit.hazard({ 16, 1, 3.5 }, { (x0 + x1) / 2, 13.5, -4 }, {
						yaw = yaw,
						motion = { kind = "spin", period = SPINNER },
					})
				)
			end
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A slow blinking column with goo shelves inside: weave round them and reach the top before the wind cuts out.
		name = "Storm Shaft",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, rise = 40, 20
			local parts: Parts = {}
			local x0, x1 = PAD, PAD + 12
			opening(parts, {
				x0 = x0,
				x1 = x1,
				z0 = -6,
				z1 = 6,
				bottom = HOP,
				top = rise + 5,
				power = 14,
				on = 2.33,
				off = 1.5,
			})
			ledge(parts, x1 + 1, length, -Kit.HALF, Kit.HALF, rise)
			local deep = 4.5
			table.insert(parts, Kit.hazard({ 12, 1, deep }, { (x0 + x1) / 2, 8.5, 6 - deep / 2 }))
			table.insert(parts, Kit.hazard({ deep, 1, 12 }, { x0 + deep / 2, 14.5, 0 }))
			table.insert(parts, Kit.hazard({ 12, 1, deep }, { (x0 + x1) / 2, 20.5, -6 + deep / 2 }))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- No ledges between the columns: walk out of each hover and drop across a 4-stud gap into the next, each one
		-- 8 higher. They blink one after the other, so keep moving.
		name = "Sky Hop",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, rise = 68, 30
			local parts: Parts = {}
			local on, off = 1.8, 2.2
			opening(parts, {
				x0 = PAD,
				x1 = PAD + 8,
				z0 = -4,
				z1 = 4,
				bottom = HOP,
				top = 12,
				hover = 10,
				on = on,
				off = off,
			})
			for i = 1, 3 do
				local x0 = PAD + i * 12
				column(parts, {
					x0 = x0,
					x1 = x0 + 8,
					z0 = -4,
					z1 = 4,
					bottom = 2 + (i - 1) * 8,
					top = 20 + (i - 1) * 8,
					hover = 18 + (i - 1) * 8,
					on = on,
					off = off,
					phase = (1 - i * 0.25) % 1,
					post = true,
				})
			end
			ledge(parts, PAD + 45, length, -Kit.HALF, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Ride up, then across into a forward wind tunnel on the other half of the lane, over a 24-stud gap, that
		-- blinks on and off: bob at the column's top, go as it comes on, or it cuts out mid-gap and you drop.
		-- Halfway across a goo block slides from side to side.
		name = "Gust Gap",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, rise = 56, 12
			local parts: Parts = {}
			-- The tunnel is on the other half of the lane from the column: steer across into it at the top.
			opening(parts, { x0 = PAD, x1 = PAD + 8, z0 = -12, z1 = -2, bottom = HOP, top = 16 })
			local tunnel: Column = {
				x0 = PAD + 8,
				x1 = PAD + 34,
				z0 = 0,
				z1 = 12,
				bottom = 13,
				top = 20,
				hover = 16.5,
				tunnel = true,
				on = 1.9,
				off = 1.6,
			}
			column(parts, tunnel)
			gust(parts, tunnel, GUST)
			table.insert(
				parts,
				Kit.hazard({ 2, 7, 4 }, { PAD + 22, 16.5, 6 }, {
					motion = { kind = "slide", axis = "z", amp = 3, period = 2 },
				})
			)
			ledge(parts, PAD + 32, length, -Kit.HALF, Kit.HALF, rise)
			return Kit.section(length, rise, parts)
		end,
	},
}

return M
