--!strict
--[[
	ObbyCheck: the checks every obby section variant must pass (contract/obby-sections.md §9, §10). Each check takes
	a built section (Kit.Section, section-local coords) and returns nil when it passes or a sentence saying what is
	wrong. tests/ObbySections.spec runs them all over every variant of every idea for seeds 1..20; idea-specific specs
	(tests/obby/<Id>.spec) can call them one by one.

	  budget        <= PARTS_MAX parts with markers, length LENGTH_MIN..LENGTH_MAX, every part (and its motion) in the lane
	  widths        steps >= BEAM_MIN, non-beam steps >= FLOOR_MIN across the way you cross them
	  fields        only the motion kinds and fields of the contract; start groups have triggers; gates have keys
	  makeable      every step of every route is reachable from an earlier one (walk / jump, launch, lift, climb,
	                sticky wall, vine, cannon, boost jump), moving parts at their closest of SAMPLES points a period
	  straightWalk  holding forward with no jumping never clears it, on any line across the lane, at any start time
	  fairness      the runner (16 studs / s, 0.15 s per jump, can wait only where no hazard ever reaches) finds every
	                stretch of hazards open for WINDOW[tier] s; floods and collapses leave SPARE s (timers)
	  fall          the fall height never resets a runner above a platform they could land on
	  challenge     no section is just walking: at least one hazard, motion or trigger

	The models are deliberately simple (a point walker, straight-line runner, boxes for every shape). Where they are
	too rough for an idea (rides that carry you under hazards, mazes), add an idea spec instead of loosening these.
]]

local Config = require("../src/shared/Config")
local Kit = require("../src/shared/ObbySections/Kit")
local ObbyCourse = require("../src/shared/ObbyCourse")

type Part = Kit.Part
type Section = Kit.Section

local ObbyCheck = {}

ObbyCheck.PARTS_MAX = 80
ObbyCheck.LENGTH_MIN = 30
ObbyCheck.LENGTH_MAX = 110
ObbyCheck.SEEDS = 20 -- seeds 1..SEEDS per variant
ObbyCheck.SAMPLES = 32 -- points a period a moving part is measured at
-- Seconds a hazard stretch must stay open for the runner, past the time it takes to cross it (contract §9).
ObbyCheck.WINDOW = table.freeze({ easy = 1.4, medium = 1.0, hard = 0.75 })
ObbyCheck.SPARE = 1 -- seconds a flood or a collapse leaves the runner
ObbyCheck.LATERAL = 8 -- studs / s the fairness runner can sidestep while it runs forward
ObbyCheck.BODY = 1 -- half a character's width (studs)
ObbyCheck.STICKY_PEAK = 45 * 45 / (2 * Kit.GRAVITY) -- a jump off a sticky wall: 45 up ...
ObbyCheck.STICKY_REACH = 30 * (2 * 45 / Kit.GRAVITY) * 0.8 -- ... and 30 away, back at the same height (20 % spare)
ObbyCheck.VINE_UP = 20 -- jumping off a vine adds this upward speed
ObbyCheck.CANNON_SLACK = 2 -- studs: the cannon hands you back to physics 2 studs above the landing

-- Parts each marker kind adds (mirror of visuals/shared/ObbyParts.MARKER_PARTS, which needs Roblox to load).
ObbyCheck.MARKER_PARTS = table.freeze({
	rings1 = 1,
	rings2 = 1,
	rings3 = 1,
	chevrons = 4,
	arrows = 3,
	handprints = 3,
	cracks = 3,
	star = 2,
	rail = 2,
	ghostStop = 2,
	sign = 1,
})

local KINDS = table.freeze({
	slide = true,
	spin = true,
	melt = true,
	flip = true,
	shrink = true,
	bounce = true,
	lift = true,
	swing = true,
	rock = true,
	roll = true,
	punch = true,
	gust = true,
	path = true,
	sink = true,
	rise = true,
	drop = true,
	sweep = true,
	turn = true,
	pattern = true,
})
ObbyCheck.KINDS = KINDS

local function set(list: { string }): { [string]: boolean }
	local out = {}
	for _, k in list do
		out[k] = true
	end
	return out
end

local PART_FIELDS = set({
	"size",
	"pos",
	"look",
	"shape",
	"ghost",
	"motion",
	"conveyor",
	"ice",
	"step",
	"tone",
	"link",
	"yaw",
	"pitch",
	"roll",
	"hazard",
	"route",
	"boost",
	"slide",
	"sticky",
	"vine",
	"cannon",
	"zone",
	"key",
	"gate",
	"trigger",
	"start",
	"marker",
	"beat",
	"id",
})
local MOTION_FIELDS = set({
	"kind",
	"axis",
	"amp",
	"period",
	"phase",
	"delay",
	"away",
	"duty",
	"min",
	"power",
	"arm",
	"on",
	"spread",
	"next",
	"solid",
	"throw",
	"cap",
	"points",
	"hold",
	"loop",
	"once",
	"jump",
	"spinRoll",
	"depth",
	"speed",
	"stop",
	"at",
	"beats",
})
local SUB_FIELDS: { [string]: { [string]: boolean } } = {
	boost = set({ "speed", "carry" }),
	slide = set({ "pull", "cap" }),
	sticky = set({ "fall" }),
	vine = set({ "reach" }),
	cannon = set({ "power", "arc" }),
	zone = set({ "kind", "gravity", "light" }),
	gate = set({ "group", "need" }),
}
local ZONE_KINDS = set({ "moon", "dark", "lift" })
local MARKERS = set({
	"rings1",
	"rings2",
	"rings3",
	"chevrons",
	"arrows",
	"handprints",
	"cracks",
	"star",
	"rail",
	"ghostStop",
})
local BEAT_KINDS = set({ "slam", "half", "rest" })

-- Motions that move a part through space (sampled over a period); the rest act in place.
local MOVING = set({ "slide", "path", "spin", "sweep", "swing", "shrink", "punch", "pattern" })
-- Motions whose state depends on the time at all (moving, or on / off, or a one-shot clock).
local TIMED =
	set({ "slide", "path", "spin", "sweep", "swing", "shrink", "punch", "pattern", "flip", "rise", "drop", "turn" })

---------------------------------------------------------------------------
-- Cases
---------------------------------------------------------------------------

export type Case = {
	idea: Kit.Idea,
	variant: number, -- index into idea.variants; 0 = the generator
	tier: string,
	name: string,
	build: (seed: number) -> Section,
}

-- Every variant of `idea`, and its generator once per tier it covers.
function ObbyCheck.cases(idea: Kit.Idea): { Case }
	local out: { Case } = {}
	for i, v in idea.variants do
		table.insert(
			out,
			{ idea = idea, variant = i, tier = v.tier, name = `{idea.id} #{i} {v.name}`, build = v.build }
		)
	end
	local gen = idea.generator
	if gen then
		for _, tier in gen.tiers do
			table.insert(out, {
				idea = idea,
				variant = 0,
				tier = tier,
				name = `{idea.id} generator {tier}`,
				build = function(seed: number): Section
					return gen.build(seed, tier)
				end,
			})
		end
	end
	return out
end

-- A canonical string of any value (sorted keys): same string = same data.
function ObbyCheck.encode(value: any): string
	local kind = type(value)
	if kind == "table" then
		local keys = {}
		for k in value do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local out = {}
		for _, k in keys do
			table.insert(out, `{tostring(k)}={ObbyCheck.encode(value[k])}`)
		end
		return "{" .. table.concat(out, ",") .. "}"
	elseif kind == "number" then
		return string.format("%.6g", value)
	end
	return tostring(value)
end

---------------------------------------------------------------------------
-- Geometry: bodies, footprints, gaps
---------------------------------------------------------------------------

type Pt = { number } -- { x, z }

-- A part prepared for the checks.
type Body = {
	part: Part,
	index: number,
	cx: number,
	cy: number,
	cz: number,
	hx: number,
	hy: number,
	hz: number,
	tilted: boolean, -- pitch or roll: footprint and heights from the rotated box
	kind: string?, -- motion kind
	moving: boolean,
	timed: boolean,
	period: number,
	solid: boolean, -- collides (not ghost, not a hazard)
	floor: boolean, -- you can stand on it
	x0: number, -- swept x range over its whole motion
	x1: number,
}

local function bodiesOf(section: Section): { Body }
	local out: { Body } = {}
	for i, part in section.parts do
		local m = part.motion
		local kind = m and m.kind
		local b: Body = {
			part = part,
			index = i,
			cx = part.pos[1],
			cy = part.pos[2],
			cz = part.pos[3],
			hx = part.size[1] / 2,
			hy = part.size[2] / 2,
			hz = part.size[3] / 2,
			tilted = (part.pitch or 0) ~= 0 or (part.roll or 0) ~= 0,
			kind = kind,
			moving = kind ~= nil and MOVING[kind] == true,
			timed = kind ~= nil and TIMED[kind] == true,
			period = Kit.periodOf(part),
			solid = not part.ghost and not part.hazard and part.zone == nil and part.key == nil,
			floor = false,
			x0 = 0,
			x1 = 0,
		}
		b.floor = b.solid and part.vine == nil and part.gate == nil
		local x0, x1 = Kit.bounds(part)
		if b.moving or kind == "rise" then
			for k = 0, ObbyCheck.SAMPLES - 1 do
				local dx, _, _, dyaw = Kit.offsetAt(part, k / ObbyCheck.SAMPLES * b.period)
				local r = if dyaw ~= 0 then math.sqrt(b.hx * b.hx + b.hz * b.hz) else 0
				x0 = math.min(x0, b.cx + dx - r, x0 + dx)
				x1 = math.max(x1, b.cx + dx + r, x1 + dx)
			end
		end
		b.x0, b.x1 = x0, x1
		table.insert(out, b)
	end
	return out
end

-- The clock a body reads at time `t`: nil (at rest) for a `start` part whose group has not started.
local function clockOf(b: Body, t: number, started: { [string]: number }?): number?
	local g = b.part.start
	if g == nil then
		return t
	end
	local s = started and started[g]
	return if s then t - s else nil
end

-- A body's footprint (4 corners, x / z) moved by (dx, dz), turned a further dyaw degrees, scaled.
local function footprint(b: Body, dx: number, dz: number, dyaw: number, scale: number): { Pt }
	if b.tilted then
		local x0, x1, _, _, z0, z1 = Kit.bounds(b.part)
		return { { x0 + dx, z0 + dz }, { x1 + dx, z0 + dz }, { x1 + dx, z1 + dz }, { x0 + dx, z1 + dz } }
	end
	local a = math.rad((b.part.yaw or 0) + dyaw)
	local c, s = math.cos(a), math.sin(a)
	local hx, hz = b.hx * scale, b.hz * scale
	local out = {}
	for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local lx, lz = corner[1] * hx, corner[2] * hz
		-- Ry: (x, z) -> (x c + z s, -x s + z c)
		table.insert(out, { b.cx + dx + lx * c + lz * s, b.cz + dz - lx * s + lz * c })
	end
	return out
end

-- True when (x, z) is within `tol` of a body's footprint (moved / turned / scaled).
local function covers(
	b: Body,
	x: number,
	z: number,
	tol: number,
	dx: number,
	dz: number,
	dyaw: number,
	scale: number
): boolean
	local shape = b.part.shape
	local px, pz = x - b.cx - dx, z - b.cz - dz
	if shape == "disc" or shape == "ball" then
		local r = b.hx * scale + tol
		return px * px + pz * pz <= r * r
	end
	if b.tilted then
		local x0, x1, _, _, z0, z1 = Kit.bounds(b.part)
		return x >= x0 + dx - tol and x <= x1 + dx + tol and z >= z0 + dz - tol and z <= z1 + dz + tol
	end
	local a = math.rad((b.part.yaw or 0) + dyaw)
	local c, s = math.cos(a), math.sin(a)
	-- the inverse turn: (x, z) -> (x c - z s, x s + z c)
	local lx, lz = px * c - pz * s, px * s + pz * c
	return math.abs(lx) <= b.hx * scale + tol and math.abs(lz) <= b.hz * scale + tol
end

-- The top of a body at (x, z) (a tilted part: its top plane), at rest height + dy.
local function topAt(b: Body, x: number, z: number, dy: number): number
	if not b.tilted then
		return b.cy + b.hy + dy
	end
	local p = b.part
	local n = Kit.rotate({ 0, 1, 0 }, p.yaw, p.pitch, p.roll)
	local u = Kit.rotate({ 0, b.hy, 0 }, p.yaw, p.pitch, p.roll)
	local tx, ty, tz = b.cx + u[1], b.cy + u[2], b.cz + u[3]
	if math.abs(n[2]) < 0.05 then
		return select(4, Kit.bounds(p)) + dy
	end
	local x0, x1, _, _, z0, z1 = Kit.bounds(p)
	x, z = math.clamp(x, x0, x1), math.clamp(z, z0, z1)
	return ty - (n[1] * (x - tx) + n[3] * (z - tz)) / n[2] + dy
end

local function bottomOf(b: Body, dy: number): number
	if b.tilted then
		local _, _, y0 = Kit.bounds(b.part)
		return y0 + dy
	end
	return b.cy - b.hy + dy
end

local function topOf(b: Body, dy: number): number
	if b.tilted then
		local _, _, _, y1 = Kit.bounds(b.part)
		return y1 + dy
	end
	return b.cy + b.hy + dy
end

local function segDist(px: number, pz: number, a: Pt, b: Pt): number
	local ex, ez = b[1] - a[1], b[2] - a[2]
	local len = ex * ex + ez * ez
	local f = if len > 0 then math.clamp(((px - a[1]) * ex + (pz - a[2]) * ez) / len, 0, 1) else 0
	local qx, qz = a[1] + ex * f - px, a[2] + ez * f - pz
	return math.sqrt(qx * qx + qz * qz)
end

-- Separating-axis test for two convex quads: true when they overlap.
local function overlaps(A: { Pt }, B: { Pt }): boolean
	for _, poly in { A, B } do
		for i = 1, #poly do
			local a, b = poly[i], poly[i % #poly + 1]
			local nx, nz = b[2] - a[2], a[1] - b[1]
			local amin, amax, bmin, bmax = math.huge, -math.huge, math.huge, -math.huge
			for _, p in A do
				local d = p[1] * nx + p[2] * nz
				amin, amax = math.min(amin, d), math.max(amax, d)
			end
			for _, p in B do
				local d = p[1] * nx + p[2] * nz
				bmin, bmax = math.min(bmin, d), math.max(bmax, d)
			end
			if amax < bmin - 1e-9 or bmax < amin - 1e-9 then
				return false
			end
		end
	end
	return true
end

-- Edge-to-edge distance between two footprints, seen from above.
local function polyGap(A: { Pt }, B: { Pt }): number
	if overlaps(A, B) then
		return 0
	end
	local best = math.huge
	for _, pair in { { A, B }, { B, A } } do
		local P, Q = pair[1], pair[2]
		for _, p in P do
			for i = 1, #Q do
				best = math.min(best, segDist(p[1], p[2], Q[i], Q[i % #Q + 1]))
			end
		end
	end
	return best
end

-- Distance from a point to a footprint (0 inside).
local function pointGap(px: number, pz: number, P: { Pt }): number
	if overlaps({ { px, pz }, { px, pz }, { px, pz }, { px, pz } }, P) then
		return 0
	end
	local best = math.huge
	for i = 1, #P do
		best = math.min(best, segDist(px, pz, P[i], P[i % #P + 1]))
	end
	return best
end

-- The z range of a footprint inside the strip xa <= x <= xb, or nil when it misses the strip.
local function zRangeIn(P: { Pt }, xa: number, xb: number): (number?, number?)
	local function clip(poly: { Pt }, keep: (Pt) -> boolean, cut: (Pt, Pt) -> Pt): { Pt }
		local out = {}
		for i = 1, #poly do
			local a, b = poly[i], poly[i % #poly + 1]
			local ina, inb = keep(a), keep(b)
			if ina then
				table.insert(out, a)
			end
			if ina ~= inb then
				table.insert(out, cut(a, b))
			end
		end
		return out
	end
	local function at(xc: number): (Pt, Pt) -> Pt
		return function(a: Pt, b: Pt): Pt
			local f = (xc - a[1]) / (b[1] - a[1])
			return { xc, a[2] + (b[2] - a[2]) * f }
		end
	end
	local poly = clip(P, function(p)
		return p[1] >= xa
	end, at(xa))
	poly = clip(poly, function(p)
		return p[1] <= xb
	end, at(xb))
	if #poly == 0 then
		return nil, nil
	end
	local z0, z1 = math.huge, -math.huge
	for _, p in poly do
		z0, z1 = math.min(z0, p[2]), math.max(z1, p[2])
	end
	return z0, z1
end

---------------------------------------------------------------------------
-- budget, widths, fields, challenge
---------------------------------------------------------------------------

-- Parts the section adds to the world: its parts, the decor parts of their markers and a lock per key a gate needs.
function ObbyCheck.partCount(section: Section): number
	local n = #section.parts
	for _, part in section.parts do
		local marker = part.marker
		if marker then
			local kind = if string.sub(marker, 1, 5) == "sign:" then "sign" else marker
			n += ObbyCheck.MARKER_PARTS[kind] or 0
		end
		if part.gate then
			n += part.gate.need
		end
	end
	return n
end

-- The z range a part covers over its whole motion.
local function laneRange(part: Part): (number, number)
	local _, _, _, _, z0, z1 = Kit.bounds(part)
	local m = part.motion
	if m then
		if m.kind == "spin" or m.kind == "sweep" then
			local r = math.max(part.size[1], part.size[3]) / 2
			z0, z1 = math.min(z0, part.pos[3] - r), math.max(z1, part.pos[3] + r)
		else
			local lo, hi = 0, 0
			for k = 0, ObbyCheck.SAMPLES - 1 do
				local _, _, dz = Kit.offsetAt(part, k / ObbyCheck.SAMPLES * Kit.periodOf(part))
				lo, hi = math.min(lo, dz), math.max(hi, dz)
			end
			if m.kind == "path" then
				for _, p in m.points or {} do
					lo, hi = math.min(lo, p[3]), math.max(hi, p[3])
				end
			end
			z0, z1 = z0 + lo, z1 + hi
		end
	end
	return z0, z1
end

function ObbyCheck.budget(section: Section): string?
	local n = ObbyCheck.partCount(section)
	if n > ObbyCheck.PARTS_MAX then
		return `{n} parts with markers (at most {ObbyCheck.PARTS_MAX})`
	end
	if section.length < ObbyCheck.LENGTH_MIN or section.length > ObbyCheck.LENGTH_MAX then
		return `length {section.length} ({ObbyCheck.LENGTH_MIN}..{ObbyCheck.LENGTH_MAX})`
	end
	for i, part in section.parts do
		local z0, z1 = laneRange(part)
		if z0 < -Kit.HALF - 0.01 or z1 > Kit.HALF + 0.01 then
			return `part {i} ({part.look}) leaves the lane: z {z0}..{z1}`
		end
	end
	return nil
end

-- Steps reached by something other than walking on them: their size is not a floor width.
local function special(part: Part): string?
	if part.shape == "truss" then
		return "climb"
	elseif part.motion and part.motion.kind == "lift" then
		return "lift"
	elseif part.sticky then
		return "sticky"
	elseif part.vine then
		return "vine"
	elseif part.cannon then
		return "cannon"
	end
	return nil
end

-- The routes of a section: "main" and every `route` tag on a step.
function ObbyCheck.routes(section: Section): { string }
	local out, seen = { "main" }, {}
	for _, part in section.parts do
		if part.step and part.route and not seen[part.route] then
			seen[part.route] = true
			table.insert(out, part.route)
		end
	end
	return out
end

-- The steps of `route` in order: the main path plus that route's own steps.
local function routeSteps(bodies: { Body }, route: string): { Body }
	local out = {}
	for _, b in bodies do
		local r = b.part.route
		if b.part.step and (r == nil or r == route) then
			table.insert(out, b)
		end
	end
	return out
end

-- Footprint width of a step across the unit direction (ux, uz).
local function widthAcross(b: Body, ux: number, uz: number): number
	if b.part.shape == "disc" or b.part.shape == "ball" then
		return b.hx * 2
	end
	local px, pz = -uz, ux -- across = perpendicular to the way you go
	if b.tilted then
		local x0, x1, _, _, z0, z1 = Kit.bounds(b.part)
		return math.abs(px) * (x1 - x0) + math.abs(pz) * (z1 - z0)
	end
	local a = math.rad(b.part.yaw or 0)
	local c, s = math.cos(a), math.sin(a)
	-- the part's own x axis is (c, -s), its z axis (s, c) in course x / z
	return math.abs(px * c - pz * s) * b.hx * 2 + math.abs(px * s + pz * c) * b.hz * 2
end

function ObbyCheck.widths(section: Section): string?
	local bodies = bodiesOf(section)
	for _, route in ObbyCheck.routes(section) do
		local steps = routeSteps(bodies, route)
		for i, b in steps do
			if not special(b.part) then
				local narrow = math.min(b.hx, b.hz) * 2
				if narrow < Kit.BEAM_MIN - 1e-6 then
					return `{route} step {i} ({b.part.look}) is {narrow} wide (at least {Kit.BEAM_MIN})`
				end
				if b.part.look ~= "beam" then
					local prev, nxt = steps[i - 1] or b, steps[i + 1] or b
					local dx, dz = nxt.cx - prev.cx, nxt.cz - prev.cz
					local len = math.sqrt(dx * dx + dz * dz)
					if len < 1e-6 then
						dx, dz, len = 1, 0, 1
					end
					local w = widthAcross(b, dx / len, dz / len)
					if w < Kit.FLOOR_MIN - 1e-6 then
						return `{route} step {i} ({b.part.look}) is {w} across the way you cross it (at least {Kit.FLOOR_MIN})`
					end
				end
			end
		end
	end
	return nil
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Is a key at `key` within reach of some step (a jump from its top)?
local function keyReachable(key: Body, bodies: { Body }): boolean
	for _, b in bodies do
		if b.part.step then
			local g = pointGap(key.cx, key.cz, footprint(b, 0, 0, 0, 1))
			local up = key.cy - topAt(b, key.cx, key.cz, 0)
			if g <= Kit.GAP_MAX and up >= -1 and up <= Kit.JUMP_HEIGHT + Kit.HEAD then
				return true
			end
		end
	end
	return false
end

function ObbyCheck.fields(section: Section): string?
	local triggers, starts, keys, gates = {}, {}, {}, {}
	local bodies = bodiesOf(section)
	for i, part in section.parts do
		local label = `part {i} ({part.look})`
		for k in part :: any do
			if not PART_FIELDS[k] then
				return `{label}: unknown field {k}`
			end
		end
		if #part.size ~= 3 or #part.pos ~= 3 then
			return `{label}: size and pos need 3 numbers`
		end
		for j = 1, 3 do
			if not finite(part.size[j]) or part.size[j] <= 0 or not finite(part.pos[j]) then
				return `{label}: bad size or pos`
			end
		end
		for name, allowed in SUB_FIELDS do
			local sub = (part :: any)[name]
			if sub ~= nil then
				if type(sub) ~= "table" then
					return `{label}: {name} must be a table`
				end
				for k in sub do
					if not allowed[k] then
						return `{label}: unknown {name} field {k}`
					end
				end
			end
		end
		if part.zone and not ZONE_KINDS[part.zone.kind] then
			return `{label}: unknown zone kind {part.zone.kind}`
		end
		if part.marker then
			local m = part.marker
			if not MARKERS[m] and string.sub(m, 1, 5) ~= "sign:" then
				return `{label}: unknown marker {m}`
			end
		end
		local m = part.motion
		if m then
			if not KINDS[m.kind] then
				return `{label}: unknown motion {m.kind}`
			end
			for k in m :: any do
				if not MOTION_FIELDS[k] then
					return `{label}: unknown motion field {k}`
				end
			end
			if (m.kind == "punch" or m.kind == "rise") and not part.hazard then
				return `{label}: a {m.kind} must be a hazard`
			end
			if TIMED[m.kind] and m.kind ~= "rise" and m.kind ~= "drop" and not finite(Kit.periodOf(part)) then
				return `{label}: {m.kind} needs a period`
			end
			if m.kind == "drop" and not (part.start and finite(m.at)) then
				return `{label}: a drop needs a start group and at`
			end
			if m.kind == "rise" and not (part.start and finite(m.speed)) then
				return `{label}: a rise needs a start group and speed`
			end
			if m.kind == "path" and (m.points == nil or #m.points < 2) then
				return `{label}: a path needs at least 2 points`
			end
			for _, n in m.next or {} do
				if type(n) ~= "number" or section.parts[n] == nil then
					return `{label}: melt next {n} is not a part index`
				end
			end
			for _, b in m.beats or {} do
				if not BEAT_KINDS[b.kind] or not finite(b.at) then
					return `{label}: bad pattern beat`
				end
			end
		end
		if part.trigger then
			triggers[part.trigger] = true
		end
		if part.start then
			starts[part.start] = true
		end
		if part.key and keyReachable(bodies[i], bodies) then
			keys[part.key] = (keys[part.key] or 0) + 1
		end
		if part.gate then
			table.insert(gates, part.gate)
		end
	end
	for g in starts do
		if not triggers[g] then
			return `start group {g} has no trigger`
		end
	end
	for _, gate in gates do
		if (keys[gate.group] or 0) < gate.need then
			return `gate {gate.group} needs {gate.need} keys, {keys[gate.group] or 0} within reach`
		end
	end
	return nil
end

-- At least one hazard, moving or timed part, trigger or controller: no section is just walking (§10).
function ObbyCheck.challenge(section: Section): string?
	for _, part in section.parts do
		if part.hazard or part.motion or part.trigger or part.gate or part.sticky or part.vine or part.cannon then
			return nil
		end
		if part.zone or part.slide or part.conveyor then
			return nil
		end
	end
	return "just walking: no hazard, motion, trigger or controller"
end

---------------------------------------------------------------------------
-- makeable
---------------------------------------------------------------------------

local function bodyState(
	b: Body,
	t: number?,
	started: { [string]: number }?
): (number, number, number, number, number, boolean)
	if t == nil then
		return Kit.offsetAt(b.part, nil)
	end
	return Kit.offsetAt(b.part, clockOf(b, t, started))
end

-- The lowest solid roof over the middle of two steps, as studs over the higher one, or nil.
local function roofOver(bodies: { Body }, a: Body, b: Body, floor: number): number?
	local mx, mz = (a.cx + b.cx) / 2, (a.cz + b.cz) / 2
	local best: number? = nil
	for _, p in bodies do
		if not p.part.step and p.solid and not p.moving and bottomOf(p, 0) > floor + 0.01 then
			if covers(p, mx, mz, 0, 0, 0, 0, 1) then
				local room = bottomOf(p, 0) - floor
				if best == nil or room < best then
					best = room
				end
			end
		end
	end
	return best
end

-- How far a running jump carries on the flat when a roof `room` studs over the floor stops the head.
local function jumpUnderRoof(room: number): number
	local headroom = room - Kit.HEAD
	local v = Kit.JUMP_SPEED
	local peak = v * v / (2 * Kit.GRAVITY)
	if headroom <= 0 then
		return 0
	elseif headroom >= peak then
		return Kit.WALK * 2 * v / Kit.GRAVITY
	end
	local up = (v - math.sqrt(v * v - 2 * Kit.GRAVITY * headroom)) / Kit.GRAVITY
	local down = math.sqrt(2 * headroom / Kit.GRAVITY)
	return Kit.WALK * (up + down)
end

-- The gravity factor of a moon zone over (x, y, z), 1 outside every one.
local function gravityAt(bodies: { Body }, x: number, y: number, z: number): number
	for _, b in bodies do
		local zone = b.part.zone
		if zone and zone.kind == "moon" and covers(b, x, z, 0, 0, 0, 0, 1) then
			if y >= b.cy - b.hy - 0.5 and y <= b.cy + b.hy then
				return zone.gravity or 1
			end
		end
	end
	return 1
end

-- Flight time to come down to `dy` studs below the start, launched at `vy` up (nil if it never gets there).
local function fallTime(vy: number, dy: number, g: number): number?
	local disc = vy * vy + 2 * g * dy
	if disc < 0 then
		return nil
	end
	return (vy + math.sqrt(disc)) / g
end

type Pose = { poly: { Pt }, dx: number, dy: number, dz: number, on: boolean }

local function poseOf(b: Body, t: number?, started: { [string]: number }?): Pose
	local dx, dy, dz, dyaw, scale, on = bodyState(b, t, started)
	return { poly = footprint(b, dx, dz, dyaw, scale), dx = dx, dy = dy, dz = dz, on = on }
end

-- Times to look at a pair of steps: rest, and SAMPLES points over the longer period of whichever moves (a `start`
-- part as if its group started at 0).
local REST = -1 -- a pair time meaning "at rest" (no clock)

local function pairTimes(a: Body, b: Body): { number }
	local times: { number } = { REST }
	if a.moving or b.moving or a.timed or b.timed then
		local period = 0
		for _, x in { a, b } do
			if x.moving or x.timed then
				period = math.max(period, x.period)
			end
		end
		for k = 0, ObbyCheck.SAMPLES - 1 do
			table.insert(times, k / ObbyCheck.SAMPLES * period)
		end
	end
	return times
end

local STARTED_ALL = setmetatable({}, {
	__index = function()
		return 0
	end,
})

-- nil when step `b` can be reached from step `a` at time `t`; otherwise why not.
local function reachAt(bodies: { Body }, a: Body, b: Body, t: number?): string?
	local started = if t then STARTED_ALL :: any else nil
	local pa, pb = poseOf(a, t, started), poseOf(b, t, started)
	if not pa.on or not pb.on then
		return "not there"
	end
	local g = polyGap(pa.poly, pb.poly)
	local bx, bz = b.cx + pb.dx, b.cz + pb.dz
	local ax, az = a.cx + pa.dx, a.cz + pa.dz
	local topA = topAt(a, bx, bz, pa.dy)
	local topB = topAt(b, ax, az, pb.dy)
	local am = a.part.motion
	if am and am.kind == "sink" then
		topA -= math.abs(am.depth or 0) -- you sink while you wait on it: measure from the bottom
	end
	local rise = topB - topA
	local sa, sb = special(a.part), special(b.part)
	local bBottom, bTop = bottomOf(b, pb.dy), topOf(b, pb.dy)
	local aBottom, aTop = bottomOf(a, pa.dy), topOf(a, pa.dy)

	-- Into a ladder or a wind column: walk in, or (a column) jump in from beside it.
	if sb == "climb" then
		return if g <= 1.5 then nil else `gap {g} to a ladder`
	elseif sb == "lift" then
		if g <= 1.5 or (g <= Kit.GAP_MAX and bBottom <= topA + Kit.RISE_MAX and bTop >= topA) then
			return nil
		end
		return `gap {g} to a wind column`
	end
	-- Onto a sticky wall: jump at its face.
	if sb == "sticky" then
		if sa == "sticky" then
			if
				g <= ObbyCheck.STICKY_REACH
				and bTop >= aBottom - 10
				and bBottom <= aTop + ObbyCheck.STICKY_PEAK + Kit.HEAD
			then
				return nil
			end
			return `wall to wall: gap {g}`
		end
		if g <= Kit.GAP_MAX and bTop >= topA and bBottom <= topA + Kit.JUMP_HEIGHT + Kit.HEAD - 1 then
			return nil
		end
		return `gap {g} to a sticky wall`
	end
	-- Grab a rope end: jump at it.
	if sb == "vine" then
		local reach = (b.part.vine :: any).reach or 2
		local ex, ey, ez = bx, b.cy + pb.dy - b.hy, bz
		local d = pointGap(ex, ez, pa.poly)
		local up = ey - topA
		if d <= Kit.GAP_MAX + reach and up >= -reach - 1 and up <= Kit.JUMP_HEIGHT + Kit.HEAD + reach then
			return nil
		end
		return `rope end {d} away, {up} up`
	end
	-- Off a ladder or out of a column: step off at its top (or hover height) onto something at or under it.
	if sa == "climb" or sa == "lift" then
		local exitY = aTop
		if sa == "lift" and am and am.cap then
			exitY = aBottom + am.cap
		end
		local drop = exitY - topB
		local reach = math.max(2, Kit.WALK * math.sqrt(math.max(drop, 0) * 2 / Kit.GRAVITY) * 0.8)
		if drop >= -0.01 and g <= reach then
			return nil
		end
		return `off a {sa}: drop {drop}, gap {g}`
	end
	-- Off a sticky wall: jump away from its face.
	if sa == "sticky" then
		if g <= ObbyCheck.STICKY_REACH and topB <= aTop + ObbyCheck.STICKY_PEAK - 1 then
			return nil
		end
		return `off a sticky wall: gap {g}, rise {topB - aTop}`
	end
	-- Let go of a rope end: its swing speed plus a jump.
	if sa == "vine" then
		local h = 0.01
		local dx2, dy2, dz2 = bodyState(a, (t or 0) + h, started)
		local vx, vy, vz = (dx2 - pa.dx) / h, (dy2 - pa.dy) / h, (dz2 - pa.dz) / h
		local feet = a.cy + pa.dy - a.hy - 2
		local tl = fallTime(vy + ObbyCheck.VINE_UP, feet - topB, Kit.GRAVITY)
		if tl then
			local lx, lz = ax + vx * tl, az + vz * tl
			if pointGap(lx, lz, pb.poly) <= Kit.WALK * tl * 0.5 + 0.5 then
				return nil
			end
		end
		return "let go of the rope: misses"
	end
	-- Fired from a cannon: its fixed arc for the barrel's aim now.
	if sa == "cannon" then
		local cannon = a.part.cannon :: any
		local _, _, _, dyaw = bodyState(a, t, started)
		local aim = math.rad((a.part.yaw or 0) + dyaw)
		local arc = math.rad(cannon.arc)
		local vh, vy = cannon.power * math.cos(arc), cannon.power * math.sin(arc)
		local tl = fallTime(vy, a.cy - topB, Kit.GRAVITY)
		if tl then
			local lx, lz = ax + math.cos(aim) * vh * tl, az - math.sin(aim) * vh * tl
			if pointGap(lx, lz, pb.poly) <= ObbyCheck.CANNON_SLACK then
				return nil
			end
		end
		return "the cannon's arc misses"
	end
	-- Launched by a pad (with its throw).
	if am and am.kind == "bounce" and am.power then
		local throw = am.throw or { 0, 0, 0 }
		local grav = gravityAt(bodies, ax, topA + 1, az)
		local vy = am.power + throw[2]
		local peak = vy * vy / (2 * Kit.GRAVITY * grav)
		if rise > peak - 1.5 then
			return `rise {rise} over a {peak}-stud launch`
		end
		local tl = fallTime(vy, -rise, Kit.GRAVITY * grav) :: number
		local shifted = {}
		for _, p in pa.poly do
			table.insert(shifted, { p[1] + throw[1] * tl, p[2] + throw[3] * tl })
		end
		local reach = Kit.WALK * tl * 0.8
		local gl = polyGap(shifted, pb.poly)
		return if gl <= reach then nil else `gap {gl} past a {reach}-stud launch`
	end
	-- Walk or jump: further off a boost strip or a slide, shorter under a roof or off a back strip, further on the moon.
	local factor = 1
	if a.part.boost then
		factor = a.part.boost.speed / Kit.WALK
	elseif a.part.slide then
		factor = math.max(a.part.slide.cap, Kit.WALK) / Kit.WALK
	end
	local grav = gravityAt(bodies, ax, topA + 1, az)
	local gapMax = Kit.GAP_MAX * factor / grav
	local riseMax = Kit.RISE_MAX / grav
	local room = roofOver(bodies, a, b, math.max(topA, topB))
	if room then
		gapMax = math.min(gapMax, jumpUnderRoof(room) * 0.8)
	end
	if g > gapMax then
		return `gap {g} (at most {gapMax})`
	elseif rise > riseMax then
		return `rise {rise} (at most {riseMax})`
	end
	return nil
end

-- nil when `b` can be reached from `a` at some time; otherwise why not (at rest).
local function reachable(bodies: { Body }, a: Body, b: Body): string?
	local first: string? = nil
	for _, t in pairTimes(a, b) do
		local why = reachAt(bodies, a, b, if t == REST then nil else t)
		if why == nil then
			return nil
		end
		first = first or why
	end
	return first
end

function ObbyCheck.makeable(section: Section): string?
	local bodies = bodiesOf(section)
	for _, route in ObbyCheck.routes(section) do
		local steps = routeSteps(bodies, route)
		if #steps < 2 then
			return `{route}: fewer than 2 steps`
		end
		for i = 2, #steps do
			local why = reachable(bodies, steps[i - 1], steps[i])
			if why then
				-- A branch: any earlier step of this route may lead here.
				for j = i - 2, 1, -1 do
					if reachable(bodies, steps[j], steps[i]) == nil then
						why = nil
						break
					end
				end
			end
			if why then
				return `{route} step {i} (part {steps[i].index}, {steps[i].part.look}): {why}`
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- straightWalk: hold forward, never jump
---------------------------------------------------------------------------

local WALK_DT = 1 / 30
local STEP_UP = 1 -- a ledge up to this high is walked (or, falling, stumbled) up
local FEET = 1 -- studs past a floor's edge the walker still stands: half the root part's width
ObbyCheck.WALK_LINES = 1 -- studs between the lines across the lane a walker tries
ObbyCheck.WALK_STARTS = 12 -- start times a walker tries over the longest period

-- Parts by x bucket, so a walker only looks at what is near it.
local BUCKET = 4
local function bucketsOf(bodies: { Body }): { [number]: { Body } }
	local out: { [number]: { Body } } = {}
	for _, b in bodies do
		local x0, x1 = b.x0, b.x1
		local swinging = b.part.motion and b.part.motion.kind == "swing"
		if swinging then
			-- a swinging part moves across, not along: its rest x range is enough
			x0, x1 = Kit.bounds(b.part)
		end
		for k = math.floor((x0 - 2) / BUCKET), math.floor((x1 + 2) / BUCKET) do
			out[k] = out[k] or {}
			table.insert(out[k], b)
		end
	end
	return out
end

--[[
	A walker holding forward along the line z = `z0` from the first step, starting at time `t0`: it stands while any
	of its 2-stud width is over a floor, walks (and, falling, stumbles) up ledges up to STEP_UP, so a hole under about
	3.6 studs is walked over and a longer one drops it under the far edge. It rides moving floors, belts, boosts,
	launch pads, lifts and gusts it meets, starts triggers and picks up keys. Returns nil when it reaches the end of
	the section (bad: the section can be cleared without a jump), else what stopped it.
]]
function ObbyCheck.walkStop(section: Section, z0: number, t0: number, prepared: { [string]: any }?): string?
	local bodies = if prepared then prepared.bodies else bodiesOf(section)
	local buckets = if prepared then prepared.buckets else bucketsOf(bodies)
	local first: Body? = nil
	for _, b in bodies do
		if b.part.step then
			first = b
			break
		end
	end
	if not first then
		return "no steps"
	end
	local fx0 = Kit.bounds(first.part)
	local x, z = fx0 + 0.5, z0
	if not covers(first, x, z, 0, 0, 0, 0, 1) then
		return "the line misses the first step"
	end
	local y = topAt(first, x, z, 0)
	local vy, airborne = 0, false
	local ex, ez = 0, 0 -- sideways / forward speed from a throw or a gust (kept while in the air)
	local speed, boostEnd = Kit.WALK, -math.huge
	local started: { [string]: number } = {}
	local keys: { [string]: number } = {}
	local took: { [Body]: boolean } = {}
	local melted: { [Body]: number } = {} -- melt start time
	local was: Body? = nil
	local t = t0
	local limit = t0 + section.length / Kit.WALK * 3 + 10
	local lowest = math.huge
	for _, b in bodies do
		if b.part.step then
			lowest = math.min(lowest, topOf(b, 0))
		end
	end

	-- Is `b` there and solid now (on, gate shut, not melted away)? With its offsets.
	local function solidNow(b: Body, now: number): (boolean, number, number, number, number, number)
		local dx, dy, dz, dyaw, scale, on = Kit.offsetAt(b.part, clockOf(b, now, started))
		local here = on and b.solid
		local gate = b.part.gate
		if here and gate and (keys[gate.group] or 0) >= gate.need then
			here = false
		end
		local m = b.part.motion
		local since = melted[b]
		if here and m and m.kind == "melt" and since then
			local gone = now - since >= (m.delay or 0)
			local back = (m.away or -1) >= 0 and now - since >= (m.delay or 0) + (m.away or 0)
			here = not gone or back
		end
		return here, dx, dy, dz, dyaw, scale
	end

	local function at(): number
		return math.floor(x * 10) / 10
	end

	while t < limit do
		local near = buckets[math.floor(x / BUCKET)] or {}
		local grav = 1
		-- What is under and in front of the walker now.
		local support: Body? = nil
		local supportTop = -math.huge
		local supportD = { 0, 0, 0 }
		for _, b in near do
			local here, dx, dy, dz, dyaw, scale = solidNow(b, t)
			local over = y + STEP_UP
			if here and b.floor and covers(b, x, z, FEET, dx, dz, dyaw, scale) then
				local top = topAt(b, x, z, dy)
				if b.part.motion and b.part.motion.kind == "sink" and was == b then
					top -= math.abs(b.part.motion.depth or 0)
				end
				if top <= over and top > supportTop then
					supportTop, support, supportD = top, b, { dx, dy, dz }
				end
			end
			if here and covers(b, x + ObbyCheck.BODY, z, 0.2, dx, dz, dyaw, scale) then
				local top, bottom = topAt(b, x + ObbyCheck.BODY, z, dy), bottomOf(b, dy)
				if top > over and bottom < y + Kit.HEAD then
					return `blocked by part {b.index} ({b.part.look}) at x {at()}`
				end
			end
			if b.part.hazard then
				local _, _, _, _, _, on = Kit.offsetAt(b.part, clockOf(b, t, started))
				if on and covers(b, x, z, ObbyCheck.BODY, dx, dz, dyaw, scale) then
					if topOf(b, dy) > y and bottomOf(b, dy) < y + Kit.HEAD then
						return `hits hazard part {b.index} at x {at()}`
					end
				end
			end
			local touch = covers(b, x, z, 0.5, 0, 0, 0, 1) and y >= bottomOf(b, 0) - 0.5 and y <= topOf(b, 0) + Kit.HEAD
			if touch then
				if b.part.trigger and started[b.part.trigger] == nil then
					started[b.part.trigger] = t
				end
				if b.part.key and not took[b] then
					took[b] = true
					keys[b.part.key] = (keys[b.part.key] or 0) + 1
				end
				if b.part.vine or b.part.cannon then
					return `caught by a {if b.part.vine then "rope" else "cannon"} at x {at()}`
				end
				local zone = b.part.zone
				if zone and zone.kind == "moon" then
					grav = zone.gravity or 1
				end
				local m = b.part.motion
				if m and (m.kind == "lift" or m.kind == "gust") then
					local _, _, _, _, _, on = Kit.offsetAt(b.part, clockOf(b, t, started))
					if on and m.kind == "lift" and y < topOf(b, 0) then
						airborne = true
						local cap = m.cap
						vy = if cap and y >= bottomOf(b, 0) + cap then 0 else (m.power or 0)
					elseif on and m.kind == "gust" then
						local p = m.power or 0
						if m.axis == "x" then
							ex = p
						elseif m.axis == "z" then
							ez = p
						end
					end
				end
			end
		end

		-- Stand, step down, or fall.
		local standing = false
		if airborne then
			-- exact for a constant pull over the tick
			local g = Kit.GRAVITY * grav
			local ny = y + vy * WALK_DT - g * WALK_DT * WALK_DT / 2
			if support and vy <= 0 and supportTop >= ny - 0.05 then
				-- landed, or stumbled up onto a ledge just over its feet
				y, vy, airborne = supportTop, 0, false
				ex, ez = 0, 0
				standing = true
			else
				vy -= g * WALK_DT
				y = ny
			end
		elseif support and supportTop >= y - 0.6 then
			y = supportTop
			standing = true
		else
			-- walked off: it starts falling this tick
			airborne = true
			local g = Kit.GRAVITY * grav
			y += -g * WALK_DT * WALK_DT / 2
			vy = -g * WALK_DT
		end

		-- What the floor under you does.
		local onPart = if standing then support else nil
		if was and was ~= onPart then
			local m = was.part.motion
			if m and m.kind == "melt" and m.on == "leave" and melted[was] == nil then
				melted[was] = t
			end
			if was.part.boost then
				boostEnd = t + (was.part.boost.carry or 0)
			end
		end
		local fx, fz = 0, 0
		if onPart then
			local m = onPart.part.motion
			if m and m.kind == "melt" and m.on ~= "leave" and melted[onPart] == nil then
				melted[onPart] = t
			end
			if onPart.part.boost then
				speed = onPart.part.boost.speed
				boostEnd = math.huge
			end
			local belt = Kit.conveyorAt(onPart.part, clockOf(onPart, t, started))
			if belt then
				fx, fz = belt[1], belt[3]
			end
			if onPart.moving then
				local dx2, _, dz2 = Kit.offsetAt(onPart.part, clockOf(onPart, t + WALK_DT, started))
				fx += (dx2 - supportD[1]) / WALK_DT
				fz += (dz2 - supportD[3]) / WALK_DT
			end
			if m and m.kind == "bounce" then
				local _, _, _, _, _, on = Kit.offsetAt(onPart.part, clockOf(onPart, t, started))
				if on then
					local throw = m.throw or { 0, 0, 0 }
					airborne = true
					vy = (m.power or 0) + throw[2]
					ex, ez = throw[1], throw[3]
				end
			end
		end
		if t > boostEnd then
			speed, boostEnd = Kit.WALK, -math.huge
		end
		was = onPart

		x += (speed + ex + fx) * WALK_DT
		z += (ez + fz) * WALK_DT
		t += WALK_DT
		if not airborne and x >= section.length - 0.25 and math.abs(y - section.rise) < 1.6 then
			return nil
		end
		if x > section.length + 2 then
			return if y >= section.rise - 1 then nil else "falls past the end"
		end
		if y < lowest - 20 then
			return `falls at x {at()}`
		end
		if math.abs(z) > Kit.HALF + 1 then
			return "carried off the side"
		end
	end
	return "stuck"
end

-- nil when no straight walk clears the section; otherwise how one did (a line z and a start time).
function ObbyCheck.straightWalk(section: Section): string?
	local bodies = bodiesOf(section)
	local prepared = { bodies = bodies, buckets = bucketsOf(bodies) }
	local period = 0
	for _, b in bodies do
		if b.timed or b.part.start or b.part.conveyor then
			period = math.max(period, b.period)
		end
	end
	local starts = { 0 }
	if period > 0 then
		for k = 1, ObbyCheck.WALK_STARTS - 1 do
			table.insert(starts, k / ObbyCheck.WALK_STARTS * period)
		end
	end
	local z = -Kit.HALF + 1
	while z <= Kit.HALF - 1 + 1e-6 do
		for _, t0 in starts do
			if ObbyCheck.walkStop(section, z, t0, prepared) == nil then
				return `holding forward along z {z} from t {math.floor(t0 * 100) / 100} clears it`
			end
		end
		z += ObbyCheck.WALK_LINES
	end
	return nil
end

---------------------------------------------------------------------------
-- fairness: hazard windows for the runner
---------------------------------------------------------------------------

type Interval = { number } -- { from, to }

local function subtract(list: { Interval }, a: number, b: number): { Interval }
	local out = {}
	for _, iv in list do
		if b <= iv[1] or a >= iv[2] then
			table.insert(out, iv)
		else
			if a > iv[1] then
				table.insert(out, { iv[1], a })
			end
			if b < iv[2] then
				table.insert(out, { b, iv[2] })
			end
		end
	end
	return out
end

local function intersect(A: { Interval }, B: { Interval }): { Interval }
	local out = {}
	for _, a in A do
		for _, b in B do
			local lo, hi = math.max(a[1], b[1]), math.min(a[2], b[2])
			if hi > lo then
				table.insert(out, { lo, hi })
			end
		end
	end
	return out
end

local function dilate(list: { Interval }, d: number): { Interval }
	local grown = {}
	for _, iv in list do
		table.insert(grown, { iv[1] - d, iv[2] + d })
	end
	table.sort(grown, function(p, q)
		return p[1] < q[1]
	end)
	local out = {}
	for _, iv in grown do
		local last = out[#out]
		if last and iv[1] <= last[2] then
			last[2] = math.max(last[2], iv[2])
		else
			table.insert(out, { iv[1], iv[2] })
		end
	end
	return out
end

local SLICE = 0.5 -- studs between the runner's x slices
local START_STEP = 0.05 -- seconds between the start times tried
local RUN_STEP = 0.05 -- seconds between the runner's samples while it crosses

type Slice = { x: number, free: { Interval }, low: number, high: number, floor: boolean }

-- What is under the runner at every slice: the z intervals it can run on (walls taken out) and the floor heights.
local function slicesOf(section: Section, bodies: { Body }): { Slice }
	local out: { Slice } = {}
	local lastFree: { Interval } = {}
	local lastLow, lastHigh = 0, 0
	local n = math.floor(section.length / SLICE)
	for k = 0, n do
		local x = k * SLICE
		local free: { Interval } = {}
		local low, high = math.huge, -math.huge
		for _, b in bodies do
			if b.part.step and b.floor then
				local z0, z1 = zRangeIn(footprint(b, 0, 0, 0, 1), x - 1e-6, x + 1e-6)
				if z0 and z1 then
					table.insert(free, { z0, z1 })
					local top = topAt(b, x, (z0 + z1) / 2, 0)
					low, high = math.min(low, top), math.max(high, top)
				end
			end
		end
		local floor = #free > 0
		if floor then
			free = dilate(free, 0)
			lastFree, lastLow, lastHigh = free, low, high
		else
			-- in the air over a gap: the runner keeps the line it jumped on, up to a jump high
			free, low, high = lastFree, lastLow, lastHigh + Kit.JUMP_HEIGHT
		end
		for _, b in bodies do
			if b.solid and not b.part.step and not b.moving and not b.part.motion then
				local z0, z1 = zRangeIn(footprint(b, 0, 0, 0, 1), x - ObbyCheck.BODY, x + ObbyCheck.BODY)
				if z0 and z1 and bottomOf(b, 0) < high + Kit.HEAD and topOf(b, 0) > low + STEP_UP then
					free = subtract(free, z0 - ObbyCheck.BODY, z1 + ObbyCheck.BODY)
				end
			end
		end
		table.insert(out, { x = x, free = free, low = low, high = high, floor = floor })
	end
	return out
end

export type Window = { from: number, to: number, slack: number, cross: number }

-- Every stretch of hazards along the section and the seconds the runner has to set off into it.
function ObbyCheck.windows(section: Section): { Window }
	local bodies = bodiesOf(section)
	local hazards = {}
	for _, b in bodies do
		if b.part.hazard and b.kind ~= "rise" then
			table.insert(hazards, b)
		end
	end
	if #hazards == 0 then
		return {}
	end
	local slices = slicesOf(section, bodies)
	-- Slices any hazard ever reaches (with a body's width): the runner can't stop there.
	local risky = {}
	for k, s in slices do
		for _, h in hazards do
			if s.x >= h.x0 - ObbyCheck.BODY and s.x <= h.x1 + ObbyCheck.BODY then
				risky[k] = true
				break
			end
		end
	end
	local zones = {}
	local k = 1
	while k <= #slices do
		if risky[k] then
			local a = k
			while k <= #slices and risky[k] do
				k += 1
			end
			local last = zones[#zones]
			-- a pocket under two bodies wide is no place to wait: one stretch
			if last and (a - last[2]) * SLICE < 2 * ObbyCheck.BODY then
				last[2] = k - 1
			else
				table.insert(zones, { a, k - 1 })
			end
		else
			k += 1
		end
	end
	local triggers: { [string]: number } = {}
	for _, b in bodies do
		if b.part.trigger then
			local x0 = Kit.bounds(b.part)
			triggers[b.part.trigger] = math.min(triggers[b.part.trigger] or math.huge, x0)
		end
	end

	local out: { Window } = {}
	for _, zone in zones do
		local ia, ib = math.max(1, zone[1] - 1), math.min(#slices, zone[2] + 1)
		local entry, exit = slices[ia].x, slices[ib].x
		local inZone = {}
		local period = 0
		local clocked: { [string]: boolean } = {}
		for _, h in hazards do
			if h.x1 + ObbyCheck.BODY >= entry and h.x0 - ObbyCheck.BODY <= exit then
				table.insert(inZone, h)
				period = math.max(period, h.period)
				if h.part.start then
					clocked[h.part.start] = true
				end
			end
		end
		local jumps, inGap = 0, false
		for i = ia, ib do
			if not slices[i].floor and not inGap then
				jumps += 1
			end
			inGap = not slices[i].floor
		end
		local cross = (exit - entry) / Kit.WALK + Kit.JUMP_LOSS * jumps
		local horizon = math.min(30, math.max(4 * period, 8))
		-- A `start` clock runs from the trigger; the runner can't get to this stretch before walking there from it.
		local earliest = 0
		for g in clocked do
			local tx = triggers[g]
			if tx and tx <= entry then
				earliest = math.max(earliest, (entry - tx) / Kit.WALK)
			end
		end
		local function blocked(i: number, t: number, started: { [string]: number }): { Interval }
			local s = slices[i]
			local free = s.free
			for _, h in inZone do
				local dx, dy, dz, dyaw, scale, on = Kit.offsetAt(h.part, clockOf(h, t, started))
				if on and bottomOf(h, dy) < s.high + Kit.HEAD and topOf(h, dy) > s.low then
					local z0, z1 =
						zRangeIn(footprint(h, dx, dz, dyaw, scale), s.x - ObbyCheck.BODY, s.x + ObbyCheck.BODY)
					if z0 and z1 then
						free = subtract(free, z0 - ObbyCheck.BODY, z1 + ObbyCheck.BODY)
					end
				end
			end
			return free
		end
		local function passes(t0: number): boolean
			local started: { [string]: number } = {}
			for g in clocked do
				local tx = triggers[g]
				if tx and tx <= entry then
					started[g] = 0
				end
			end
			local alive = blocked(ia, t0, started)
			local n = math.max(1, math.ceil(cross / RUN_STEP))
			for step = 1, n do
				if #alive == 0 then
					return false
				end
				local f = step / n
				local t = t0 + cross * f
				local x = entry + (exit - entry) * f
				for g in clocked do
					local tx = triggers[g]
					if started[g] == nil and tx and x >= tx then
						started[g] = t
					end
				end
				local i = math.clamp(math.floor(x / SLICE + 0.5) + 1, 1, #slices)
				alive = intersect(dilate(alive, ObbyCheck.LATERAL * cross / n), blocked(i, t, started))
			end
			return #alive > 0
		end
		local best, run = 0, 0
		local t0 = earliest
		while t0 <= earliest + horizon + 1e-9 do
			if passes(t0) then
				run += 1
				best = math.max(best, run)
			else
				run = 0
			end
			t0 += START_STEP
		end
		table.insert(out, { from = entry, to = exit, slack = best * START_STEP, cross = cross })
	end
	return out
end

function ObbyCheck.fairness(section: Section, tier: string): string?
	local need = ObbyCheck.WINDOW[tier] or ObbyCheck.WINDOW.easy
	for _, w in ObbyCheck.windows(section) do
		if w.slack < need - 1e-6 then
			return `hazards at x {w.from}..{w.to}: open {w.slack} s past the {math.floor(w.cross * 100) / 100} s crossing (at least {need})`
		end
	end
	return nil
end

-- Floods and collapses: walking on without a stop from the trigger, the runner leaves every collapsing piece and
-- every step a flood covers SPARE seconds before it goes.
function ObbyCheck.timers(section: Section): string?
	local bodies = bodiesOf(section)
	for _, route in ObbyCheck.routes(section) do
		local steps = routeSteps(bodies, route)
		for _, trig in bodies do
			local g = trig.part.trigger
			if g then
				-- The step the trigger sits on (or nearest), and the walk on from there.
				local tp = footprint(trig, 0, 0, 0, 1)
				local k0, bestGap = 1, math.huge
				for k, s in steps do
					local gap = polyGap(tp, footprint(s, 0, 0, 0, 1))
					if gap < bestGap then
						k0, bestGap = k, gap
					end
				end
				local leave: { [number]: number } = {}
				local at = 0
				for k = k0, #steps do
					local s = steps[k]
					if k > k0 then
						local p = steps[k - 1]
						local d = math.sqrt((s.cx - p.cx) ^ 2 + (s.cz - p.cz) ^ 2)
						local jump = polyGap(footprint(p, 0, 0, 0, 1), footprint(s, 0, 0, 0, 1)) > 0.5
							or math.abs(topOf(s, 0) - topOf(p, 0)) > 0.5
						at += d / Kit.WALK + (if jump then Kit.JUMP_LOSS else 0)
					else
						at = math.abs(s.cx - trig.cx) / Kit.WALK
					end
					leave[k] = at + s.hx / Kit.WALK
				end
				for k = k0, #steps do
					local s = steps[k]
					local m = s.part.motion
					if
						m
						and m.kind == "drop"
						and s.part.start == g
						and leave[k] + ObbyCheck.SPARE > (m.at or 0) + 1e-6
					then
						return `{route}: piece {s.index} drops at {m.at} s, the runner leaves it at {leave[k]} s`
					end
				end
				for _, flood in bodies do
					local m = flood.part.motion
					if m and m.kind == "rise" and flood.part.start == g then
						for k = k0, #steps do
							local s = steps[k]
							local sx0, sx1 = Kit.bounds(s.part)
							local fx0, fx1 = Kit.bounds(flood.part)
							if sx1 > fx0 and sx0 < fx1 and k < #steps then
								local _, dy = Kit.offsetAt(flood.part, leave[k] + ObbyCheck.SPARE)
								if topOf(flood, dy) > topOf(s, 0) + 1e-6 then
									return `{route}: the flood covers step {s.index} {ObbyCheck.SPARE} s after the runner leaves it`
								end
							end
						end
					end
				end
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- fall
---------------------------------------------------------------------------

-- The fall height never resets a runner above a step they could land on: every point of every step's top (at rest
-- and at its lowest while it moves) stays above it. `pick` places the section in a one-section course.
function ObbyCheck.fall(pick: ObbyCourse.Pick): string?
	local course = ObbyCourse.build(1, { pick })
	local depth = Config.OBBY.FALL_DEPTH
	for _, part in course.parts do
		if part.step and not part.ghost then
			local low = math.huge
			for _, c in Kit.topCorners(part) do
				low = math.min(low, c[2])
			end
			local m = part.motion
			if m and m.kind == "slide" and m.axis == "y" then
				low -= math.abs(m.amp or 0)
			elseif m and m.kind == "path" then
				local lo = 0
				for _, p in m.points or {} do
					lo = math.min(lo, p[2])
				end
				low += lo
			elseif m and m.kind == "sink" then
				low -= math.abs(m.depth or 0)
			end
			local x0, x1 = Kit.bounds(part)
			for _, f in { 0, 0.5, 1 } do
				local p = { x0 + (x1 - x0) * f, low, part.pos[3] }
				if low < ObbyCourse.fallHeight(course, p) + depth - 1e-6 then
					return `a {part.look} step {part.id} top at {low} is under the fall floor`
				end
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- All of it
---------------------------------------------------------------------------

-- Every check on one case for seeds 1..SEEDS. Returns the problems found (empty = passes).
function ObbyCheck.run(case: Case): { string }
	local problems = {}
	local seen: { [string]: boolean } = {}
	for seed = 1, ObbyCheck.SEEDS do
		local ok, section = pcall(case.build, seed)
		if not ok then
			table.insert(problems, `{case.name} seed {seed}: build fails: {section}`)
			return problems
		end
		local again = case.build(seed)
		local key = ObbyCheck.encode(section)
		if ObbyCheck.encode(again) ~= key then
			table.insert(problems, `{case.name} seed {seed}: not the same parts for the same seed`)
			return problems
		end
		if not seen[key] then
			seen[key] = true
			local pick = { id = case.idea.id, tier = case.tier, variant = case.variant, seed = seed }
			local checks: { { any } } = {
				{ "budget", ObbyCheck.budget },
				{ "widths", ObbyCheck.widths },
				{ "fields", ObbyCheck.fields },
				{ "challenge", ObbyCheck.challenge },
				{ "makeable", ObbyCheck.makeable },
				{ "straightWalk", ObbyCheck.straightWalk },
				{ "timers", ObbyCheck.timers },
			}
			for _, check in checks do
				local why = check[2](section)
				if why then
					table.insert(problems, `{case.name} seed {seed}: {check[1]}: {why}`)
				end
			end
			local unfair = ObbyCheck.fairness(section, case.tier)
			if unfair then
				table.insert(problems, `{case.name} seed {seed}: fairness: {unfair}`)
			end
			local fell = ObbyCheck.fall(pick)
			if fell then
				table.insert(problems, `{case.name} seed {seed}: fall: {fell}`)
			end
		end
	end
	return problems
end

return ObbyCheck
