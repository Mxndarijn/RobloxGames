--!strict
--[[
	ObbySections.Kit (pure, contract/obby-sections.md §3, §4, §6)

	The section kit every obby idea module builds with: the part and motion types, the lane and jump numbers the
	checks use, small part builders (slab, prop, hazard, ramp, wall), and the motion clocks. No Roblox APIs, so the
	same file runs in Lune (tests/ObbyCheck) and in the game.

	Section-local coords: x forward from the section start, y up from the entry floor top, z to the right; the lane is
	z in [-WIDTH / 2, WIDTH / 2]. A part's `pos` is its centre. Rotation: `yaw`, `pitch`, `roll` (degrees) turn a part
	round its Y, X and Z axes in Roblox's YXZ order (CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)): a positive `roll`
	lifts the forward (+x) end, which is how `Kit.ramp` climbs; `pitch` banks it sideways; a positive `yaw` turns +x
	towards -z.

	Motion clocks (`Kit.offsetAt`, `Kit.punchAt`, `Kit.pathAt`, `Kit.sweepAt`, `Kit.patternAt`) are where a moving part
	is at a time. The checks measure fairness with them; ObbyFx can play the same curves so what is tested is what
	players see.
]]

local Rng = if script then require(script.Parent.Parent.Rng) else require("../Rng")

export type Vec = { number } -- { x, y, z }

-- One beat of a `pattern` motion: `at` seconds into the period, "slam" (full amp), "half" (`amount` of amp, 0.5 by
-- default) or "rest".
export type Beat = { at: number, kind: string, amount: number? }

-- Every motion field (contract §4). Which ones a kind reads is listed there and in ObbyCourse's header.
export type Motion = {
	kind: string,
	axis: string?,
	amp: number?,
	period: number?,
	phase: number?,
	delay: number?,
	away: number?,
	duty: number?,
	min: number?,
	power: number?,
	arm: number?,
	on: string?, -- melt: "land" (default) | "leave"
	spread: number?, -- melt: seconds until the `next` tiles start melting
	next: { number | string }?, -- melt: part indices in the section (ObbyCourse.build turns them into part ids)
	solid: boolean?, -- flip: only the glow blinks, the part stays solid
	throw: Vec?, -- bounce: course-local launch velocity on top of `power` up
	cap: number?, -- lift: hover this high above the part's bottom
	points: { Vec }?, -- path: offsets from the rest position, the first is { 0, 0, 0 }
	hold: number?, -- path / sweep: seconds held at each point / end
	loop: boolean?, -- path: go on from the last point back to the first (else ping-pong)
	once: boolean?, -- path: one trip on its `start` clock, then stay
	jump: boolean?, -- path with loop: the way back from the last point to the first is instant (drips)
	spinRoll: boolean?, -- path: a ball turns as it rolls
	depth: number?, -- sink
	speed: number?, -- sink / rise: studs per second
	stop: number?, -- rise: studs it rises at most
	at: number?, -- drop: seconds on its `start` clock it falls away
	beats: { Beat }?, -- pattern
}

export type Part = {
	size: Vec,
	pos: Vec,
	look: string,
	shape: string?, -- "block" (default) | "disc" | "ball" | "truss" | "log"
	ghost: boolean?,
	motion: Motion?,
	conveyor: Vec?,
	ice: boolean?,
	step: boolean?,
	tone: number?,
	link: boolean?,
	yaw: number?,
	pitch: number?,
	roll: number?,
	hazard: boolean?,
	route: string?,
	boost: { speed: number, carry: number? }?,
	slide: { pull: number, cap: number }?,
	sticky: { fall: number }?,
	vine: { reach: number }?,
	cannon: { power: number, arc: number }?,
	zone: { kind: string, gravity: number?, light: number? }?,
	key: string?,
	gate: { group: string, need: number }?,
	trigger: string?,
	start: string?,
	marker: string?,
	beat: number?,
	id: string?, -- set by ObbyCourse.build: "<section>.<index>", "s", "h", "f", "l<n>"
}

export type Section = { length: number, rise: number, parts: { Part } }

export type Variant = { name: string, tier: string, build: (seed: number) -> Section }
export type Generator = { tiers: { string }, build: (seed: number, tier: string) -> Section, examples: number? }

-- One idea module (ObbySections/<Id>.luau).
export type Idea = {
	id: string,
	name: string,
	idea: number,
	variants: { Variant },
	generator: Generator?,
}

local Kit = {}

Kit.WIDTH = 24 -- lane width across the course: z in [-12, 12]
Kit.HALF = Kit.WIDTH / 2
Kit.FLOOR_MIN = 8 -- studs across the way you cross it: the narrowest floor you run on
Kit.BEAM_MIN = 3 -- the narrowest beam (look "beam")
Kit.THICK = 1 -- platform thickness
Kit.WALL_HEIGHT = 9 -- a maze wall: taller than a jump (7.2) plus a head
Kit.BPM = 100 -- the beat clock of beat-snapped motions

-- A default character: JumpHeight 7.2, WalkSpeed 16. It jumps about 8.7 studs across and 7.2 up; these leave room.
Kit.GAP_MAX = 6
Kit.RISE_MAX = 3.5
Kit.GRAVITY = 196.2 -- workspace.Gravity
Kit.WALK = 16 -- WalkSpeed, studs / s
Kit.JUMP_HEIGHT = 7.2
Kit.JUMP_SPEED = math.sqrt(2 * Kit.GRAVITY * Kit.JUMP_HEIGHT)
Kit.HEAD = 5 -- feet to the top of the head
Kit.JUMP_LOSS = 0.15 -- seconds a runner loses on every jump (fairness runner)

-- A punch's beat as shares of its period: out, held, back, then resting (same as ObbyFx).
Kit.PUNCH_OUT = 0.1
Kit.PUNCH_HOLD = 0.35
Kit.PUNCH_BACK = 0.65

-- A pattern beat in seconds: shoot out, hold, slide back (a slam reads like a punch but keeps its own length when
-- the pattern's period changes).
Kit.SLAM_OUT = 0.15
Kit.SLAM_HOLD = 0.3
Kit.SLAM_BACK = 0.45

local TAU = 2 * math.pi

-- Seconds of `n` beats at Kit.BPM.
function Kit.beat(n: number): number
	return n * 60 / Kit.BPM
end

function Kit.rng(seed: number): Rng.Rng
	return Rng.new(seed)
end

-- A layout row of mixed values ({ kind, length, top, ... }); typed loosely on purpose.
function Kit.row(...: any): { any }
	return { ... }
end

local function merge(part: { [string]: any }, extra: { [string]: any }?): Part
	if extra then
		for k, v in extra do
			part[k] = v
		end
	end
	return part :: any
end

-- A walking-path platform whose top is at `top`, centred on (x, z), `sx` long and `sz` wide.
function Kit.slab(
	x: number,
	top: number,
	z: number,
	sx: number,
	sz: number,
	look: string,
	extra: { [string]: any }?
): Part
	return merge({
		size = { sx, Kit.THICK, sz },
		pos = { x, top - Kit.THICK / 2, z },
		look = look,
		step = true,
	}, extra)
end

-- Any other part (decor, obstacles, zones).
function Kit.prop(size: Vec, pos: Vec, look: string, extra: { [string]: any }?): Part
	return merge({ size = size, pos = pos, look = look }, extra)
end

-- Red see-through goo: touching it sends you back to the start pad. Not a floor, no collision.
function Kit.hazard(size: Vec, pos: Vec, extra: { [string]: any }?): Part
	local part = merge({ size = size, pos = pos, look = "hazard" }, extra)
	part.hazard = true
	part.look = "hazard"
	return part
end

-- A slab climbing (or falling) from top `top0` at x0 to `top1` at x1, `width` across, centred on z: a step.
function Kit.ramp(
	x0: number,
	top0: number,
	x1: number,
	top1: number,
	z: number,
	width: number,
	look: string,
	extra: { [string]: any }?
): Part
	local dx, dy = x1 - x0, top1 - top0
	local length = math.sqrt(dx * dx + dy * dy)
	local angle = math.atan2(dy, dx)
	-- The centre sits half a thickness under the top line's middle, along the tilted up axis.
	local half = Kit.THICK / 2
	local cx = (x0 + x1) / 2 + math.sin(angle) * half
	local cy = (top0 + top1) / 2 - math.cos(angle) * half
	return merge({
		size = { length, Kit.THICK, width },
		pos = { cx, cy, z },
		roll = math.deg(angle),
		look = look,
		step = true,
	}, extra)
end

-- A solid jelly maze wall centred on (x, z), `length` long along x (`alongX`) or along z, `height` tall (default
-- WALL_HEIGHT), 1 thick, standing on y = 0 (extra.pos overrides the whole position).
function Kit.wall(
	x: number,
	z: number,
	length: number,
	height: number?,
	alongX: boolean,
	extra: { [string]: any }?
): Part
	local h = height or Kit.WALL_HEIGHT
	local size = if alongX then { length, h, 1 } else { 1, h, length }
	return merge({ size = size, pos = { x, h / 2, z }, look = "jelly" }, extra)
end

-- Drop times for collapsing pieces at `points` (in order along the path): a runner at `speed` studs / s who starts at
-- the first point `headStart` seconds before the first piece goes reaches each piece just in time.
function Kit.collapseTimes(points: { Vec }, speed: number, headStart: number): { number }
	local out = {}
	local dist = 0
	for i, p in points do
		if i > 1 then
			local q = points[i - 1]
			local dx, dy, dz = p[1] - q[1], p[2] - q[2], p[3] - q[3]
			dist += math.sqrt(dx * dx + dy * dy + dz * dz)
		end
		out[i] = headStart + dist / speed
	end
	return out
end

-- How far (studs across) a launch straight up at `power` (plus `throw`) carries you to land `rise` studs higher, with
-- 20 % spare on the walk steering; nil when it can't get that high (1.5 studs to spare at the peak).
function Kit.launchReach(power: number, rise: number, throw: Vec?): number?
	local vy = power + (if throw then throw[2] else 0)
	local peak = vy * vy / (2 * Kit.GRAVITY)
	if vy <= 0 or rise > peak - 1.5 then
		return nil
	end
	local t = (vy + math.sqrt(vy * vy - 2 * Kit.GRAVITY * rise)) / Kit.GRAVITY
	local across = if throw then math.sqrt(throw[1] * throw[1] + throw[3] * throw[3]) else 0
	return (Kit.WALK * 0.8 + across) * t
end

---------------------------------------------------------------------------
-- Rotation and bounds
---------------------------------------------------------------------------

-- `v` turned by a part's yaw / pitch / roll (degrees, YXZ order: R = Ry * Rx * Rz).
function Kit.rotate(v: Vec, yaw: number?, pitch: number?, roll: number?): Vec
	local x, y, z = v[1], v[2], v[3]
	if roll and roll ~= 0 then
		local c, s = math.cos(math.rad(roll)), math.sin(math.rad(roll))
		x, y = x * c - y * s, x * s + y * c
	end
	if pitch and pitch ~= 0 then
		local c, s = math.cos(math.rad(pitch)), math.sin(math.rad(pitch))
		y, z = y * c - z * s, y * s + z * c
	end
	if yaw and yaw ~= 0 then
		local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
		x, z = x * c + z * s, -x * s + z * c
	end
	return { x, y, z }
end

-- The 8 corners of a part (rotated), moved by (dx, dy, dz) and turned a further `dyaw` degrees round its centre.
function Kit.corners(part: Part, dx: number?, dy: number?, dz: number?, dyaw: number?): { Vec }
	local hx, hy, hz = part.size[1] / 2, part.size[2] / 2, part.size[3] / 2
	local cx, cy, cz = part.pos[1] + (dx or 0), part.pos[2] + (dy or 0), part.pos[3] + (dz or 0)
	local yaw = (part.yaw or 0) + (dyaw or 0)
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local r = Kit.rotate({ sx * hx, sy * hy, sz * hz }, yaw, part.pitch, part.roll)
				table.insert(out, { cx + r[1], cy + r[2], cz + r[3] })
			end
		end
	end
	return out
end

-- Axis-aligned bounds of a part at rest (rotation included): minX, maxX, minY, maxY, minZ, maxZ.
function Kit.bounds(part: Part): (number, number, number, number, number, number)
	if not (part.yaw or part.pitch or part.roll) then
		local p, s = part.pos, part.size
		return p[1] - s[1] / 2, p[1] + s[1] / 2, p[2] - s[2] / 2, p[2] + s[2] / 2, p[3] - s[3] / 2, p[3] + s[3] / 2
	end
	local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, c in Kit.corners(part) do
		x0, x1 = math.min(x0, c[1]), math.max(x1, c[1])
		y0, y1 = math.min(y0, c[2]), math.max(y1, c[2])
		z0, z1 = math.min(z0, c[3]), math.max(z1, c[3])
	end
	return x0, x1, y0, y1, z0, z1
end

-- The top face's corners (rotated) at rest: the four corners of the part's own +Y face.
function Kit.topCorners(part: Part): { Vec }
	local hx, hy, hz = part.size[1] / 2, part.size[2] / 2, part.size[3] / 2
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local r = Kit.rotate({ sx * hx, hy, sz * hz }, part.yaw, part.pitch, part.roll)
			table.insert(out, { part.pos[1] + r[1], part.pos[2] + r[2], part.pos[3] + r[3] })
		end
	end
	return out
end

-- The top face's near (lowest x) and far (highest x) ends at rest: x and height of each, a ramp's start and end.
function Kit.endTops(part: Part): (number, number, number, number)
	local tops = Kit.topCorners(part)
	table.sort(tops, function(a, b)
		return a[1] < b[1]
	end)
	return (tops[1][2] + tops[2][2]) / 2, (tops[3][2] + tops[4][2]) / 2, tops[1][1], tops[4][1]
end

---------------------------------------------------------------------------
-- Motion clocks
---------------------------------------------------------------------------

-- A motion's period in seconds: `beat` beats at Kit.BPM when the part snaps to the beat, else motion.period.
function Kit.periodOf(part: Part): number
	local m = part.motion
	if part.beat then
		return Kit.beat(part.beat)
	end
	return if m and m.period and m.period ~= 0 then math.abs(m.period) else 1
end

-- How far out a punch is (0..1) at `cycle` (0..1).
function Kit.punchAt(cycle: number): number
	if cycle < Kit.PUNCH_OUT then
		return math.sin(cycle / Kit.PUNCH_OUT * math.pi / 2)
	elseif cycle < Kit.PUNCH_HOLD then
		return 1
	elseif cycle < Kit.PUNCH_BACK then
		return 1 - (cycle - Kit.PUNCH_HOLD) / (Kit.PUNCH_BACK - Kit.PUNCH_HOLD)
	end
	return 0
end

-- How far out a pattern motion is (0..1 of amp) `s` seconds into its period: the strongest beat acting then.
function Kit.patternAt(motion: Motion, s: number, period: number): number
	local best = 0
	local beats: { Beat } = motion.beats or {}
	for _, b in beats do
		local amount = if b.kind == "slam" then 1 elseif b.kind == "half" then (b.amount or 0.5) else 0
		if amount > 0 then
			local into = (s - b.at) % period
			local out
			if into < Kit.SLAM_OUT then
				out = math.sin(into / Kit.SLAM_OUT * math.pi / 2)
			elseif into < Kit.SLAM_OUT + Kit.SLAM_HOLD then
				out = 1
			elseif into < Kit.SLAM_OUT + Kit.SLAM_HOLD + Kit.SLAM_BACK then
				out = 1 - (into - Kit.SLAM_OUT - Kit.SLAM_HOLD) / Kit.SLAM_BACK
			else
				out = 0
			end
			best = math.max(best, out * amount)
		end
	end
	return best
end

-- The legs a path motion travels, as point index pairs: ping-pong (1..N..1), a loop (1..N, N -> 1) or once (1..N).
local function pathLegs(motion: Motion, n: number): { { number } }
	local legs = {}
	for i = 1, n - 1 do
		table.insert(legs, { i, i + 1 })
	end
	if motion.once then
		return legs
	elseif motion.loop then
		table.insert(legs, { n, 1 })
	else
		for i = n, 2, -1 do
			table.insert(legs, { i, i - 1 })
		end
	end
	return legs
end

-- Offset { x, y, z } of a path motion `s` seconds into its period (constant speed between points, `hold` seconds at
-- the start of every leg; a `jump` leg back to the first point takes no time).
function Kit.pathAt(motion: Motion, s: number, period: number): Vec
	local points = motion.points or { { 0, 0, 0 } }
	local n = #points
	if n < 2 then
		return { 0, 0, 0 }
	end
	local legs = pathLegs(motion, n)
	local hold = motion.hold or 0
	local lengths, total = {}, 0
	for i, leg in legs do
		local a, b = points[leg[1]], points[leg[2]]
		local instant = motion.loop and motion.jump and i == #legs
		local d = if instant then 0 else math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
		lengths[i] = d
		total += d
	end
	local moving = math.max(period - hold * #legs, 0.01)
	if motion.once and s >= period then
		return table.clone(points[n])
	end
	local left = s
	for i, leg in legs do
		local a, b = points[leg[1]], points[leg[2]]
		if left < hold then
			return table.clone(a)
		end
		left -= hold
		local span = if total > 0 then moving * lengths[i] / total else 0
		if left < span then
			local f = left / span
			return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
		end
		left -= span
	end
	return table.clone(points[legs[#legs][2]])
end

-- Turn (degrees) of a sweep motion `s` seconds into its period: centre -> +amp, hold, -> -amp, hold, -> centre.
function Kit.sweepAt(motion: Motion, s: number, period: number): number
	local amp, hold = motion.amp or 0, motion.hold or 0
	local move = math.max((period - 2 * hold) / 2, 0.01) -- seconds from one end to the other
	local quarter = move / 2
	if s < quarter then
		return amp * s / quarter
	end
	s -= quarter
	if s < hold then
		return amp
	end
	s -= hold
	if s < move then
		return amp - 2 * amp * s / move
	end
	s -= move
	if s < hold then
		return -amp
	end
	s -= hold
	return -amp + amp * math.min(s / quarter, 1)
end

--[[
	Where a part is at time `t` on its clock (server time, or seconds since its `start` group began; nil = not
	started, at rest). Returns the offset of its centre (dx, dy, dz), an extra turn round its vertical axis (dyaw,
	degrees), its footprint scale (shrink) and whether it is there / acting (`on`: flip solid, duty on, not dropped).
	Player-driven motions (melt, sink, bounce landings) sit at rest here.
]]
function Kit.offsetAt(part: Part, t: number?): (number, number, number, number, number, boolean)
	local m = part.motion
	if not m then
		return 0, 0, 0, 0, 1, true
	end
	local kind = m.kind
	if kind == "rise" then
		local up = if t then math.clamp((t - (m.delay or 0)) * (m.speed or 0), 0, m.stop or math.huge) else 0
		return 0, up, 0, 0, 1, true
	elseif kind == "drop" then
		return 0, 0, 0, 0, 1, t == nil or t < (m.at or 0)
	end
	local period = Kit.periodOf(part)
	local cycle = if t then (t / period + (m.phase or 0)) % 1 else 0
	local function along(d: number): (number, number, number)
		if m.axis == "x" then
			return d, 0, 0
		elseif m.axis == "z" then
			return 0, 0, d
		end
		return 0, d, 0
	end
	if kind == "slide" then
		local dx, dy, dz = along((m.amp or 0) * math.sin(TAU * cycle))
		return dx, dy, dz, 0, 1, true
	elseif kind == "punch" then
		local dx, dy, dz = along((m.amp or 0) * Kit.punchAt(cycle))
		return dx, dy, dz, 0, 1, true
	elseif kind == "pattern" then
		local dx, dy, dz = along((m.amp or 0) * Kit.patternAt(m, cycle * period, period))
		return dx, dy, dz, 0, 1, true
	elseif kind == "spin" then
		local sign = if (m.period or 1) < 0 then -1 else 1
		return 0, 0, 0, 360 * cycle * sign, 1, true
	elseif kind == "sweep" then
		return 0, 0, 0, Kit.sweepAt(m, cycle * period, period), 1, true
	elseif kind == "swing" then
		-- Across the course round a pivot `arm` above the rest position (as ObbyFx: CFrame.Angles(angle, 0, 0)).
		local angle = math.rad(m.amp or 0) * math.sin(TAU * cycle)
		local arm = m.arm or 0
		return 0, arm * (1 - math.cos(angle)), -arm * math.sin(angle), 0, 1, true
	elseif kind == "path" then
		local o = Kit.pathAt(m, if m.once and t then math.min(t, period) else cycle * period, period)
		return o[1], o[2], o[3], 0, 1, true
	elseif kind == "shrink" then
		local min = m.min or 1
		return 0, 0, 0, 0, min + (1 - min) * (1 + math.cos(TAU * cycle)) / 2, true
	elseif kind == "flip" then
		return 0, 0, 0, 0, 1, m.solid == true or cycle < (m.duty or 0.5)
	elseif kind == "bounce" or kind == "lift" or kind == "gust" or kind == "turn" then
		-- Timed (duty) pads, columns and gusts act only while the cycle is under duty; a belt (turn) runs both ways.
		if kind == "turn" or m.duty == nil then
			return 0, 0, 0, 0, 1, true
		end
		return 0, 0, 0, 0, 1, cycle < m.duty
	end
	return 0, 0, 0, 0, 1, true
end

-- A belt's surface velocity at time `t`: `conveyor`, reversed while a `turn` motion's cycle is past its duty.
function Kit.conveyorAt(part: Part, t: number?): Vec?
	local c = part.conveyor
	local m = part.motion
	if not c or not m or m.kind ~= "turn" then
		return c
	end
	local cycle = if t then (t / Kit.periodOf(part) + (m.phase or 0)) % 1 else 0
	if cycle < (m.duty or 0.5) then
		return c
	end
	return { -c[1], -c[2], -c[3] }
end

---------------------------------------------------------------------------
-- Section
---------------------------------------------------------------------------

local EPS = 0.05 -- studs of slack on the entry and exit rules

-- Builds a section and checks its ends: the first step starts at x in [0, 4] with its top at 0, the last step reaches
-- x = length with its top at `rise`.
function Kit.section(length: number, rise: number, parts: { Part }): Section
	local first, last
	for _, part in parts do
		if part.step then
			first = first or part
			last = part
		end
	end
	assert(first and last, "obby section without steps")
	local near, _, x0 = Kit.endTops(first)
	assert(x0 >= -EPS and x0 <= 4 + EPS, `obby section: first step starts at x {x0} (0..4)`)
	assert(math.abs(near) <= EPS, `obby section: first step top {near} (0)`)
	local _, far, _, x1 = Kit.endTops(last)
	assert(math.abs(x1 - length) <= EPS, `obby section: last step ends at x {x1}, length {length}`)
	assert(math.abs(far - rise) <= EPS, `obby section: last step top {far}, rise {rise}`)
	return { length = length, rise = rise, parts = parts }
end

return table.freeze(Kit)
