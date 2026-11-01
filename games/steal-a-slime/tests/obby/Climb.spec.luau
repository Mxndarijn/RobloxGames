--!strict
--[[
	Climb (obby idea 8): every variant through ObbyCheck, plus the climbing the shared checks don't model. ObbyCheck's
	fairness runner runs along the floor, so a drip falling down a ladder looks easy to it; here a climber goes up
	each ladder stretch at CLIMB studs / s and must not meet a drip anywhere on the way:

	  * drip windows: for every ladder stretch under a drip, the seconds you can set off and reach its top untouched
	    are at least ObbyCheck.WINDOW[tier], and the tightest stretch of a variant is at most MAX[tier] (§10: earned)
	  * crumbling ladders: you get off each piece at least CRUMBLE_SPARE s before it falls, climbing without a stop
	  * sliding ladders: they wait long enough to board and climb all the way while they stand still (whether a
	    moving TrussPart carries a climber is not known, so the window assumes it doesn't)

	CLIMB is an assumption (Humanoid climbing at about 0.7 x WalkSpeed); it is not measured in Studio.
]]

local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Climb = require("../../src/shared/ObbySections/Climb")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local process = require("@lune/process")

local DEBUG = process.env.CLIMB_DEBUG ~= nil -- CLIMB_DEBUG=1 prints every measured window

type Part = Kit.Part

local CLIMB = 11.2 -- studs / s up a truss
local STEP_OFF = 0.15 -- s to step off a ladder top
local HOP = 0.35 -- s to leap from one ladder into the next
local DT = 0.01
local MAX = { easy = 1.6, medium = 1.15, hard = 0.85 } -- tightest window per tier: near the bottom of §10 (reviewed)
local CRUMBLE_SPARE = 0.5

local function isTruss(p: Part): boolean
	return p.shape == "truss"
end

local function yRange(p: Part): (number, number)
	return p.pos[2] - p.size[2] / 2, p.pos[2] + p.size[2] / 2
end

local function topOf(p: Part): number
	local _, _, _, y1 = Kit.bounds(p)
	return y1
end

-- Horizontal gap between two parts' footprints at rest (axis-aligned, no turns in this idea).
local function gap(a: Part, b: Part): number
	local ax0, ax1, _, _, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, _, bz0, bz1 = Kit.bounds(b)
	local dx = math.max(0, math.max(ax0, bx0) - math.min(ax1, bx1))
	local dz = math.max(0, math.max(az0, bz0) - math.min(az1, bz1))
	return math.sqrt(dx * dx + dz * dz)
end

type Stretch = { pieces: { Part }, from: number, to: number }

-- Ladder stretches climbed in one go: trusses stacked on one column, split where a non-ladder step offers a rest.
local function stretches(section: Kit.Section): { Stretch }
	local steps, trusses = {}, {}
	for _, p in section.parts do
		if p.step then
			table.insert(if isTruss(p) then trusses else steps, p)
		end
	end
	local function restAt(p: Part, y: number): boolean
		for _, s in steps do
			if math.abs(topOf(s) - y) < 0.05 and gap(s, p) <= 2 then
				return true
			end
		end
		return false
	end
	table.sort(trusses, function(a, b)
		if a.pos[1] ~= b.pos[1] then
			return a.pos[1] < b.pos[1]
		elseif a.pos[3] ~= b.pos[3] then
			return a.pos[3] < b.pos[3]
		end
		return a.pos[2] < b.pos[2]
	end)
	local out: { Stretch } = {}
	local current: Stretch? = nil
	for _, p in trusses do
		local y0, y1 = yRange(p)
		local last = current and current.pieces[#current.pieces]
		if
			current
			and last
			and last.pos[1] == p.pos[1]
			and last.pos[3] == p.pos[3]
			and math.abs(select(2, yRange(last)) - y0) < 0.05
			and not restAt(last, y0)
		then
			table.insert(current.pieces, p)
			current.to = y1
		else
			-- You board at the top of the step you come from when that is above the ladder's foot (hanging ladders).
			local from = y0
			for _, s in steps do
				local top = topOf(s)
				if gap(s, p) <= 1.5 and top > from and top < y1 then
					from = top
				end
			end
			current = { pieces = { p }, from = from, to = y1 }
			table.insert(out, current :: Stretch)
		end
	end
	return out
end

-- Drips falling down `stretch`: hazards within reach of its column.
local function dripsOn(section: Kit.Section, stretch: Stretch): { Part }
	local out = {}
	local p = stretch.pieces[1]
	for _, h in section.parts do
		if h.hazard and h.motion and h.motion.kind == "path" then
			local d = math.sqrt((h.pos[1] - p.pos[1]) ^ 2 + (h.pos[3] - p.pos[3]) ^ 2)
			if d <= 1.6 then
				table.insert(out, h)
			end
		end
	end
	return out
end

-- Does a climber setting off at t0 from stretch.from meet any of `drips` before it is off the top?
local function hit(stretch: Stretch, drips: { Part }, t0: number): boolean
	local climb = (stretch.to - stretch.from) / CLIMB
	local t = t0
	while t <= t0 + climb + STEP_OFF do
		local feet = math.min(stretch.from + (t - t0) * CLIMB, stretch.to)
		for _, h in drips do
			local _, dy = Kit.offsetAt(h, t)
			local c, r = h.pos[2] + dy, h.size[2] / 2
			if c - r < feet + Kit.HEAD and c + r > feet then
				return true
			end
		end
		t += DT
	end
	return false
end

-- Longest run of start times (seconds) that climb `stretch` untouched.
local function window(stretch: Stretch, drips: { Part }): number
	local period = 0
	for _, h in drips do
		period = math.max(period, Kit.periodOf(h))
	end
	local best, run = 0, 0
	local t0 = 0
	while t0 < 3 * period do
		if hit(stretch, drips, t0) then
			run = 0
		else
			run += DT
			best = math.max(best, run)
		end
		t0 += DT
	end
	return best
end

local function build(i: number): Kit.Section
	return Climb.variants[i].build(1)
end

describe("Climb (idea 8)", function()
	it("every variant passes ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(Climb) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds every variant of the design file, in its order", function()
		local names = {}
		for _, v in Climb.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ", ")).toBe(table.concat({
			"First Rungs",
			"Pillar Steps",
			"Tower Spiral",
			"First Drip",
			"Rungs or Plain",
			"Drip Shaft",
			"Ladder Notches",
			"Sliding Ladder",
			"Leap and Grab",
			"Over the Edge",
			"Drip Rain Pillars",
			"Crumbling Rungs",
			"Drip Gauntlet",
			"Sliding Pair",
			"Hanging Ladders",
			"Leaning Tower Storm",
			"Crumble Gauntlet",
		}, ", "))
	end)

	it("every ladder is a real 2 x 2 truss with an even height", function()
		for i, v in Climb.variants do
			for _, p in build(i).parts do
				if isTruss(p) then
					local ok = p.size[1] == 2 and p.size[3] == 2 and p.size[2] % 2 == 0
					if not ok then
						error(`{v.name}: truss {p.size[1]} x {p.size[2]} x {p.size[3]}`)
					end
				end
			end
		end
	end)

	it("every drip on a ladder leaves a climbing window fit for its tier", function()
		local problems = {}
		for i, v in Climb.variants do
			local section = build(i)
			local tightest = math.huge
			for _, s in stretches(section) do
				local drips = dripsOn(section, s)
				-- a sliding ladder's drip is measured with its boarding window (below)
				local m = s.pieces[1].motion
				if #drips > 0 and not (m and m.kind == "path") then
					local w = window(s, drips)
					tightest = math.min(tightest, w)
					if DEBUG then
						print(`{v.name} [{v.tier}] climb {s.from}..{s.to}: {w} s`)
					end
					if w < ObbyCheck.WINDOW[v.tier] then
						table.insert(problems, `{v.name}: climb {s.from}..{s.to} open {w} s`)
					end
				end
			end
			if tightest < math.huge and tightest > MAX[v.tier] then
				table.insert(problems, `{v.name}: tightest climb open {tightest} s (too easy for {v.tier})`)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("the glob pillars' runs are open long enough and no longer than the tier allows", function()
		local section = build(11)
		local tightest = math.huge
		for _, w in ObbyCheck.windows(section) do
			tightest = math.min(tightest, w.slack)
		end
		if DEBUG then
			print(`Drip Rain Pillars glob window {tightest} s`)
		end
		expect(tightest >= ObbyCheck.WINDOW.medium).toBe(true)
		expect(tightest <= MAX.medium).toBe(true)
	end)

	it("crumbling pieces fall only after a non-stop climber is off them", function()
		local problems = {}
		local seen = 0
		for i, v in Climb.variants do
			local section = build(i)
			for _, s in stretches(section) do
				for k, p in s.pieces do
					local m = p.motion
					if m and m.kind == "drop" then
						seen += 1
						local _, y1 = yRange(p)
						-- its clock starts when the climber's head reaches the foot of the piece that triggers it (or at the
						-- start); it is left when the feet pass its top
						local touched = 0
						for _, q in s.pieces do
							if q.trigger and q.trigger == p.start then
								touched = math.max(0, (yRange(q) - Kit.HEAD - s.from) / CLIMB)
							end
						end
						local left = (y1 - s.from) / CLIMB + (if k == #s.pieces then STEP_OFF else 0)
						local spare = (m.at or 0) - (left - touched)
						if spare < CRUMBLE_SPARE then
							table.insert(problems, `{v.name}: piece {k} falls {spare} s after you leave it`)
						end
					end
				end
			end
		end
		expect(seen).toBe(7)
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("sliding ladders wait long enough to board and climb off while they stand still", function()
		for _, i in { 8, 14 } do
			local v = Climb.variants[i]
			local section = build(i)
			local movers, board, exit = {}, nil, nil
			for _, p in section.parts do
				if p.step then
					if isTruss(p) then
						table.insert(movers, p)
					elseif #movers == 0 then
						board = p
					else
						exit = p
					end
				end
			end
			assert(board and exit, "board and exit steps")
			local need = (topOf(exit) - topOf(board)) / CLIMB + STEP_OFF + HOP * (#movers - 1)
			-- a drip down the first ladder (Sliding Ladder) must miss the climber too
			local first = stretches(section)[1]
			local drips = dripsOn(section, first)
			local period = Kit.periodOf(movers[1])
			local function still(t0: number): boolean
				if #drips > 0 and hit(first, drips, t0) then
					return false
				end
				local _, _, z0 = Kit.offsetAt(movers[1], t0)
				local moved = { 0, 0, z0 }
				if math.abs(z0) > 0.01 then
					return false -- lined up with the boarding ledge only at rest
				end
				local t = t0
				while t <= t0 + need do
					for _, p in movers do
						local _, _, dz = Kit.offsetAt(p, t)
						if math.abs(dz - (if p == movers[1] then moved[3] else 0)) > 0.01 then
							return false
						end
					end
					t += DT
				end
				return true
			end
			local best, run, t0 = 0, 0, 0
			while t0 < 2 * period do
				if still(t0) then
					run += DT
					best = math.max(best, run)
				else
					run = 0
				end
				t0 += DT
			end
			if DEBUG then
				print(`{v.name} [{v.tier}] boarding window {best} s`)
			end
			if best < ObbyCheck.WINDOW[v.tier] - 1e-6 or best > MAX[v.tier] then
				error(`{v.name}: boarding window {best} s`)
			end
		end
	end)
end)
