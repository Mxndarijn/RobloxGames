--!strict
-- Glow Memory (obby idea 10): every variant and the generator through ObbyCheck, plus what the shared checks can't
-- see in a memory grid: the safe tiles alone (no fake) always lead from the entry pad to the exit, no lane is safe
-- all the way (so it can't be jumped straight), every row has a fake, and the path glows long enough to read.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local GlowMemory = require("../../src/shared/ObbySections/GlowMemory")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

local SEEDS = 120 -- more than the shared 20

local function isFake(p: Kit.Part): boolean
	local m = p.motion
	return m ~= nil and m.kind == "melt" and (m.delay or 0) <= 0.2
end

-- A floor you can stand on at time t (nil = at rest): solid, not a fake, there now.
local function floorAt(p: Kit.Part, t: number?): boolean
	if p.ghost or p.hazard or isFake(p) then
		return false
	end
	local _, _, _, _, _, on = Kit.offsetAt(p, t)
	return on
end

local function gap(a: Kit.Part, b: Kit.Part): (number, number)
	local ax0, ax1, _, ay1, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, by1, bz0, bz1 = Kit.bounds(b)
	local gx = math.max(0, bx0 - ax1, ax0 - bx1)
	local gz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(gx * gx + gz * gz), by1 - ay1
end

-- Can the exit pad (the last step) be reached from the entry pad over safe floors only, all present at time t?
local function solvable(section: Kit.Section, t: number?): boolean
	local floors, first, last = {}, nil, nil
	for _, p in section.parts do
		if p.step then
			first = first or p
			last = p
		end
		if p.size[2] <= 1.01 and floorAt(p, t) then
			table.insert(floors, p)
		end
	end
	local seen = { [first :: Kit.Part] = true }
	local queue = { first :: Kit.Part }
	while #queue > 0 do
		local a = table.remove(queue) :: Kit.Part
		if a == last then
			return true
		end
		for _, b in floors do
			if not seen[b] then
				local g, rise = gap(a, b)
				if g <= Kit.GAP_MAX and rise <= Kit.RISE_MAX then
					seen[b] = true
					table.insert(queue, b)
				end
			end
		end
	end
	return false
end

-- Grid tiles grouped in rows (by x) and lanes (by z): tiles are the 1-thick "glow" slabs.
local function rowsOf(section: Kit.Section): { { Kit.Part } }
	local byX: { [number]: { Kit.Part } } = {}
	local xs = {}
	for _, p in section.parts do
		if p.look == "glow" and not p.ghost then
			local key = math.floor(p.pos[1] * 10 + 0.5)
			if not byX[key] then
				byX[key] = {}
				table.insert(xs, key)
			end
			table.insert(byX[key], p)
		end
	end
	table.sort(xs)
	local out = {}
	for _, key in xs do
		table.insert(out, byX[key])
	end
	return out
end

-- New Every Round (and the generator's rounds mode): one path's own tiles fade out for the other round.
local function hasRounds(section: Kit.Section): boolean
	for _, p in section.parts do
		local m = p.motion
		if m and m.kind == "flip" and not m.solid then
			return true
		end
	end
	return false
end

-- Each case's sections for seeds 1..SEEDS.
local function eachSection(fn: (string, Kit.Section, number) -> ())
	for _, case in ObbyCheck.cases(GlowMemory :: any) do
		for seed = 1, SEEDS do
			fn(case.name, case.build(seed), seed)
		end
	end
end

-- The times to look at a section: over one 20 s cycle (round mode switches every 10 s).
local TIMES: { number } = {}
for k = 0, 39 do
	table.insert(TIMES, k * 0.5)
end

describe("GlowMemory", function()
	it("passes every ObbyCheck for every variant and the generator", function()
		local problems = {}
		for _, case in ObbyCheck.cases(GlowMemory :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("has every variant of the design in order", function()
		local names = {}
		for _, v in GlowMemory.variants do
			table.insert(names, v.name)
		end
		expect(table.concat(names, ", ")).toBe(
			"First Steps, Two of Three, Breadcrumbs, Chime Path, Show Me Pad, Snake Trail, Pink Traps, Memory Stairs, "
				.. "Song Path, Map Behind You, Quick Flash, Two Grids, One Look, New Every Round, Trail Run, Hot Feet"
		)
	end)

	it("can always be crossed on safe tiles alone, for many seeds", function()
		local bad = {}
		eachSection(function(name, section, seed)
			local ok = false
			for _, t in TIMES do
				ok = ok or solvable(section, t)
			end
			if not ok then
				table.insert(bad, `{name} seed {seed}`)
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("puts a fake in every row and in every lane, so nothing is safe straight ahead", function()
		local bad = {}
		eachSection(function(name, section, seed)
			local lanes: { [number]: boolean } = {}
			local laneSeen: { [number]: boolean } = {}
			for k, row in rowsOf(section) do
				local fakes = 0
				for _, p in row do
					local z = math.floor(p.pos[3] + 0.5)
					laneSeen[z] = true
					if isFake(p) then
						fakes += 1
						lanes[z] = true
					end
				end
				if fakes == 0 then
					table.insert(bad, `{name} seed {seed}: row {k} has no fake`)
				end
			end
			for z in laneSeen do
				if not lanes[z] then
					table.insert(bad, `{name} seed {seed}: lane z {z} is safe in every row`)
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("keeps one main-path step a row, at most one lane over from the last", function()
		local bad = {}
		eachSection(function(name, section, seed)
			local lastZ: number? = nil
			for k, row in rowsOf(section) do
				local steps = {}
				for _, p in row do
					if p.step then
						table.insert(steps, p)
					end
				end
				-- New Every Round has two paths (one tile each a row, or one shared)
				local most = if hasRounds(section) then 2 else 1
				if #steps < 1 or #steps > most then
					table.insert(bad, `{name} seed {seed}: row {k} has {#steps} path tiles`)
				elseif most == 1 then
					local z = steps[1].pos[3]
					if lastZ and math.abs(z - lastZ) > 12.01 then
						table.insert(bad, `{name} seed {seed}: row {k} jumps two lanes`)
					end
					lastZ = z
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("shows the path for at least 1.5 s in all", function()
		-- A glow is a solid flip lit while its cycle is under duty, or an overlay popped up out of its tile. The show is
		-- the longest stretch of 0.05 s samples (one 20 s look) with some path tile lit: seq modes light one after another.
		local function lit(p: Kit.Part, t: number): boolean
			local m = p.motion
			if not m then
				return false
			end
			local cycle = (t / Kit.periodOf(p) + (m.phase or 0)) % 1
			if m.kind == "flip" and m.solid then
				return cycle < (m.duty or 0)
			elseif m.kind == "path" and p.ghost then
				local _, dy = Kit.offsetAt(p, t)
				return dy > 0.3
			end
			return false
		end
		local bad = {}
		eachSection(function(name, section, seed)
			local best, run = 0, 0
			for k = 0, 400 do
				local any = false
				for _, p in section.parts do
					any = any or lit(p, k * 0.05)
				end
				run = if any then run + 0.05 else 0
				best = math.max(best, run)
			end
			-- the map board (a lit cell per row, always on) shows the path instead of the floor
			local board = false
			for _, p in section.parts do
				board = board or (p.ghost == true and p.look == "glow" and p.motion == nil)
			end
			if not board and not hasRounds(section) and best < 1.5 - 0.06 then
				table.insert(bad, `{name} seed {seed}: shown {best} s`)
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("lets nobody wait on a safe tile for the next glow (it melts first), but in One Look and rounds", function()
		local bad = {}
		eachSection(function(name, section, seed)
			if string.find(name, "One Look", 1, true) or hasRounds(section) then
				return
			end
			for _, p in section.parts do
				if p.step and p.look == "glow" then
					local m = p.motion
					if not (m and m.kind == "melt" and (m.delay or 0) > 0.2 and (m.delay or 0) <= 2) then
						table.insert(bad, `{name} seed {seed}: safe tile {p.pos[1]},{p.pos[3]} holds you forever`)
						return
					end
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("gives different paths for different seeds and the same for the same seed", function()
		for _, case in ObbyCheck.cases(GlowMemory :: any) do
			local seen = {}
			for seed = 1, 20 do
				seen[ObbyCheck.encode(case.build(seed))] = true
			end
			local n = 0
			for _ in seen do
				n += 1
			end
			expect(n >= 5).toBe(true)
			expect(ObbyCheck.encode(case.build(7))).toBe(ObbyCheck.encode(case.build(7)))
		end
	end)
end)
