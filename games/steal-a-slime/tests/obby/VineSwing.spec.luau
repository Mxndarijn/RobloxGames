--!strict
-- Vine Swing (obby idea 15): every variant through ObbyCheck, plus the rope windows the shared checks don't size:
-- for every pair of steps where a rope moves, the longest stretch the grab (or the release, or the reach into a
-- ladder) works must sit in the tier's band (contract §10). The rules are the same as tests/ObbyCheck's makeable
-- (grab: knob within GAP_MAX + reach; release: the rope end's speed plus a 20 up kick lands within steering reach),
-- measured at real times only (never the at-rest pose).
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local VineSwing = require("../../src/shared/ObbySections/VineSwing")

-- Release windows a tier earns (contract §10): at least `lo` seconds on every timed hand-over, at most `hi`.
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}

local HORIZON = 60 -- seconds looked at (a multiple of every period used)
local DT = 0.01

type Part = Kit.Part

-- Where a part's centre is at time t, and its top / bottom.
local function poseAt(p: Part, t: number): (number, number, number)
	local dx, dy, dz = Kit.offsetAt(p, t)
	return p.pos[1] + dx, p.pos[2] + dy, p.pos[3] + dz
end

-- Distance from (x, z) to a part's footprint (axis-aligned box) centred on (cx, cz).
local function pointGap(x: number, z: number, p: Part, cx: number, cz: number): number
	local gx = math.max(math.abs(x - cx) - p.size[1] / 2, 0)
	local gz = math.max(math.abs(z - cz) - p.size[3] / 2, 0)
	return math.sqrt(gx * gx + gz * gz)
end

local function boxGap(a: Part, ax: number, az: number, b: Part, bx: number, bz: number): number
	local gx = math.max(math.abs(ax - bx) - (a.size[1] + b.size[1]) / 2, 0)
	local gz = math.max(math.abs(az - bz) - (a.size[3] + b.size[3]) / 2, 0)
	return math.sqrt(gx * gx + gz * gz)
end

local function fallTime(vy: number, dy: number): number?
	local disc = vy * vy + 2 * Kit.GRAVITY * dy
	if disc < 0 then
		return nil
	end
	return (vy + math.sqrt(disc)) / Kit.GRAVITY
end

-- Can step b be reached from step a at time t (the ObbyCheck rules for ropes and ladders)?
local function okAt(a: Part, b: Part, t: number): boolean
	local ax, ay, az = poseAt(a, t)
	local bx, by, bz = poseAt(b, t)
	if b.vine then
		local reach = b.vine.reach
		local d = pointGap(bx, bz, a, ax, az)
		local up = (by - b.size[2] / 2) - (ay + a.size[2] / 2)
		return d <= Kit.GAP_MAX + reach and up >= -reach - 1 and up <= Kit.JUMP_HEIGHT + Kit.HEAD + reach
	elseif b.shape == "truss" then
		return boxGap(a, ax, az, b, bx, bz) <= 1.5
	elseif a.vine then
		local h = 0.01
		local x2, y2, z2 = poseAt(a, t + h)
		local vx, vy, vz = (x2 - ax) / h, (y2 - ay) / h, (z2 - az) / h
		local feet = ay - a.size[2] / 2 - 2
		local tl = fallTime(vy + ObbyCheck.VINE_UP, feet - (by + b.size[2] / 2))
		if not tl then
			return false
		end
		return pointGap(ax + vx * tl, az + vz * tl, b, bx, bz) <= Kit.WALK * tl * 0.5 + 0.5
	end
	return true
end

-- The longest stretch (s) over the horizon when b can be reached from a (HORIZON = always open).
local function windowOf(a: Part, b: Part): number
	local best, run = 0, 0
	for k = 0, math.floor(HORIZON / DT) do
		if okAt(a, b, k * DT) then
			run += DT
			best = math.max(best, run)
		else
			run = 0
		end
	end
	return best
end

local function steps(section: Kit.Section): { Part }
	local out = {}
	for _, p in section.parts do
		if p.step then
			table.insert(out, p)
		end
	end
	return out
end

-- Every hand-over that involves a rope: its window and whether it is timed (not always open).
local function windows(section: Kit.Section): { { index: number, window: number, timed: boolean } }
	local list = steps(section)
	local out = {}
	for i = 2, #list do
		local a, b = list[i - 1], list[i]
		if a.vine or b.vine or b.shape == "truss" then
			local w = windowOf(a, b)
			table.insert(out, { index = i, window = w, timed = w < HORIZON - 1 })
		end
	end
	return out
end

-- The finish time (s after the trigger) of a runner who takes the first good hand-over every time: ENTRY_WALK to
-- the entry pad's edge, FLIGHT in the air after every hand-over; the worst and best over server-clock offsets.
local ENTRY_WALK, FLIGHT = 0.625, 0.3
local function greedy(section: Kit.Section): (number, number)
	local list = steps(section)
	local worst, best = 0, math.huge
	for k = 0, 59 do
		local phi = k * 0.05
		local t = ENTRY_WALK
		for i = 2, #list do
			local give = t + HORIZON
			while not okAt(list[i - 1], list[i], phi + t) and t < give do
				t += DT
			end
			t += FLIGHT
		end
		worst, best = math.max(worst, t), math.min(best, t)
	end
	return worst, best
end

describe("VineSwing", function()
	it("every variant passes ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(VineSwing) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("keeps the variants in the design file's order", function()
		local names = {}
		for _, v in VineSwing.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ", ")).toBe(
			"First Swing, Two in Step, Rest Island, Long Lazy Vine, Swing Down, Side Swing, Three Vine Chain, "
				.. "Quick Vines, Narrow Landing, Vine Climb, Sliding Anchor, Over the Goo Bar, Zigzag Vines, "
				.. "Vine to Ladder, Five Vine Run, Drifting Beat, Pulling Anchors, Pinpoint Drop, Snapping Vine"
		)
	end)

	it("every rope hand-over is open for the tier's window, and no longer", function()
		local problems = {}
		for _, v in VineSwing.variants do
			local band = BAND[v.tier]
			local timed = 0
			for _, w in windows(v.build(1)) do
				local s = math.floor(w.window * 100 + 0.5) / 100
				if w.timed then
					timed += 1
					if w.window < band.lo - 1e-6 or w.window > band.hi + 1e-6 then
						table.insert(problems, `{v.name} ({v.tier}) step {w.index}: open {s} s ({band.lo}..{band.hi})`)
					end
				end
			end
			if timed == 0 then
				table.insert(problems, `{v.name}: no timed hand-over`)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("Snapping Vine's flood reaches a hanging player 1..2 s after the slowest first-chance run", function()
		local section = VineSwing.variants[19].build(1)
		local flood, lowest = nil, math.huge
		for _, p in section.parts do
			if p.motion and p.motion.kind == "rise" then
				flood = p
			elseif p.vine then
				lowest = math.min(lowest, p.pos[2] - p.size[2] / 2)
			end
		end
		assert(flood and flood.motion, "Snapping Vine has a flood")
		local m = flood.motion :: Kit.Motion
		local feet = lowest - 5.5 -- a hanging player's feet: ObbyMoves.HANG 2.5 under the knob, then the legs
		local restTop = flood.pos[2] + flood.size[2] / 2
		expect(restTop + (m.stop :: number) >= feet - 1e-6).toBe(true)
		local touch = (m.delay or 0) + (feet - restTop) / (m.speed :: number)
		local worst, best = greedy(section)
		expect(best < worst).toBe(true)
		expect(touch >= worst + 1 - 1e-6).toBe(true)
		expect(touch <= worst + 2 + 1e-6).toBe(true)
	end)
end)
