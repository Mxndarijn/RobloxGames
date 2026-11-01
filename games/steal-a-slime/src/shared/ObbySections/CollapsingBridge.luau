--!strict
--[[
	Collapsing Bridge (obby idea 24, docs/obby-variants/24.json; contract/obby-sections.md)

	A plank bridge that falls away behind you: stepping on the first plank (the one with the painted crack) starts a
	per-player clock, and every plank then cracks and drops (`drop` on that `start` clock) on a wave that follows the
	walking path. Keep moving and jump every gap or the wave takes you. Later variants bend the bridge, fork it, add
	stone rest islands, goo puddles, boost planks, a wave that speeds up, and planks ahead that drop early.

	Wave timing: a plank's drop time is head + (time the wave front needs to reach its centre along the path). The
	wave speed is a curve over path distance. `head` is not hand-set: it is solved so the runner of ObbyCheck.timers
	(16 studs/s, 0.15 s lost per jump, here also 0.3 s per turn) leaves the tightest plank exactly SPARE[tier]
	seconds before it drops. That keeps every tier honest whatever the layout (contract §10): easy leaves about 1.6 s,
	medium 1.25 s, hard 1.05 s at the tightest plank (the check needs 1 s, measured by a laxer runner).

	Every variant opens with a 5-stud jump from the entry pad onto the bridge and has holes of at least 4.5 studs on
	the bridge itself, so walking forward never clears it (contract §9: the walker steps over a 4-stud hole), and ends
	on a solid exit ledge that never drops.

	Kit simplifications (see the engine gaps in the build summary): a rest island does not pause the wave while you
	stand on it; it is a grey pad that drops `pause` seconds after the wave reaches it, and the next stretch has its
	own trigger on its first plank. The left half of Two Halves and the early holes of Holes Ahead are plain solid
	parts (not steps) on the same clock.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part

local ENTRY_LONG = 8 -- the entry pad (full lane width)
local ENTRY_GAP = 5 -- the jump onto the bridge: too long to walk over (ObbyCheck.walkStop needs 4.4)
local HOLE = 4.5 -- the shortest hole on the bridge a walker can't step over
local FROM = ENTRY_LONG + ENTRY_GAP -- where the bridge starts
local WIDE = 10 -- bridge width across the lane
local EXIT_LONG = 6

local TURN = 0.3 -- seconds the runner loses on every turn (stricter than ObbyCheck.timers)
-- Seconds the runner leaves the tightest plank early. Since every plank is on one clock, this is also the whole
-- section's delay budget: dawdle that long anywhere and the wave has you somewhere further on.
local SPARE = { easy = 1.6, medium = 1.25, hard = 1.05 }
local EARLY = 0.5 -- an early hole is open this long before a 16-stud/s walker gets there

local function topOf(p: Part): number
	return p.pos[2] + p.size[2] / 2
end

-- Edge gap between two unturned footprints, seen from above (0 when they touch).
local function gapOf(a: Part, b: Part): number
	local ax0, ax1 = a.pos[1] - a.size[1] / 2, a.pos[1] + a.size[1] / 2
	local az0, az1 = a.pos[3] - a.size[3] / 2, a.pos[3] + a.size[3] / 2
	local bx0, bx1 = b.pos[1] - b.size[1] / 2, b.pos[1] + b.size[1] / 2
	local bz0, bz1 = b.pos[3] - b.size[3] / 2, b.pos[3] + b.size[3] / 2
	local dx = math.max(0, bx0 - ax1, ax0 - bx1)
	local dz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	The runner along `steps` (walking order, the first one the trigger): path distance of every centre from the
	first, and when the runner leaves each one (as ObbyCheck.timers: centre distance / 16, 0.15 s a jump, half the
	plank's length to walk off it, plus TURN a turn).
]]
local function runner(steps: { Part }): ({ number }, { number })
	local dist, leave = {}, {}
	local at, d = 0, 0
	local dirX: number?, dirZ: number? = nil, nil
	for k, s in steps do
		if k > 1 then
			local p = steps[k - 1]
			local dx, dz = s.pos[1] - p.pos[1], s.pos[3] - p.pos[3]
			local len = math.sqrt(dx * dx + dz * dz)
			local jump = gapOf(p, s) > 0.5 or math.abs(topOf(s) - topOf(p)) > 0.5
			at += len / Kit.WALK + (if jump then Kit.JUMP_LOSS else 0)
			if len > 0 then
				if dirX and dirZ and (dirX * dx + dirZ * dz) / len < 0.87 then
					at += TURN
				end
				dirX, dirZ = dx / len, dz / len
			end
			d += len
		end
		dist[k] = d
		leave[k] = at + s.size[1] / 2 / Kit.WALK
	end
	return dist, leave
end

-- A wave speed curve: studs / s at path distance `d` of `total`.
type Speed = (d: number, total: number) -> number

local function steady(v: number): Speed
	return function(_d: number, _total: number): number
		return v
	end
end

-- From `v0` to `v1`, rising evenly from `from` (share of the path) to the end.
local function rising(v0: number, v1: number, from: number?): Speed
	local f0 = from or 0
	return function(d: number, total: number): number
		local f = if total > 0 then d / total else 0
		if f <= f0 then
			return v0
		end
		return v0 + (v1 - v0) * math.min((f - f0) / math.max(1 - f0, 1e-6), 1)
	end
end

-- Seconds the wave front needs to travel `d` studs along the path (numeric, deterministic).
local function travel(speed: Speed, d: number, total: number): number
	local t, s, h = 0, 0, 0.25
	while s < d - 1e-9 do
		local step = math.min(h, d - s)
		t += step / speed(s + step / 2, total)
		s += step
	end
	return t
end

export type WaveOpts = {
	group: string, -- the start group (trigger on the first step)
	speed: Speed,
	tier: string,
	pause: { [number]: number }?, -- step index -> extra seconds that piece stays (rest islands)
}

-- Puts the collapse on `steps` (walking order): the first is the trigger with the painted crack, every one drops on
-- the wave. Returns each step's drop time.
local function wave(steps: { Part }, o: WaveOpts): { number }
	local dist, leave = runner(steps)
	local total = dist[#dist]
	local raw = {}
	local head = -math.huge
	for k in steps do
		raw[k] = travel(o.speed, dist[k], total) + (if o.pause then o.pause[k] or 0 else 0)
		head = math.max(head, leave[k] + SPARE[o.tier] - raw[k])
	end
	local times = {}
	for k, s in steps do
		local at = math.floor((head + raw[k]) * 100 + 0.5) / 100 + 0.01 -- rounded up a hair, never under the spare
		times[k] = at
		s.start = o.group
		s.motion = { kind = "drop", at = at }
	end
	steps[1].trigger = o.group
	steps[1].marker = steps[1].marker or "cracks"
	return times
end

-- The entry pad (x 0..8) before the 4-stud jump onto the bridge.
local function entry(parts: { Part })
	table.insert(parts, Kit.slab(ENTRY_LONG / 2, 0, 0, ENTRY_LONG, Kit.WIDTH, "jelly", { tone = 1 }))
end

-- A plank from x0, `long` along x, `wide` across, centred on z, top `top`.
local function plank(x0: number, long: number, top: number, z: number, wide: number, tone: number): Part
	return Kit.slab(x0 + long / 2, top, z, long, wide, "plank", { tone = tone })
end

-- `n` planks from x0, `long` each with `gap` between, appended to `parts`; returns them and the x after the last.
local function planks(
	parts: { Part },
	x0: number,
	n: number,
	long: number,
	gap: number,
	z: number?,
	wide: number?
): ({ Part }, number)
	local out = {}
	local x = x0
	for i = 1, n do
		if i > 1 then
			x += gap
		end
		local p = plank(x, long, 0, z or 0, wide or WIDE, 1 + i % 2)
		table.insert(parts, p)
		table.insert(out, p)
		x += long
	end
	return out, x
end

-- The solid exit ledge from x0 to x1 (top `top`, centred on z): the section's last step, it never drops.
local function exit(parts: { Part }, x0: number, x1: number, top: number?, z: number?, wide: number?)
	table.insert(parts, Kit.slab((x0 + x1) / 2, top or 0, z or 0, x1 - x0, wide or Kit.WIDTH, "jelly", { tone = 3 }))
end

-- A grey stone rest island from x0 (`long` x WIDE).
local function island(x0: number, long: number): Part
	return Kit.slab(x0 + long / 2, 0, 0, long, WIDE, "pad", { marker = "sign:REST" })
end

local function append(list: { Part }, more: { Part })
	for _, p in more do
		table.insert(list, p)
	end
end

local M = {}
M.id = "CollapsingBridge"
M.name = "Collapsing Bridge"
M.idea = 24

M.variants = {
	{
		-- A flat, straight bridge with one hole halfway: learn that it falls behind you, keep going and jump the hole.
		name = "First Crumble",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge, x = planks(parts, FROM, 5, 6, 0)
			local rest
			rest, x = planks(parts, x + ENTRY_GAP, 6, 6, 0)
			append(bridge, rest)
			wave(bridge, { group = "crumble", speed = steady(14), tier = "easy" })
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- Small gaps and planks that step up and down: hop every one without stopping while the wave chases you.
		name = "Little Hops",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge = {}
			local x = FROM
			for i = 1, 8 do
				if i > 1 then
					x += 3.5
				end
				local p = plank(x, 6, if i % 2 == 0 then 1.5 else 0, 0, WIDE, 1 + i % 2)
				table.insert(parts, p)
				table.insert(bridge, p)
				x += 6
			end
			wave(bridge, { group = "hops", speed = steady(14), tier = "easy" })
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- A stone rest island halfway: it holds 2 s longer than the planks, then the second half starts its own wave
		-- when you jump onto it.
		name = "Catch Your Breath",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local first, x = planks(parts, FROM, 4, 5, HOLE)
			x += HOLE
			local rest = island(x, 10)
			table.insert(parts, rest)
			x += 10 + HOLE
			local second
			second, x = planks(parts, x, 4, 5, HOLE)
			local leg1 = table.clone(first)
			table.insert(leg1, rest)
			wave(leg1, { group = "breath1", speed = steady(13), tier = "easy", pause = { [#leg1] = 2 } })
			wave(second, { group = "breath2", speed = steady(14), tier = "easy" })
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- One right-angle turn: the bridge runs down the left side, turns right across the lane and the exit ledge
		-- leaves from the right. The wave follows you round; a wall at the corner shows the turn.
		name = "Corner",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local zLeft = -Kit.HALF + WIDE / 2 -- the left leg's centre (z -12..-2)
			local leg, x = planks(parts, FROM, 5, 6, 0, zLeft)
			local corner = plank(x, WIDE, 0, zLeft, WIDE, 1)
			table.insert(parts, corner)
			local across = Kit.slab(x + WIDE / 2, 0, 1.5, WIDE, 7, "plank", { tone = 2 }) -- z -2..5
			table.insert(parts, across)
			local steps = table.clone(leg)
			append(steps, { corner, across })
			wave(steps, { group = "corner", speed = steady(14), tier = "easy" })
			table.insert(parts, Kit.wall(x + WIDE + 0.5, zLeft, WIDE, nil, false, { tone = 2 }))
			local length = x + WIDE + 4
			exit(parts, x, length, 0, (5 + Kit.HALF) / 2, Kit.HALF - 5) -- z 5..12, reaching the section end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Only four long slabs, each dropping as one big chunk, and they zigzag left and right: jump sideways too.
		name = "Big Chunks",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge = {}
			local x = FROM
			for i = 1, 4 do
				if i > 1 then
					x += ENTRY_GAP
				end
				local p = plank(x, 14, 0, if i % 2 == 1 then -5 else 5, WIDE, 1 + i % 2)
				table.insert(parts, p)
				table.insert(bridge, p)
				x += 14
			end
			wave(bridge, { group = "chunks", speed = steady(14), tier = "easy" })
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- Every row of the bridge is two halves with a hole before it; one half of each row cracks and falls before
		-- you get there. Read the cracks ahead and jump to the safe side while the wave eats the halves you used.
		name = "Two Halves",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local half = Kit.HALF
			local lead = plank(FROM, 6, 0, 0, Kit.WIDTH, 1)
			table.insert(parts, lead)
			local steps, early = { lead }, {}
			local x = FROM + 6
			for i, side in { 1, 1, -1, -1, -1, 1, 1, -1 } do
				x += HOLE
				local safe = plank(x, 6, 0, side * half / 2, half, 1 + i % 2)
				local gone = plank(x, 6, 0, -side * half / 2, half, 1 + (i + 1) % 2)
				gone.step = nil -- not the path: it falls ahead of you
				table.insert(parts, safe)
				table.insert(parts, gone)
				table.insert(steps, safe)
				table.insert(early, gone)
				x += 6
			end
			wave(steps, { group = "halves", speed = steady(14), tier = "easy" })
			local x0 = lead.pos[1] - lead.size[1] / 2
			for _, e in early do
				local reach = (e.pos[1] - e.size[1] / 2 - x0) / Kit.WALK
				e.start = "halves"
				e.motion = { kind = "drop", at = math.max(math.floor((reach - EARLY) * 100) / 100, 0.9) }
			end
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- The wave starts slow and speeds up as it goes: a calm start, a sprint at the end.
		name = "Speeding Up",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge, x = planks(parts, FROM, 11, 4, HOLE)
			wave(bridge, { group = "faster", speed = rising(13, 21), tier = "medium" })
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- The bridge snakes: down the left, across to the right, down the right, back across to the left exit. Three
		-- turns and a wave that never lets you slow down.
		name = "S-Bend",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local zL, zR = -Kit.HALF + WIDE / 2, Kit.HALF - WIDE / 2
			local steps = {}
			local legA, x = planks(parts, FROM, 4, 5, 0, zL)
			append(steps, legA)
			-- across to the right: four pieces 6 deep, x .. x + WIDE
			for i, zc in { -9, -3, 3, 9 } do
				local p = Kit.slab(x + WIDE / 2, 0, zc, WIDE, 6, "plank", { tone = 1 + i % 2 })
				table.insert(parts, p)
				table.insert(steps, p)
			end
			x += WIDE
			local legC
			legC, x = planks(parts, x, 4, 5, 0, zR)
			append(steps, legC)
			-- back across to the left: three pieces, then the exit ledge on the left
			for i, zc in { 9, 3, -3 } do
				local p = Kit.slab(x + WIDE / 2, 0, zc, WIDE, 6, "plank", { tone = 1 + i % 2 })
				table.insert(parts, p)
				table.insert(steps, p)
			end
			wave(steps, { group = "bend", speed = steady(15), tier = "medium" })
			local length = x + WIDE + 4
			exit(parts, x, length, 0, -9, 6)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The bridge drops down in 3-stud ledges with wide gaps: land and go at once, the wave is fast.
		name = "Downhill Drops",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local steps = {}
			local x, long, gap, down = FROM, 7, 5.5, 3
			for i = 1, 7 do
				local p = plank(x, long, -(i - 1) * down, 0, WIDE, 1 + i % 2)
				table.insert(parts, p)
				table.insert(steps, p)
				x += long + (if i < 7 then gap else 0)
			end
			wave(steps, { group = "downhill", speed = steady(16), tier = "medium" })
			local rise = -6 * down
			exit(parts, x, x + EXIT_LONG, rise)
			return Kit.section(x + EXIT_LONG, rise, parts)
		end,
	},
	{
		-- Some planks carry a red goo puddle covering most of their width: hop it or squeeze past, at speed.
		name = "Goo Spots",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge, x = planks(parts, FROM, 12, 5, 2.5)
			local times = wave(bridge, { group = "goo", speed = steady(15), tier = "medium" })
			for n, i in { 2, 4, 6, 8, 10, 12 } do
				local p = bridge[i]
				local side = if n % 2 == 1 then -1 else 1
				table.insert(
					parts,
					Kit.hazard({ 3.5, 0.5, 7 }, { p.pos[1], topOf(p) + 0.2, side * 1.5 }, {
						start = "goo",
						motion = { kind = "drop", at = times[i] },
					})
				)
			end
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- Three runs split by two rest islands; every run's wave is faster than the last.
		name = "Two Breathers",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local x = FROM
			for leg, v in { 13, 15, 17 } do
				local run
				run, x = planks(parts, x, 3, 4, HOLE)
				local steps = table.clone(run)
				local pause: { [number]: number } = {}
				if leg < 3 then
					x += 2
					local rest = island(x, 6)
					table.insert(parts, rest)
					table.insert(steps, rest)
					pause[#steps] = 2
					x += 6 + 2
				end
				wave(steps, { group = `leg{leg}`, speed = steady(v), tier = "medium", pause = pause })
			end
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- Few planks with full 6-stud gaps (the jump limit) and a wave right behind you: no jump may come up short.
		name = "Long Leaps",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge, x = planks(parts, FROM, 6, 6, 6)
			wave(bridge, { group = "leaps", speed = steady(16), tier = "hard" })
			x += 6
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- Past plank 6 the wave speeds up past your walk; the yellow boost plank carries you over the 9-stud gap to the
		-- exit.
		name = "Boost Plank",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge, x = planks(parts, FROM, 6, 5, 3)
			x += 3
			local boost = Kit.slab(x + 5, 0, 0, 10, WIDE, "boost", {
				boost = { speed = 26, carry = 2 },
				marker = "chevrons",
			})
			table.insert(parts, boost)
			x += 10
			local steps = table.clone(bridge)
			table.insert(steps, boost)
			local fast = steps[6].pos[1] - steps[1].pos[1]
			wave(steps, {
				group = "boost",
				tier = "medium",
				speed = function(d: number, _total: number): number
					return if d < fast then 14 else 20
				end,
			})
			x += 9
			exit(parts, x, x + 8)
			return Kit.section(x + 8, 0, parts)
		end,
	},
	{
		-- The bridge forks at a wide pad: the right branch is three planks with 5.5-stud leaps, the left four planks
		-- with 4.8-stud hops. Each branch starts its own wave on its first plank, so it follows whichever one you take.
		name = "Split Bridge",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local lead = plank(FROM, 6, 0, 0, WIDE, 1)
			table.insert(parts, lead)
			local fork = Kit.slab(FROM + 6 + 2 + 4, 0, 0, 8, Kit.WIDTH, "plank", { tone = 2 })
			table.insert(parts, fork)
			wave({ lead, fork }, { group = "split", speed = steady(15), tier = "medium" })
			local from, to = FROM + 16, FROM + 56
			local zL, zR = -Kit.HALF + WIDE / 2, Kit.HALF - WIDE / 2
			-- left (main): 4 planks 4 long, five 4.8-stud hops (the last onto the exit)
			local left = {}
			local x = from
			local hop = (to - from - 4 * 4) / 5
			for i = 1, 4 do
				x += hop
				local p = plank(x, 4, 0, zL, WIDE, 1 + i % 2)
				table.insert(parts, p)
				table.insert(left, p)
				x += 4
			end
			-- right (route "short"): 3 planks 6 long, 5.5-stud leaps
			local right = {}
			x = from
			for i = 1, 3 do
				x += 5.5
				local p = plank(x, 6, 0, zR, WIDE, 1 + i % 2)
				p.route = "short"
				table.insert(parts, p)
				table.insert(right, p)
				x += 6
			end
			right[1].marker = "sign:SHORT"
			wave(left, { group = "left", speed = steady(15), tier = "medium" })
			wave(right, { group = "right", speed = steady(15), tier = "medium" })
			exit(parts, to, to + 8)
			return Kit.section(to + 8, 0, parts)
		end,
	},
	{
		-- A long bridge, a fast wave and no rest: any pause or a mistimed jump and it catches you.
		name = "Sprint",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge, x = planks(parts, FROM, 11, 4, HOLE)
			wave(bridge, { group = "sprint", speed = steady(17), tier = "hard" })
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- Besides the wave behind you, four planks ahead crack and drop early on the same clock: read the cracks in
		-- front and jump the new 5-stud holes.
		name = "Holes Ahead",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			-- P = plank (a step), E = early drop, g = 2-stud gap
			local layout = string.split("PgPgPgPEPgPEPgPEPgPEP", "")
			local steps: { Part }, early: { Part } = {}, {}
			local x, tone = FROM, 1
			for _, kind in layout do
				if kind == "g" then
					x += 2
				else
					tone = 3 - tone
					local p = plank(x, 5, 0, 0, WIDE, tone)
					table.insert(parts, p)
					table.insert(if kind == "P" then steps else early, p)
					x += 5
				end
			end
			wave(steps, { group = "holes", speed = steady(16), tier = "hard" })
			local x0 = steps[1].pos[1] - steps[1].size[1] / 2
			for _, e in early do
				local ex0 = e.pos[1] - e.size[1] / 2
				e.step = nil -- not the path: it is gone before you get there
				e.start = "holes"
				e.motion = { kind = "drop", at = math.floor(((ex0 - x0) / Kit.WALK - EARLY) * 100) / 100 }
			end
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
	{
		-- Calm for two thirds, then the wave speeds up hard and the bridge ends in a full 6-stud jump to the exit.
		name = "Final Dash",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local bridge, x = planks(parts, FROM, 12, 4, 3)
			wave(bridge, { group = "dash", speed = rising(13, 22, 0.55), tier = "hard" })
			x += 6
			exit(parts, x, x + 8)
			return Kit.section(x + 8, 0, parts)
		end,
	},
	{
		-- The wave runs faster than you walk: every plank is a yellow boost plank, and the gaps between them are too long
		-- to clear without the speed.
		name = "Boost or Bust",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local steps = {}
			local x = FROM
			for i = 1, 4 do
				if i > 1 then
					x += 7
				end
				local p = Kit.slab(x + 5, 0, 0, 10, WIDE, "boost", {
					boost = { speed = 24, carry = 1.5 },
					marker = "chevrons",
					tone = 1,
				})
				table.insert(parts, p)
				table.insert(steps, p)
				x += 10
			end
			wave(steps, { group = "bust", speed = steady(21), tier = "hard" })
			x += 7
			exit(parts, x, x + EXIT_LONG)
			return Kit.section(x + EXIT_LONG, 0, parts)
		end,
	},
}

return M
