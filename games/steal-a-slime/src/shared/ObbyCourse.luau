--!strict
--[[
	ObbyCourse (pure, contract/obby.md, contract/obby-sections.md)

	The Obby sky course as data. The sections themselves live in ObbySections (one module per idea, each with many
	variants, built with ObbySections.Kit); this module picks, lays out and measures them.

	`pick(slot)` chooses the sections of one rotation: one per Config.OBBY.ORDER tier slot, an idea not used in this
	course nor (inside one chain of CHAIN_SLOTS rotations) in the course before it, then a variant of that idea with
	that tier (an idea's generator counts as one more variant, `variant = 0`) and a seed. An idea with no variant of a
	tier is skipped for that slot. `build(slot)` lays the course out: a start pad (the Goo Ring home standing on its
	back edge), then the sections joined by short jelly connectors in line with the path, then the finish pad. Every
	part gets a unique `id` ("<section>.<index>", start "s", home catch pad "h", connectors "l<n>", finish "f") and a
	melt's `next` indices become those ids. There are no checkpoints: the server tracks which section a runner is
	over (`sectionAt`), and a runner that drops `fallHeight` under the lowest platform it could still land on goes
	straight back to the start pad. Every server and client gets the same course for the same slot.

	Course-local frame: x runs forward along the course, y up, z to the right. A part's `pos` is its centre; `yaw`,
	`pitch`, `roll` turn it (Kit.rotate: YXZ order, roll lifts the forward end). Parts flagged `step` are the walking
	path in order (`route` tags branches). Moving parts carry a `motion` the client plays (visuals/client/ObbyFx);
	the server only uses the spans and the finish. `toWorld` / `toLocal` map between this frame and the world for a
	Frame (origin + yaw, from WorldLayout.OBBY).

	Motion kinds (contract/obby-sections.md §4; Kit.offsetAt has the clocks):
	  slide, punch, pattern  move along `axis`; spin, sweep  turn round their vertical axis; swing  a pendulum across
	  the course; rock  a seesaw; roll  a log; path  through `points`; shrink  breathes its size; flip  solid on a duty;
	  melt  fades once stood on; sink  lowers under you; drop  collapses on its `start` clock; rise  a flood;
	  bounce  throws you up; lift  a wind column; gust  a sideways wind; turn  a belt that flips direction.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local ObbySections = if script then require(script.Parent.ObbySections) else require("./ObbySections")
local Kit = if script then require(script.Parent.ObbySections.Kit) else require("./ObbySections/Kit")

local OBBY = Config.OBBY

export type Vec = Kit.Vec
export type Motion = Kit.Motion
export type Part = Kit.Part
export type Section = Kit.Section

-- One section of a course: idea `id`, its variant (index into the idea's variants; 0 = its generator) and the seed.
export type Pick = { id: string, tier: string, variant: number, seed: number }

-- One section's stretch of the course along x, with the connector after it.
export type Span = {
	index: number, -- 1..#picks
	from: number, -- course-local x where the section starts
	to: number, -- course-local x where the next section (or the finish pad) starts
	floor: number, -- the lower of its entry and exit heights: falls are measured from here
}

-- The Goo Ring behind the start pad: stepping in ends the run and sets the runner down in the yard.
export type Ring = {
	pos: Vec, -- ring centre on the pad's top
	radius: number,
}

-- The finish pad.
export type Zone = {
	pos: Vec, -- pad top centre
	size: Vec, -- pad footprint (x, _, z) and the height above the top that counts as standing on it (y)
}

-- Where a falling runner could still land: a solid platform's course-local x extent and its lowest top.
export type Floor = { from: number, to: number, top: number }

export type Course = {
	slot: number,
	picks: { Pick },
	parts: { Part },
	floors: { Floor }, -- every platform a runner could land on (fallHeight)
	start: Vec, -- where a runner appears (above the start pad)
	startTop: number, -- the start pad's top
	home: Ring, -- the way back to base: the walk-in circle just behind the Goo Ring on the start pad's back edge
	spans: { Span }, -- one per pick, in order
	finish: Zone,
	length: number,
}

export type Frame = { origin: Vec, yaw: number } -- yaw in degrees: forward = (sin yaw, 0, cos yaw)

local ObbyCourse = {}

ObbyCourse.START_LENGTH = 12
ObbyCourse.LINK_LENGTH = 4 -- connector between two sections: a jelly block in line with the path, no checkpoint
ObbyCourse.LINK_MIN_WIDTH = 4 -- the connector spans the path's ends next to it, at least this wide
ObbyCourse.LINK_MARGIN = 0.5 -- studs past those ends on either side
ObbyCourse.FALL_REACH = 10 -- studs along the course a falling runner can still drift onto a platform
ObbyCourse.FINISH_LENGTH = 12
ObbyCourse.HOME_LENGTH = 7 -- the catch pad behind the start pad, under the far side of the Goo Ring home
ObbyCourse.HOME_BACK = 2 -- studs behind the start pad's back edge (where the ring stands) that the walk-in circle sits
ObbyCourse.HOME_WIDTH = 8
ObbyCourse.HOME_RADIUS = 2.5 -- studs: stepping inside the Goo Ring ends the run
ObbyCourse.WIDTH = Kit.WIDTH -- pad and lane width across the course
ObbyCourse.STAND_HEIGHT = 9 -- studs above the finish pad's top that count as standing on it
ObbyCourse.THICK = Kit.THICK -- platform thickness
ObbyCourse.SEED_MAX = 999999 -- a pick's seed is 1..this

---------------------------------------------------------------------------
-- Rotation
---------------------------------------------------------------------------

function ObbyCourse.slot(now: number): number
	return math.floor(now / OBBY.ROTATION_SECONDS)
end

-- Server time the rotation `slot` starts.
function ObbyCourse.slotStart(slot: number): number
	return slot * OBBY.ROTATION_SECONDS
end

local function seedOf(slot: number): number
	return (math.floor(slot) * 2654435761 + 1013) % 2147483646 + 1
end

-- One idea's choices for a tier: its variant indices of that tier (0 = its generator).
type Option = { idea: Kit.Idea, variants: { number } }

-- The tier a variant index of `idea` builds as (a generator: `tier` when it covers it, else its first tier).
local function tierOf(idea: Kit.Idea, variant: number, tier: string): string
	if variant == 0 then
		local gen = idea.generator :: Kit.Generator
		return if table.find(gen.tiers, tier) then tier else gen.tiers[1]
	end
	return idea.variants[variant].tier
end

-- The ideas with something of `tier` (nil: anything at all), in registry order.
local function optionsFor(tier: string?): { Option }
	local out = {}
	for _, idea in ObbySections.ALL do
		local variants = {}
		for i, v in idea.variants do
			if tier == nil or v.tier == tier then
				table.insert(variants, i)
			end
		end
		local gen = idea.generator
		if gen and (tier == nil or table.find(gen.tiers, tier)) then
			table.insert(variants, 0)
		end
		if #variants > 0 then
			table.insert(out, { idea = idea, variants = variants })
		end
	end
	return out
end

local OPTIONS: { [string]: { Option } } = {}
for _, tier in OBBY.ORDER do
	OPTIONS[tier] = OPTIONS[tier] or optionsFor(tier)
end
local ANY = optionsFor(nil)

-- The options in `pool` whose idea passes `keep`.
local function filter(pool: { Option }, keep: (id: string) -> boolean): { Option }
	local out = {}
	for _, option in pool do
		if keep(option.idea.id) then
			table.insert(out, option)
		end
	end
	return out
end

local function rawPick(slot: number, avoid: { [string]: boolean }): { Pick }
	assert(#ANY > 0, "no obby section ideas registered")
	local rng = Rng.new(seedOf(slot))
	local used: { [string]: boolean } = {}
	local out: { Pick } = {}
	for _, tier in OBBY.ORDER do
		-- Fresh ideas of this tier first, then ones from the course before, then (only while the registry is short of
		-- this tier) any idea at all, so a course can always be built.
		local options = filter(OPTIONS[tier], function(id)
			return not used[id] and not avoid[id]
		end)
		if #options == 0 then
			options = filter(OPTIONS[tier], function(id)
				return not used[id]
			end)
		end
		if #options == 0 then
			options = filter(ANY, function(id)
				return not used[id]
			end)
		end
		if #options == 0 then
			options = ANY
		end
		local option = options[rng:int(1, #options)]
		local variant = option.variants[rng:int(1, #option.variants)]
		local seed = rng:int(1, ObbyCourse.SEED_MAX)
		used[option.idea.id] = true
		table.insert(
			out,
			{ id = option.idea.id, tier = tierOf(option.idea, variant, tier), variant = variant, seed = seed }
		)
	end
	return out
end

-- The sections of rotation `slot`. Inside one chain of CHAIN_SLOTS rotations no idea of a course comes back in the
-- next one; the first course of a chain starts fresh.
function ObbyCourse.pick(slot: number): { Pick }
	local anchor = slot - slot % OBBY.CHAIN_SLOTS
	local picks = rawPick(anchor, {})
	for s = anchor + 1, slot do
		local avoid = {}
		for _, p in picks do
			avoid[p.id] = true
		end
		picks = rawPick(s, avoid)
	end
	return picks
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function slab(
	x: number,
	top: number,
	z: number,
	sx: number,
	sz: number,
	look: string,
	extra: { [string]: any }?
): Part
	return Kit.slab(x, top, z, sx, sz, look, extra)
end

local function offset(part: Part, dx: number, dy: number): Part
	local moved = table.clone(part)
	moved.pos = { part.pos[1] + dx, part.pos[2] + dy, part.pos[3] }
	return moved
end

-- A section's first and last steps (the walking path's ends).
local function firstStep(section: Section): Part
	for _, part in section.parts do
		if part.step then
			return part
		end
	end
	error("obby section without steps")
end

local function lastStep(section: Section): Part
	for i = #section.parts, 1, -1 do
		if section.parts[i].step then
			return section.parts[i]
		end
	end
	error("obby section without steps")
end

-- Smallest and largest of `axis` (1 = x, 2 = y, 3 = z) over a path motion's points (the rest point included).
local function pathRange(motion: Motion, axis: number): (number, number)
	local lo, hi = 0, 0
	local points: { Vec } = motion.points or {}
	for _, p in points do
		lo, hi = math.min(lo, p[axis]), math.max(hi, p[axis])
	end
	return lo, hi
end

-- Half the footprint a part sweeps when it turns round its vertical axis.
local function turnRadius(part: Part): number
	return math.max(part.size[1], part.size[3]) / 2
end

-- The z range (across the course) a step can cover: rotated footprint plus how far it moves or turns.
local function acrossOf(part: Part): (number, number)
	local _, _, _, _, lo, hi = Kit.bounds(part)
	local motion = part.motion
	if motion then
		local kind = motion.kind
		if kind == "spin" or kind == "sweep" then
			local r = turnRadius(part)
			lo, hi = math.min(lo, part.pos[3] - r), math.max(hi, part.pos[3] + r)
		elseif kind == "slide" and motion.axis == "z" then
			local amp = math.abs(motion.amp or 0)
			lo, hi = lo - amp, hi + amp
		elseif kind == "path" then
			local a, b = pathRange(motion, 3)
			lo, hi = lo + a, hi + b
		end
	end
	return lo, hi
end

-- Looks a runner can't stand on: obstacles that hit, swing or punch. Ghost parts have no collision at all.
local NOT_FLOOR = table.freeze({ bar = true, blob = true, puncher = true, gate = true, wave = true, hazard = true })

-- True for a part a falling runner could land on: solid, not a hazard, zone, key, gate or rope end. Melting tiles and
-- collapsing pieces still count (they are there until they go).
local function isFloor(part: Part): boolean
	return not part.ghost
		and not part.hazard
		and part.zone == nil
		and part.key == nil
		and part.gate == nil
		and part.vine == nil
		and not NOT_FLOOR[part.look]
end

-- The platforms a falling runner could land on, with the lowest their top gets while they move.
local function floorsOf(parts: { Part }): { Floor }
	local out: { Floor } = {}
	for _, part in parts do
		if isFloor(part) then
			local from, to = Kit.bounds(part)
			local top = math.huge
			for _, c in Kit.topCorners(part) do
				top = math.min(top, c[2])
			end
			local motion = part.motion
			if motion then
				local kind = motion.kind
				local amp = math.abs(motion.amp or 0)
				if kind == "spin" or kind == "sweep" then
					local r = turnRadius(part)
					from, to = math.min(from, part.pos[1] - r), math.max(to, part.pos[1] + r)
				elseif kind == "slide" and motion.axis == "x" then
					from, to = from - amp, to + amp
				elseif kind == "slide" and motion.axis == "y" then
					top -= amp
				elseif kind == "rock" then
					top -= part.size[1] / 2 * math.sin(math.rad(amp))
				elseif kind == "path" then
					local a, b = pathRange(motion, 1)
					from, to = from + a, to + b
					top += math.min(0, (pathRange(motion, 2)))
				elseif kind == "sink" then
					top -= math.abs(motion.depth or 0)
				end
			end
			table.insert(out, { from = from, to = to, top = top })
		end
	end
	return out
end

ObbyCourse.floorsOf = floorsOf -- for the specs

-- One section, in section-local coordinates: idea `id`, variant index (0 = the idea's generator, built for `tier`)
-- and seed.
function ObbyCourse.section(id: string, variant: number, seed: number, tier: string?): Section
	local idea = ObbySections.byId[id]
	assert(idea, `unknown obby section {id}`)
	local s = math.max(1, math.floor(seed))
	if variant == 0 then
		local gen = idea.generator
		assert(gen, `obby section {id} has no generator`)
		return gen.build(s, if tier and table.find(gen.tiers, tier) then tier else gen.tiers[1])
	end
	local v = idea.variants[math.clamp(math.floor(variant), 1, #idea.variants)]
	return v.build(s)
end

-- Lays out `picks` (default: the sections of `slot`).
function ObbyCourse.build(slot: number, picks: { Pick }?): Course
	local chosen = picks or ObbyCourse.pick(slot)
	local W, S = ObbyCourse.WIDTH, ObbyCourse.STAND_HEIGHT
	local H = ObbyCourse.HOME_LENGTH
	local parts: { Part } = {
		slab(ObbyCourse.START_LENGTH / 2, 0, 0, ObbyCourse.START_LENGTH, W, "start", { id = "s" }),
		slab(-H / 2, 0, 0, H, ObbyCourse.HOME_WIDTH, "start", { step = false, id = "h" }),
	}
	local spans: { Span } = {}
	local x, y = ObbyCourse.START_LENGTH, 0
	local sections = {}
	for i, pick in chosen do
		sections[i] = ObbyCourse.section(pick.id, pick.variant, pick.seed, pick.tier)
	end
	for i, section in sections do
		local from, entry = x, y
		for index, part in section.parts do
			local moved = offset(part, x, y)
			moved.id = `{i}.{index}`
			local motion = part.motion
			if motion and motion.next then
				local remapped = table.clone(motion)
				local ids = {}
				for _, n in motion.next do
					table.insert(ids, if type(n) == "number" then `{i}.{n}` else n)
				end
				remapped.next = ids
				moved.motion = remapped
			end
			table.insert(parts, moved)
		end
		x += section.length
		y += section.rise
		local nextSection = sections[i + 1]
		if nextSection then
			local L = ObbyCourse.LINK_LENGTH
			local lo, hi = acrossOf(lastStep(section))
			local nlo, nhi = acrossOf(firstStep(nextSection))
			lo, hi = math.min(lo, nlo) - ObbyCourse.LINK_MARGIN, math.max(hi, nhi) + ObbyCourse.LINK_MARGIN
			local grow = math.max(0, ObbyCourse.LINK_MIN_WIDTH - (hi - lo)) / 2
			lo, hi = math.max(lo - grow, -W / 2), math.min(hi + grow, W / 2)
			local tone = (i - 1) % 3 + 1
			table.insert(
				parts,
				slab(x + L / 2, y, (lo + hi) / 2, L, hi - lo, "jelly", { tone = tone, link = true, id = `l{i}` })
			)
			x += L
		end
		table.insert(spans, { index = i, from = from, to = x, floor = math.min(entry, y) })
	end
	local depth = ObbyCourse.FINISH_LENGTH
	table.insert(parts, slab(x + depth / 2, y, 0, depth, W, "finish", { id = "f" }))
	local finish = { pos = { x + depth / 2, y, 0 }, size = { depth, S, W } }
	x += depth
	return {
		slot = slot,
		picks = chosen,
		parts = parts,
		floors = floorsOf(parts),
		start = { ObbyCourse.START_LENGTH / 3, OBBY.RESPAWN_LIFT, 0 },
		startTop = 0,
		home = { pos = { -ObbyCourse.HOME_BACK, 0, 0 }, radius = ObbyCourse.HOME_RADIUS },
		spans = spans,
		finish = finish,
		length = x,
	}
end

-- True when course-local `p` (a root position) has walked into the Goo Ring home.
function ObbyCourse.inHome(course: Course, p: Vec): boolean
	local ring = course.home
	local dx, dz = p[1] - ring.pos[1], p[3] - ring.pos[3]
	local dy = p[2] - ring.pos[2]
	return dx * dx + dz * dz <= ring.radius * ring.radius and dy >= -1 and dy <= ObbyCourse.STAND_HEIGHT
end

-- True when course-local `p` stands on the finish pad (over it, up to STAND_HEIGHT above its top).
function ObbyCourse.onFinish(course: Course, p: Vec): boolean
	local zone = course.finish
	return math.abs(p[1] - zone.pos[1]) <= zone.size[1] / 2
		and math.abs(p[3] - zone.pos[3]) <= zone.size[3] / 2
		and p[2] >= zone.pos[2] - 1
		and p[2] <= zone.pos[2] + zone.size[2]
end

-- Which part of the course course-local `p` is over: 0 = the start pad (or before it), i = section i (with the
-- connector after it), #spans + 1 = the finish pad (or past it).
function ObbyCourse.sectionAt(course: Course, p: Vec): number
	local x = p[1]
	for _, span in course.spans do
		if x < span.from then
			return span.index - 1
		elseif x < span.to then
			return span.index
		end
	end
	return #course.spans + 1
end

-- The lowest platform top a runner at course-local `p` could still land on: every floor within FALL_REACH of it
-- along the course (the section's floor if none is).
function ObbyCourse.lowestFloor(course: Course, p: Vec): number
	local x, reach = p[1], ObbyCourse.FALL_REACH
	local low = math.huge
	for _, floor in course.floors do
		if floor.to >= x - reach and floor.from <= x + reach and floor.top < low then
			low = floor.top
		end
	end
	if low < math.huge then
		return low
	end
	local index = ObbyCourse.sectionAt(course, p)
	local span = course.spans[index]
	return if span then span.floor elseif index <= 0 then course.startTop else course.finish.pos[2]
end

-- A runner (root part) at course-local `p` has fallen once it is below this height: `depth` (default
-- OBBY.FALL_DEPTH) under the lowest platform it could still land on.
function ObbyCourse.fallHeight(course: Course, p: Vec, depth: number?): number
	return ObbyCourse.lowestFloor(course, p) - (depth or OBBY.FALL_DEPTH)
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function axes(frame: Frame): (number, number)
	local a = math.rad(frame.yaw)
	return math.sin(a), math.cos(a)
end

-- Course-local point -> world.
function ObbyCourse.toWorld(frame: Frame, p: Vec): Vec
	local fx, fz = axes(frame)
	local o = frame.origin
	-- right = forward x up = (-fz, 0, fx)
	return { o[1] + fx * p[1] - fz * p[3], o[2] + p[2], o[3] + fz * p[1] + fx * p[3] }
end

-- World point -> course-local.
function ObbyCourse.toLocal(frame: Frame, p: Vec): Vec
	local fx, fz = axes(frame)
	local o = frame.origin
	local dx, dz = p[1] - o[1], p[3] - o[3]
	return { dx * fx + dz * fz, p[2] - o[2], -dx * fz + dz * fx }
end

-- Display name of idea `id` (shown on the run card and in analytics).
function ObbyCourse.nameOf(id: string): string
	return ObbySections.nameOf(id)
end

-- Display names of a course's sections, in order.
function ObbyCourse.names(picks: { Pick }): { string }
	local out = {}
	for _, p in picks do
		table.insert(out, ObbySections.nameOf(p.id))
	end
	return out
end

return table.freeze(ObbyCourse)
