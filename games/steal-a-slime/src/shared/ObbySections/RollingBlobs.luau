--!strict
--[[
	Rolling Blobs (obby idea 14, docs/obby-variants/14.json; contract/obby-sections.md)

	Red see-through goo balls come out of a dark launcher at the top of a slope and roll (or hop) down at you: read
	each ball's line and size, step aside, weave, or run between two of them. Touching one sends you back to the start
	pad (balls are `hazard`s).

	How a ball moves: one `path` motion with `loop` + `jump` (ObbyFx and the checks share Kit.pathAt). It drops out of
	the launcher housing (LIFT studs over the floor, so you walk under it), rolls down its line on the floor
	(`spinRoll`), sinks into the drain pit at the bottom of its stretch, and goes back under the floor out of sight
	until it is its turn again; the way back to the mouth is instant. Every leg runs at one speed, so the idle time a
	ball needs between two shots (period minus the visible trip) is spent on that hidden way back.
	Several balls share a launcher with phases (`fire` = seconds into the period it leaves the mouth).

	Layout: an entry pad, then stretches. A stretch is a 4-stud drain pit (the jump in: a walker can't cross it, so
	holding forward never clears a variant) and a floor or ramp, with its launcher over the top end. Stretches are
	joined by rest pads that no ball reaches: the fairness runner (tests/ObbyCheck) can only wait where no hazard ever
	gets to, so pockets live between stretches rather than beside a ball's line.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part
type Vec = Kit.Vec

local ENTRY = 10 -- entry pad length
local PIT = 4 -- drain pit before every stretch: too long to walk over (ObbyCheck.walkStop)
local LIFT = 8 -- launcher housing bottom over the floor under it: well over a head, you walk under it
local SINK = 2.5 -- a drained ball's top this far under the floor top (out of reach under a 1-stud floor)
local HOUSE = 6 -- launcher housing length along the course (at least a ball + 1)

local function dist(a: Vec, b: Vec): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function lerp(a: Vec, b: Vec, f: number): Vec
	return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end

-- A path ball. `mouth` is its rest centre inside the launcher, `route` the centre points it rolls / hops through,
-- `drain` the centre point in the pit, `back` the hidden way back under the floor (ping-ponged if the idle time is
-- longer). It leaves the mouth `fire` seconds into every `period` at `speed` studs / s. `log` = a roller that long
-- across the course instead of a ball.
type BallSpec = {
	d: number,
	mouth: Vec,
	route: { Vec },
	drain: Vec,
	back: { Vec },
	speed: number,
	period: number,
	fire: number,
	log: number?,
}

local function ball(s: BallSpec): Part
	local pts: { Vec } = { s.mouth }
	for _, p in s.route do
		table.insert(pts, p)
	end
	table.insert(pts, s.drain)
	local seen = 0
	for i = 2, #pts do
		seen += dist(pts[i - 1], pts[i])
	end
	local need = s.period * s.speed - seen
	assert(need >= -1e-6, `rolling blob: a {s.period} s period is shorter than its {seen / s.speed} s trip`)
	local here = s.drain
	local i, dir, guard = 1, 1, 0
	while need > 1e-6 and guard < 64 do
		guard += 1
		local nxt = s.back[i]
		local d = dist(here, nxt)
		if d >= need then
			table.insert(pts, lerp(here, nxt, need / d))
			need = 0
		else
			if d > 1e-6 then
				table.insert(pts, nxt)
			end
			need -= d
			here = nxt
			i += dir
			if i > #s.back then
				i, dir = math.max(#s.back - 1, 1), -1
			elseif i < 1 then
				i, dir = math.min(2, #s.back), 1
			end
		end
	end
	local rel: { Vec } = {}
	for _, p in pts do
		table.insert(rel, { p[1] - s.mouth[1], p[2] - s.mouth[2], p[3] - s.mouth[3] })
	end
	local motion = {
		kind = "path",
		points = rel,
		period = s.period,
		phase = (-s.fire / s.period) % 1,
		loop = true,
		jump = true,
		spinRoll = true,
	}
	if s.log then
		-- A cylinder runs along its X: turned a quarter it lies across the course.
		return Kit.hazard({ s.log, s.d, s.d }, s.mouth, { shape = "log", yaw = 90, motion = motion })
	end
	return Kit.hazard({ s.d, s.d, s.d }, s.mouth, { shape = "ball", motion = motion })
end

---------------------------------------------------------------------------
-- Course pieces
---------------------------------------------------------------------------

type Stretch = {
	from: number, -- floor start (just past the pit)
	to: number, -- floor end
	top0: number,
	top1: number,
	pit: number, -- pit centre
	hl: number, -- launcher housing length
	mx: number, -- launcher mouth x
}

type Course = { parts: { Part }, x: number, top: number }

local function newCourse(): Course
	local c: Course = { parts = {}, x = ENTRY, top = 0 }
	table.insert(c.parts, Kit.slab(ENTRY / 2, 0, 0, ENTRY, Kit.WIDTH, "jelly", { tone = 1 }))
	return c
end

local function surface(st: Stretch, x: number): number
	return st.top0 + (x - st.from) / (st.to - st.from) * (st.top1 - st.top0)
end

-- A drain pit, then a floor `len` long climbing `rise`, `wide` across centred on `zc`; its launcher housing (for balls
-- up to `d`) sits over the top end. `up` lifts the floor over the pad before the pit (a jump up).
local function stretch(
	c: Course,
	len: number,
	rise: number,
	wide: number,
	zc: number,
	d: number,
	tone: number,
	houseWide: number?,
	houseZ: number?,
	up: number?
): Stretch
	local from = c.x + PIT
	local top0 = c.top + (up or 0)
	local st: Stretch = {
		from = from,
		to = from + len,
		top0 = top0,
		top1 = top0 + rise,
		pit = c.x + PIT / 2,
		hl = math.max(HOUSE, d + 1),
		mx = 0,
	}
	st.mx = st.to - st.hl / 2
	table.insert(c.parts, Kit.ramp(from, top0, st.to, st.top1, zc, wide, "goo", { tone = tone }))
	local h = d + 1.5
	table.insert(
		c.parts,
		Kit.prop({ st.hl, h, houseWide or wide }, { st.to - st.hl / 2, st.top1 + LIFT + h / 2, houseZ or zc }, "post")
	)
	c.x, c.top = st.to, st.top1
	return st
end

-- A flat pad from the course's end (a rest pad between stretches, or the exit).
local function pad(c: Course, len: number, tone: number)
	table.insert(c.parts, Kit.slab(c.x + len / 2, c.top, 0, len, Kit.WIDTH, "jelly", { tone = tone }))
	c.x += len
end

local function finish(c: Course): Kit.Section
	return Kit.section(c.x, c.top, c.parts)
end

type RollOpts = {
	d: number,
	z: number, -- line at the mouth
	zEnd: number?, -- line at the bottom (a slanted line), default z
	via: { Vec }?, -- extra { x, z } points between (zigzags); heights follow the floor
	speed: number,
	period: number,
	fire: number,
	hop: { number }?, -- { length, height }: hops instead of rolling
	log: number?,
}

-- A ball for stretch `st`: out of the mouth, down onto the top of the floor, down the floor to its start, into the
-- pit, back under the floor.
local function rollSpec(st: Stretch, o: RollOpts): BallSpec
	local r = o.d / 2
	local zEnd = o.zEnd or o.z
	local mouth = { st.mx, st.top1 + LIFT + 0.5 + r, o.z }
	-- The centre line on the floor: { x, z } corners, top first.
	local line: { Vec } = { { st.mx, 0, o.z } }
	for _, p in (o.via or {}) :: { Vec } do
		table.insert(line, { p[1], 0, p[2] })
	end
	table.insert(line, { st.from, 0, zEnd })
	local route: { Vec } = {}
	if o.hop then
		local hopLen, height = o.hop[1], o.hop[2]
		table.insert(route, { st.mx, surface(st, st.mx) + r, o.z })
		for k = 1, #line - 1 do
			local a, b = line[k], line[k + 1]
			local n = math.max(1, math.ceil(math.abs(a[1] - b[1]) / hopLen - 0.25))
			for j = 1, n do
				local mid = lerp(a, b, (j - 0.5) / n)
				local land = lerp(a, b, j / n)
				table.insert(route, { mid[1], surface(st, mid[1]) + r + height, mid[3] })
				table.insert(route, { land[1], surface(st, land[1]) + r, land[3] })
			end
		end
	else
		for _, p in line do
			table.insert(route, { p[1], surface(st, p[1]) + r, p[3] })
		end
	end
	local back: { Vec } = {}
	for k = #line, 1, -1 do
		local p = line[k]
		table.insert(back, { p[1], surface(st, p[1]) - r - SINK, p[3] })
	end
	return {
		d = o.d,
		mouth = mouth,
		route = route,
		drain = { st.pit, st.top0 - r - SINK, zEnd },
		back = back,
		speed = o.speed,
		period = o.period,
		fire = o.fire,
		log = o.log,
	}
end

local function roll(st: Stretch, o: RollOpts): Part
	return ball(rollSpec(st, o))
end

-- Seconds a ball is in sight: out of the mouth, down its line, into the drain.
local function tripOf(s: BallSpec): number
	local seen = dist(s.mouth, s.route[1]) + dist(s.route[#s.route], s.drain)
	for i = 2, #s.route do
		seen += dist(s.route[i - 1], s.route[i])
	end
	return seen / s.speed
end

-- How many times a firing order of `n` shots `gap` apart repeats in one period, so a ball's trip fits in it.
local function repsFor(trip: number, n: number, gap: number): number
	return math.max(1, math.ceil(trip / (n * gap) - 1e-9))
end

-- A lamp on the launcher's front face over line z: its glow is lit for `lead` seconds before each ball fired at
-- `fire` (every `period`), so you can read where the next one comes (flip with solid: glow only).
local function lamp(st: Stretch, z: number, period: number, fire: number, lead: number): Part
	return Kit.prop({ 0.4, 1.5, 3 }, { st.to - st.hl - 0.2, st.top1 + LIFT + 1, z }, "glow", {
		ghost = true,
		motion = {
			kind = "flip",
			solid = true,
			period = period,
			duty = lead / period,
			phase = (-(fire - lead) / period) % 1,
		},
	})
end

-- A thin painted strip on the floor between two { x, z } points (lane lines, grooves).
local function paint(st: Stretch, a: Vec, b: Vec, wide: number, look: string): Part
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local ha, hb = surface(st, a[1]), surface(st, b[1])
	local flat = math.sqrt(dx * dx + dz * dz)
	local len = math.sqrt(flat * flat + (hb - ha) ^ 2)
	return Kit.prop({ len, 0.2, wide }, { (a[1] + b[1]) / 2, (ha + hb) / 2 + 0.06, (a[2] + b[2]) / 2 }, look, {
		ghost = true,
		yaw = math.deg(math.atan2(-dz, dx)),
		roll = math.deg(math.atan2(hb - ha, flat)),
	})
end

---------------------------------------------------------------------------
-- Variants
---------------------------------------------------------------------------

local M = {}
M.id = "RollingBlobs"
M.name = "Rolling Blobs"
M.idea = 14

M.variants = {
	{
		-- Three painted lanes; the lamp over a lane glows just before its ball drops, so you move to another lane.
		-- The order (left, right, middle, right, left, middle) is not a simple loop, so watch the lamps.
		name = "Lane Watch",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 56, 6, Kit.WIDTH, 0, 6, 2)
			local d, gap, speed = 6, 0.9, 11
			local order = { -8, 8, 0, 8, -8, 0 }
			for _, z in { -4, 4 } do
				table.insert(c.parts, paint(st, { st.from, z }, { st.to, z }, 0.4, "glow"))
			end
			local cycle = gap * #order
			local reps =
				repsFor(tripOf(rollSpec(st, { d = d, z = 0, speed = speed, period = 1, fire = 0 })), #order, gap)
			for i = 1, #order * reps do
				local z = order[(i - 1) % #order + 1]
				table.insert(
					c.parts,
					roll(st, { d = d, z = z, speed = speed, period = cycle * reps, fire = (i - 1) * gap })
				)
			end
			for i, z in order do
				table.insert(c.parts, lamp(st, z, cycle, (i - 1) * gap, gap))
			end
			pad(c, 8, 3)
			return finish(c)
		end,
	},
	{
		-- Flat floor, rows of small (3-stud) pebbles: jump each row as it rolls under you, or thread the gaps. The
		-- rows come in three patterns, so the gaps keep moving.
		name = "Pebble Hop",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 50, 0, Kit.WIDTH, 0, 3, 1)
			local gap, speed = 1.0, 12
			local rows = { { -10.5, -4.5, 1.5, 7.5 }, { -7.5, -1.5, 4.5, 10.5 }, { -9, -3, 3, 9 } }
			local reps =
				repsFor(tripOf(rollSpec(st, { d = 3, z = 0, speed = speed, period = 1, fire = 0 })), #rows, gap)
			for i = 1, #rows * reps do
				for _, z in rows[(i - 1) % #rows + 1] do
					table.insert(
						c.parts,
						roll(st, { d = 3, z = z, speed = speed, period = gap * #rows * reps, fire = (i - 1) * gap })
					)
				end
			end
			pad(c, 8, 2)
			return finish(c)
		end,
	},
	{
		-- Narrow 8-wide bridges a 7-stud ball fills; wait on the wide pad (the pocket) while the ball rolls down and
		-- drains in front of you, then run the bridge before the next one. Three bridges, each on its own beat.
		name = "Wall Pockets",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local period, off, len, speed = 5.0, 1.7, 14, 10
			for k = 1, 3 do
				local st = stretch(c, len, 1.5, 8, 0, 7, k, 8)
				table.insert(c.parts, roll(st, { d = 7, z = 0, speed = speed, period = period, fire = (k - 1) * off }))
				pad(c, if k < 3 then 8 else 6, k)
			end
			return finish(c)
		end,
	},
	{
		-- Two halves split by a painted line, a ball filling each in turn: step across every time the ball in your
		-- half gets close.
		name = "Two Lanes Swap",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 56, 6, Kit.WIDTH, 0, 10, 3)
			local gap, speed = 1.7, 11
			table.insert(c.parts, paint(st, { st.from, 0 }, { st.to, 0 }, 0.4, "glow"))
			local reps = repsFor(tripOf(rollSpec(st, { d = 10, z = 6, speed = speed, period = 1, fire = 0 })), 2, gap)
			for i = 1, 2 * reps do
				local z = if i % 2 == 1 then -6 else 6
				table.insert(
					c.parts,
					roll(st, { d = 10, z = z, speed = speed, period = gap * 2 * reps, fire = (i - 1) * gap })
				)
			end
			pad(c, 8, 1)
			return finish(c)
		end,
	},
	{
		-- Huge slow balls rolling down slanted lines, from one side to the other: the open side swaps halfway, so
		-- you cross in front of or behind each giant.
		name = "Slow Giants",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local d, speed, gap, slant = 12, 7.5, 2.2, 5
			local st = stretch(c, 56, 6, Kit.WIDTH, 0, d, 1)
			local spec = rollSpec(st, { d = d, z = -slant, zEnd = slant, speed = speed, period = 1, fire = 0 })
			local reps = repsFor(tripOf(spec), 2, gap)
			-- The two slanted lines painted on the ramp (an X): read where each giant is heading.
			for s = -1, 1, 2 do
				table.insert(c.parts, paint(st, { st.mx, -s * slant }, { st.from, s * slant }, 1.2, "post"))
			end
			for i = 1, 2 * reps do
				local s = if i % 2 == 1 then 1 else -1
				table.insert(
					c.parts,
					roll(st, {
						d = d,
						z = -s * slant,
						zEnd = s * slant,
						speed = speed,
						period = gap * 2 * reps,
						fire = (i - 1) * gap,
					})
				)
			end
			pad(c, 8, 2)
			return finish(c)
		end,
	},
	{
		-- A 16-wide ramp; the launcher fires three balls across it close together, then rests. Weave through the
		-- burst or time your climb into the quiet gap.
		name = "Burst and Lull",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 56, 6, 16, 0, 6, 2)
			local cycle, step, speed = 4.6, 1.0, 11
			local bursts = { { -4, 4, 0 }, { 4, 0, -4 } }
			for b, burst in bursts do
				for i, z in burst do
					local fire = (b - 1) * cycle + (i - 1) * step
					table.insert(
						c.parts,
						roll(st, { d = 6, z = z, speed = speed, period = cycle * #bursts, fire = fire })
					)
				end
			end
			pad(c, 8, 3)
			return finish(c)
		end,
	},
	{
		-- Balls hop down in big arcs on three lines: run under one while it is high, never where it lands.
		name = "Bouncers",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 56, 0, Kit.WIDTH, 0, 6, 1)
			local gap, speed = 2.4, 14
			local hop = { 16, 8 }
			local spec = rollSpec(st, { d = 6, z = 0, speed = speed, period = 1, fire = 0, hop = hop })
			local reps = repsFor(tripOf(spec), 1, gap)
			for line, z in { -8, 0, 8 } do
				for k = 0, reps - 1 do
					table.insert(
						c.parts,
						roll(st, {
							d = 6,
							z = z,
							speed = speed,
							period = gap * reps,
							fire = k * gap + (line - 1) * gap / 3,
							hop = hop,
						})
					)
				end
			end
			pad(c, 8, 2)
			return finish(c)
		end,
	},
	{
		-- The floor folds into four legs across the course (walls with a door at alternate ends); the balls follow
		-- the folds the other way, so one you dodged on a leg turns the corner and meets you again on the next.
		-- (The draft's two 40-stud legs back along the course turned across it: a section only runs forward.)
		name = "Switchback",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local d, r, speed, gap = 5, 2.5, 11.5, 2.6
			local from = c.x + PIT
			local legs, depth = 4, 12
			local to = from + legs * depth + (legs - 1)
			table.insert(c.parts, Kit.slab((from + to) / 2, 0, 0, to - from, Kit.WIDTH, "goo", { tone = 2 }))
			local centres = {}
			for k = 1, legs do
				centres[k] = from + (k - 1) * (depth + 1) + depth / 2
			end
			for k = 1, legs - 1 do
				local wx = from + k * (depth + 1) - 0.5
				local zc = if k % 2 == 1 then -Kit.HALF / 2 else Kit.HALF / 2 -- odd walls leave the +z half open
				table.insert(c.parts, Kit.wall(wx, zc, Kit.HALF, nil, false, { tone = 3 }))
			end
			-- The launcher over the -z end of the last leg.
			local hl, h = HOUSE, d + 1.5
			table.insert(c.parts, Kit.prop({ hl, h, 6 }, { centres[4], LIFT + h / 2, -7 }, "post"))
			local line = {
				{ centres[4], -7 },
				{ centres[4], 6 },
				{ centres[3], 6 },
				{ centres[3], -6 },
				{ centres[2], -6 },
				{ centres[2], 6 },
				{ centres[1], 6 },
				{ from, 6 },
			}
			local route, back = {}, {}
			for _, q in line do
				table.insert(route, { q[1], r, q[2] })
			end
			for k = #line, 1, -1 do
				table.insert(back, { line[k][1], -r - SINK, line[k][2] })
			end
			local spec: BallSpec = {
				d = d,
				mouth = { centres[4], LIFT + 0.5 + r, -7 },
				route = route,
				drain = { c.x + PIT / 2, -r - SINK, 6 },
				back = back,
				speed = speed,
				period = 1,
				fire = 0,
			}
			local n = repsFor(tripOf(spec), 1, gap)
			for k = 1, n do
				local s = table.clone(spec)
				s.period, s.fire = n * gap, (k - 1) * gap
				table.insert(c.parts, ball(s))
			end
			c.x = to
			pad(c, 8, 1)
			return finish(c)
		end,
	},
	{
		-- One 14-wide lane: small balls (jump them) and big ones (step to the side they leave open) in a set order,
		-- S S B S B B. Read the size as it drops out of the launcher.
		name = "Big and Small",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 66, 8, 14, 0, 8, 3)
			local gap, speed = 1.8, 12
			local order = { { 3, 0 }, { 3, 0 }, { 8, 2.5 }, { 3, 0 }, { 8, -2.5 }, { 8, -2.5 } }
			local spec = rollSpec(st, { d = 3, z = 0, speed = speed, period = 1, fire = 0 })
			local reps = repsFor(tripOf(spec), #order, gap)
			for i = 1, #order * reps do
				local b = order[(i - 1) % #order + 1]
				table.insert(
					c.parts,
					roll(st, { d = b[1], z = b[2], speed = speed, period = gap * #order * reps, fire = (i - 1) * gap })
				)
			end
			pad(c, 8, 1)
			return finish(c)
		end,
	},
	{
		-- Four roads across the course, balls rolling over each from a launcher on the side (directions alternate);
		-- cross one road at a time and wait on the strips between.
		name = "Road Crossing",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts: { Part } = {}
			table.insert(parts, Kit.slab(ENTRY / 2, 0, 0, ENTRY, Kit.WIDTH, "jelly", { tone = 1 }))
			local d, r, speed, gap, shift = 5, 2.5, 12.5, 0.94, 0.7
			local x = ENTRY + PIT
			local road, strip = d + 2, 5
			local function stripAt(len: number, tone: number)
				table.insert(parts, Kit.slab(x + len / 2, 0, 0, len, Kit.WIDTH, "jelly", { tone = tone }))
				x += len
			end
			stripAt(4, 2)
			for row = 1, 4 do
				local s = if row % 2 == 1 then 1 else -1 -- +1: from the +z side to the -z side
				local xc = x + road / 2
				-- The road leaves a 6-stud gutter on the far side for the balls to drop into.
				table.insert(parts, Kit.slab(xc, 0, s * 3, road, Kit.WIDTH - 6, "goo", { tone = row % 2 + 1 }))
				local hh = d + 1.5
				table.insert(parts, Kit.prop({ road, hh, 6 }, { xc, LIFT + hh / 2, s * 9 }, "post"))
				local spec: BallSpec = {
					d = d,
					mouth = { xc, LIFT + 0.5 + r, s * 9 },
					route = { { xc, r, s * 9 }, { xc, r, -s * 9 } },
					drain = { xc, -r - SINK, -s * 9 },
					back = { { xc, -r - SINK, -s * 5 }, { xc, -r - SINK, s * 9 } },
					speed = speed,
					period = 1,
					fire = 0,
				}
				local n = 4
				for k = 0, n - 1 do
					local b = table.clone(spec)
					b.period, b.fire = n * gap, k * gap + (row - 1) * shift
					table.insert(parts, ball(b))
				end
				x += road
				stripAt(if row < 4 then strip else 8, row % 3 + 1)
			end
			return Kit.section(x, 0, parts)
		end,
	},
	{
		-- The ramp narrows from 24 to 10 near the launcher's two mouths: lots of room at the bottom, almost none at
		-- the top. Balls fan out from the mouths onto six lines.
		name = "Funnel",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local from = c.x + PIT
			local seg, rise = 17, 2
			local widths = { 24, 19, 15, 10 }
			for k, w in widths do
				local x0 = from + (k - 1) * seg
				table.insert(
					c.parts,
					Kit.ramp(x0, (k - 1) * rise, x0 + seg, k * rise, 0, w, "goo", { tone = (k - 1) % 2 + 1 })
				)
			end
			local st: Stretch = {
				from = from,
				to = from + #widths * seg,
				top0 = 0,
				top1 = #widths * rise,
				pit = c.x + PIT / 2,
				hl = HOUSE,
				mx = from + #widths * seg - HOUSE / 2,
			}
			local h = 7.5
			table.insert(c.parts, Kit.prop({ HOUSE, h, 10 }, { st.mx, st.top1 + LIFT + h / 2, 0 }, "post"))
			local narrow = from + (#widths - 1) * seg -- where the 10-wide piece starts: lines fan out below it
			local gap, speed = 1.5, 10.5
			local lines = { { -2.5, -8 }, { 2.5, 5 }, { -2.5, -2 }, { 2.5, 8 }, { -2.5, -5 }, { 2.5, 2 } }
			for i, l in lines do
				table.insert(
					c.parts,
					roll(st, {
						d = 5,
						z = l[1],
						zEnd = l[2],
						via = { { narrow, l[1] } },
						speed = speed,
						period = gap * #lines,
						fire = (i - 1) * gap,
					})
				)
			end
			c.x, c.top = st.to, st.top1
			pad(c, 8, 3)
			return finish(c)
		end,
	},
	{
		-- The launcher slides side to side over the top; each ball rolls down the line the launcher was on when it
		-- fired. Watch the launcher, not the balls.
		name = "Roaming Launcher",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local d, swing, period = 7, 8, 6
			local n, speed = 6, 12
			local st = stretch(c, 56, 6, Kit.WIDTH, 0, d, 2, 8)
			-- The housing stretch() made is the launcher: it slides across and back every period.
			local house = c.parts[#c.parts]
			house.motion = { kind = "slide", axis = "z", amp = swing, period = period }
			local gap = period / n
			for i = 0, n - 1 do
				-- Half a shot off the centre line: the lines land at +-4 and +-8, so a ball also sweeps each edge.
				local fire = (i + 0.5) * gap
				local z = swing * math.sin(2 * math.pi * fire / period)
				table.insert(c.parts, roll(st, { d = d, z = z, speed = speed, period = period, fire = fire }))
			end
			pad(c, 8, 1)
			return finish(c)
		end,
	},
	{
		-- A groove zigzags down the ramp from side to side every 18 studs and every ball follows it: the safe spot
		-- keeps moving, so follow the groove with your eyes.
		name = "Zigzag Grooves",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 66, 8, Kit.WIDTH, 0, 6, 1)
			local via, z = {}, 8
			local x = st.mx - 18
			while x > st.from + 6 do
				z = -z
				table.insert(via, { x, z })
				x -= 18
			end
			local zEnd = -z
			-- Two grooves, mirror images, crossing in the middle; their balls take turns.
			local gap, speed = 2.15, 10.5
			for side = 1, -1, -2 do
				local mine = {}
				for _, q in via do
					table.insert(mine, { q[1], q[2] * side })
				end
				local corners = { { st.mx, 8 * side } }
				for _, q in mine do
					table.insert(corners, q)
				end
				table.insert(corners, { st.from, zEnd * side })
				for k = 1, #corners - 1 do
					table.insert(c.parts, paint(st, corners[k], corners[k + 1], 1.2, "post"))
				end
				local o: RollOpts =
					{ d = 6, z = 8 * side, zEnd = zEnd * side, via = mine, speed = speed, period = 1, fire = 0 }
				local n = repsFor(tripOf(rollSpec(st, o)), 1, gap)
				for i = 1, n do
					o.period, o.fire = gap * n, (i - 1) * gap + (if side < 0 then gap / 2 else 0)
					table.insert(c.parts, roll(st, o))
				end
			end
			pad(c, 8, 2)
			return finish(c)
		end,
	},
	{
		-- Rows of three balls fill the width: two big, one small. Find the small one (its lane's lamp glows first)
		-- and jump it or squeeze past it; its lane changes every row.
		name = "Odd One Out",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 80, 10, Kit.WIDTH, 0, 8, 3)
			local gap, speed, lanes = 1.82, 14, { -8, 0, 8 }
			-- { lane of the small ball, where it sits in its lane }: it hugs one side, so the gap beside it is the
			-- way through (or jump it). Lane 1 and 3 never follow each other: the gap moves one lane a row.
			local order = { { 1, -2.5 }, { 2, 2.5 }, { 3, 2.5 }, { 2, -2.5 } }
			local cycle = gap * #order
			local spec = rollSpec(st, { d = 8, z = 0, speed = speed, period = 1, fire = 0 })
			local reps = repsFor(tripOf(spec), #order, gap)
			for row = 1, #order * reps do
				local o = order[(row - 1) % #order + 1]
				for lane, z in lanes do
					local small = lane == o[1]
					table.insert(
						c.parts,
						roll(st, {
							d = if small then 3 else 8,
							z = if small then z + o[2] else z,
							speed = speed,
							period = cycle * reps,
							fire = (row - 1) * gap,
						})
					)
				end
			end
			-- Lamps: lanes 1 and 3 come once a cycle, lane 2 every other row.
			table.insert(c.parts, lamp(st, lanes[1], cycle, 0, gap * 0.8))
			table.insert(c.parts, lamp(st, lanes[3], cycle, 2 * gap, gap * 0.8))
			table.insert(c.parts, lamp(st, lanes[2], 2 * gap, gap, gap * 0.8))
			pad(c, 8, 1)
			return finish(c)
		end,
	},
	{
		-- A roller as wide as the course thunders down each of three stretches; small balls fill the space between.
		-- Run a stretch between two rollers and catch your breath on the pad (the pocket) before the next.
		name = "Full Sweep",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local small = { { -7, 2, 7 }, { -2, 7, -7 }, { 7, -7, 2 } }
			local lp, sp, ls, off = 5.0, 4.5, 13, 2
			local ss, sgap, len = 10, 1.5, 20
			for k = 1, 3 do
				local st = stretch(c, len, 2, Kit.WIDTH, 0, 6, k)
				local base = (k - 1) * off
				table.insert(
					c.parts,
					roll(st, { d = 6, z = 0, speed = ls, period = lp, fire = base, log = Kit.WIDTH - 0.4 })
				)
				for i, z in small[k] do
					table.insert(
						c.parts,
						roll(st, { d = 3, z = z, speed = ss, period = sp, fire = base + sgap * (i - 1) + 0.8 })
					)
				end
				pad(c, if k < 3 then 8 else 6, k)
			end
			return finish(c)
		end,
	},
	{
		-- Six real steps up, 3 studs each; balls bounce down them one step a hop, on two lines. Each jump up has to
		-- fit between two landings.
		name = "Stair Bounce",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts: { Part } = {}
			table.insert(parts, Kit.slab(ENTRY / 2, 0, 0, ENTRY, Kit.WIDTH, "jelly", { tone = 1 }))
			local from, steps, long, up, wide = ENTRY + PIT, 6, 10, 3, 12
			for k = 1, steps do
				table.insert(
					parts,
					Kit.slab(from + (k - 0.5) * long, k * up, 0, long, wide, "goo", { tone = (k - 1) % 2 + 1 })
				)
			end
			local top, to = steps * up, from + steps * long
			local d, r, speed, gap = 5, 2.5, 15, 1.0
			local hl, h = HOUSE, d + 1.5
			table.insert(parts, Kit.prop({ hl, h, wide }, { to - hl / 2, top + LIFT + h / 2, 0 }, "post"))
			local mx = to - hl / 2
			local zs = { -3, 3 }
			local function build(z: number): BallSpec
				local route = { { mx, top + r, z } }
				for k = steps - 1, 1, -1 do
					table.insert(route, { from + k * long, (k + 1) * up + r + 3, z })
					table.insert(route, { from + (k - 0.5) * long, k * up + r, z })
				end
				local back = {}
				for k = 1, steps do
					table.insert(back, { from + (k - 0.5) * long, k * up - r - SINK, z })
				end
				return {
					d = d,
					mouth = { mx, top + LIFT + 0.5 + r, z },
					route = route,
					drain = { ENTRY + PIT / 2, -r - SINK, z },
					back = back,
					speed = speed,
					period = 1,
					fire = 0,
				}
			end
			local n = repsFor(tripOf(build(zs[1])), 2, gap) * 2
			for k = 1, n do
				local s = build(zs[(k - 1) % 2 + 1])
				s.period, s.fire = n * gap, (k - 1) * gap
				table.insert(parts, ball(s))
			end
			table.insert(parts, Kit.slab(to + 4, top, 0, 8, Kit.WIDTH, "jelly", { tone = 3 }))
			return Kit.section(to + 8, top, parts)
		end,
	},
	{
		-- A steep ramp, two launchers out of step, rollers and bouncers mixed on slanted lines: no rhythm to copy,
		-- read each ball as it comes.
		name = "Storm Ramp",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local c = newCourse()
			local st = stretch(c, 80, 20, Kit.WIDTH, 0, 7, 2, 8, -6)
			-- The second launcher, beside the first.
			local house = c.parts[#c.parts]
			table.insert(c.parts, Kit.prop(house.size, { house.pos[1], house.pos[2], 6 }, "post"))
			local speed, off = 13, 0.9
			local launchers = {
				{ z = -6, gap = 1.0, ends = { -6, -8.5, -1, -8, -3, -7 } },
				{ z = 6, gap = 1.75, ends = { 3, 8.5, 0, 6 } },
			}
			for _, l in launchers do
				local n = #l.ends
				local function opts(i: number): RollOpts
					return {
						d = 7,
						z = l.z,
						zEnd = l.ends[(i - 1) % n + 1],
						speed = speed,
						period = 1,
						fire = (i - 1) * l.gap + (if l.z > 0 then off else 0),
						hop = if i % 2 == 0 then { 14, 6 } else nil,
					}
				end
				local trip = 0
				for i = 1, n do
					trip = math.max(trip, tripOf(rollSpec(st, opts(i))))
				end
				local reps = repsFor(trip, n, l.gap)
				for i = 1, n * reps do
					local o = opts(i)
					o.period = l.gap * n * reps
					table.insert(c.parts, roll(st, o))
				end
			end
			pad(c, 8, 3)
			return finish(c)
		end,
	},
}

return M
