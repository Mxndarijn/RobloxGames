--!strict
-- Sliding Maze (obby idea 25): every variant and the generator through ObbyCheck, the variant list against its design
-- file, the tier bands of the hazard windows (contract §10), and what the shared checks can't see in a maze: the timed
-- solver gets out from every start moment, the panels on the way through open for the tier's window, the maze walls
-- alone stop every straight walk, panels never reach a cell centre, and the plates and the chaser do what they say.
local T = require("../TestRunner")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local SlidingMaze = require("../../src/shared/ObbySections/SlidingMaze")

local Maze = SlidingMaze :: any

-- The tightest hazard window ObbyCheck measures, per tier (contract §10); a window over STILL s is a passage that is
-- never shut (a swap panel always leaves one side open).
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}
local STILL = 5
-- The solver's runner is stricter than ObbyCheck's (a body 0.1 s either side of the panel's plane): its windows on
-- the way through sit up to this much under the band.
local RUNNER_SLACK = 0.3
local GEN_SEEDS = 120 -- generator seeds per tier the solver proves here (the shared checks run 1..20)

local TIER_ROWS = { easy = { 5, 6 }, medium = { 8, 9 }, hard = { 10, 12 } }

local function caseLayout(case: ObbyCheck.Case, seed: number): (any, Kit.Section)
	return Maze.layoutOf(case.variant, seed, case.tier)
end

-- The seeds worth looking at for a case: hand-made variants ignore theirs.
local function seedsOf(case: ObbyCheck.Case, many: number): { number }
	local out = {}
	for s = 1, if case.variant == 0 then many else 1 do
		table.insert(out, s)
	end
	return out
end

-- The cells' graph ignoring panels: the shortest way from an entry cell to an exit cell, as the edge keys it
-- crosses.
local function route(L: any): { string }
	local N = L.rows
	local prev: { [string]: { string } } = {}
	local queue = {}
	for c = 1, 3 do
		local key = `1:{c}`
		if (L.entry == nil or L.entry[c]) and L.used[key] then
			prev[key] = { "", "" }
			table.insert(queue, { 1, c })
		end
	end
	local head = 1
	while head <= #queue do
		local r, c = queue[head][1], queue[head][2]
		head += 1
		if r == N and (L.exit == nil or L.exit[c]) then
			local edges = {}
			local key = `{r}:{c}`
			while prev[key][1] ~= "" do
				table.insert(edges, prev[key][2])
				key = prev[key][1]
			end
			return edges
		end
		for _, mv in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nr, nc = r + mv[1], c + mv[2]
			local nkey = `{nr}:{nc}`
			if nr >= 1 and nr <= N and nc >= 1 and nc <= 3 and L.used[nkey] and not prev[nkey] then
				local edge = if mv[1] ~= 0 then `x{math.min(r, nr)}:{c}` else `z{r}:{math.min(c, nc)}`
				if L.open[edge] then
					prev[nkey] = { `{r}:{c}`, edge }
					table.insert(queue, { nr, nc })
				end
			end
		end
	end
	return {}
end

-- The maze on its own: the entry pad moved up to the maze floor and a flat exit, so a walker starts inside.
local function mazeOnly(section: Kit.Section, L: any): Kit.Section
	local x0, xEnd = L.x0, L.x0 + 8 * L.rows
	local parts = { Kit.slab(x0 - 2, L.tops[1], 0, 4, Kit.WIDTH, "jelly") }
	for _, p in section.parts do
		local a, b = Kit.bounds(p)
		if not p.step or (a >= x0 - 0.01 and b <= xEnd + 0.01) then
			table.insert(parts, p)
		end
	end
	table.insert(parts, Kit.slab(xEnd + 1.5, L.tops[L.rows], 0, 3, Kit.WIDTH, "jelly"))
	return { length = xEnd + 3, rise = L.tops[L.rows], parts = parts }
end

-- The solver gets out from every start moment over the longest beat, and never needs more than one beat per panel.
local function solveAll(L: any, section: Kit.Section): string?
	local period = math.max(Maze.longestPeriod(L), 1)
	local walk = (2 * L.rows + 6) * 0.8
	local t0 = 0
	while t0 < period do
		local took = Maze.solve(L, section, t0)
		if took == nil then
			return `no way out when starting at {t0} s`
		elseif took > walk + #L.doors * period then
			return `{took} s to get out when starting at {t0} s`
		end
		t0 += 0.1
	end
	return nil
end

describe("Sliding Maze", function()
	it("builds every variant of docs/obby-variants/25.json, in its order and tiers, plus its generator", function()
		local doc = serde.decode("json", fs.readFile("docs/obby-variants/25.json"))
		local design = doc.ideas[1]
		expect(SlidingMaze.id).toBe("SlidingMaze")
		expect(SlidingMaze.name).toBe(design.name)
		expect(SlidingMaze.idea).toBe(design.id)
		expect(#SlidingMaze.variants).toBe(#design.variants)
		for i, v in design.variants do
			expect(SlidingMaze.variants[i].name).toBe(v.name)
			expect(SlidingMaze.variants[i].tier).toBe(v.tier)
		end
		local gen = SlidingMaze.generator :: Kit.Generator
		expect(table.concat(gen.tiers, ",")).toBe("easy,medium,hard")
	end)

	it("passes every shared check for every variant and the generator, seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(SlidingMaze :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("keeps the tightest hazard window of every maze in its tier's band", function()
		local off = {}
		for _, case in ObbyCheck.cases(SlidingMaze :: any) do
			for _, seed in seedsOf(case, 20) do
				local section = case.build(seed)
				-- Plates run their door on your own press clock: the walk from the plate is the window (below).
				local clocked = false
				for _, part in section.parts do
					clocked = clocked or (part.hazard == true and part.start ~= nil and part.motion.kind == "path")
				end
				local tight = math.huge
				for _, w in ObbyCheck.windows(section) do
					tight = math.min(tight, w.slack)
				end
				local band = BAND[case.tier]
				if not clocked and tight < STILL and (tight < band.lo - 1e-6 or tight > band.hi + 1e-6) then
					table.insert(off, `{case.name} seed {seed}: tightest window {tight} s ({band.lo}..{band.hi})`)
				end
			end
		end
		expect(table.concat(off, "\n")).toBe("")
	end)

	it("gets the timed runner out from every start moment, waiting at most a beat a panel", function()
		local off = {}
		for _, case in ObbyCheck.cases(SlidingMaze :: any) do
			for _, seed in seedsOf(case, 20) do
				local L, section = caseLayout(case, seed)
				local why = solveAll(L, section)
				if why then
					table.insert(off, `{case.name} seed {seed}: {why}`)
				end
			end
		end
		expect(table.concat(off, "\n")).toBe("")
	end)

	it("opens every panel on the way through for the tier's window", function()
		local off = {}
		for _, case in ObbyCheck.cases(SlidingMaze :: any) do
			for _, seed in seedsOf(case, 20) do
				local L, section = caseLayout(case, seed)
				local doorEdges = {}
				for _, key in Maze.doorEdges(L) do
					doorEdges[key] = true
				end
				local plate = #L.plates > 0
				local band = BAND[case.tier]
				local span = 3 * math.max(Maze.longestPeriod(L), 1)
				for _, key in route(L) do
					if doorEdges[key] then
						local w = Maze.window(L, section, key, span)
						local hi = if plate then 4.5 else band.hi + RUNNER_SLACK
						if w < band.lo - RUNNER_SLACK - 1e-6 or w > hi + 1e-6 then
							table.insert(off, `{case.name} seed {seed}: {key} open {w} s`)
						end
					end
				end
			end
		end
		expect(table.concat(off, "\n")).toBe("")
	end)

	it("stops every straight walk with its own walls, even without the jump in", function()
		local off = {}
		for _, case in ObbyCheck.cases(SlidingMaze :: any) do
			for _, seed in seedsOf(case, 20) do
				local L, section = caseLayout(case, seed)
				local why = ObbyCheck.straightWalk(mazeOnly(section, L))
				if why then
					table.insert(off, `{case.name} seed {seed}: {why}`)
				end
			end
		end
		expect(table.concat(off, "\n")).toBe("")
	end)

	it("never moves a panel over a cell centre: every cell is a safe place to wait", function()
		local off = {}
		for _, case in ObbyCheck.cases(SlidingMaze :: any) do
			for _, seed in seedsOf(case, 5) do
				local L, section = caseLayout(case, seed)
				for _, d in L.doors do
					local part = section.parts[d.index]
					local period = Kit.periodOf(part)
					for k = 0, 63 do
						local dx, dy, dz = Kit.offsetAt(part, k / 64 * period)
						local cx, cz = part.pos[1] + dx, part.pos[3] + dz
						local bottom = part.pos[2] - part.size[2] / 2 + dy
						for r = 1, L.rows do
							for c = 1, 3 do
								local x, z = L.x0 + 8 * r - 4, -16 + 8 * c
								local near = math.abs(x - cx) < part.size[1] / 2 + 1.5
									and math.abs(z - cz) < part.size[3] / 2 + 1.5
								if near and bottom < L.tops[r] + Kit.HEAD then
									table.insert(off, `{case.name}: panel {d.index} reaches cell {r}:{c}`)
								end
							end
						end
					end
				end
			end
		end
		expect(table.concat(off, "\n")).toBe("")
	end)
end)

describe("Sliding Maze generator", function()
	it(`proves a way out for seeds 1..{GEN_SEEDS} of every tier, within the part budget`, function()
		local off = {}
		local chasers = 0
		for _, tier in { "easy", "medium", "hard" } do
			for seed = 1, GEN_SEEDS do
				local L, section = Maze.layoutOf(0, seed, tier)
				if not L.generated then
					table.insert(off, `{tier} seed {seed}: fell back to a hand-made maze`)
				end
				if L.rows < TIER_ROWS[tier][1] or L.rows > TIER_ROWS[tier][2] then
					table.insert(off, `{tier} seed {seed}: {L.rows} rows`)
				end
				if ObbyCheck.partCount(section) > ObbyCheck.PARTS_MAX then
					table.insert(off, `{tier} seed {seed}: {ObbyCheck.partCount(section)} parts`)
				end
				local why = solveAll(L, section)
				if why then
					table.insert(off, `{tier} seed {seed}: {why}`)
				end
				if L.chaser then
					chasers += 1
				end
			end
		end
		expect(table.concat(off, "\n")).toBe("")
		-- Hard mazes sometimes add the chaser, never the others.
		expect(chasers > 10).toBe(true)
	end)

	it("is the same maze for the same seed and a different one for another", function()
		local gen = SlidingMaze.generator :: Kit.Generator
		for _, tier in gen.tiers do
			local seen = {}
			for seed = 1, 20 do
				local key = ObbyCheck.encode(gen.build(seed, tier))
				expect(key).toBe(ObbyCheck.encode(gen.build(seed, tier)))
				seen[key] = true
			end
			local n = 0
			for _ in seen do
				n += 1
			end
			expect(n >= 18).toBe(true)
		end
	end)

	it("passes the shared checks past the shared seeds too (21..40)", function()
		local problems = {}
		for _, tier in { "easy", "medium", "hard" } do
			for seed = 21, 40 do
				local section = (SlidingMaze.generator :: Kit.Generator).build(seed, tier)
				for _, name in { "budget", "widths", "fields", "challenge", "makeable", "straightWalk", "timers" } do
					local why = (ObbyCheck :: any)[name](section)
					if why then
						table.insert(problems, `{tier} seed {seed}: {name}: {why}`)
					end
				end
				local unfair = ObbyCheck.fairness(section, tier)
				if unfair then
					table.insert(problems, `{tier} seed {seed}: fairness: {unfair}`)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("keeps dead ends off easy mazes and puts them in medium and hard ones", function()
		for _, tier in { "easy", "medium", "hard" } do
			for seed = 1, 20 do
				local L = Maze.layoutOf(0, seed, tier)
				-- Dead ends: maze cells with one passage that are neither the entry nor the exit cell.
				local ends = 0
				for key in L.used do
					local r, c = string.match(key, "^(%d+):(%d)$")
					local rr, cc = tonumber(r) :: number, tonumber(c) :: number
					local n = 0
					for _, e in { `x{rr}:{cc}`, `x{rr - 1}:{cc}`, `z{rr}:{cc}`, `z{rr}:{cc - 1}` } do
						if L.open[e] then
							n += 1
						end
					end
					local entry = rr == 1 and L.entry[cc]
					local exit = rr == L.rows and L.exit[cc]
					if n == 1 and not entry and not exit then
						ends += 1
					end
				end
				if tier == "easy" then
					expect(ends).toBe(0)
				else
					expect(ends >= 1).toBe(true)
				end
			end
		end
	end)
end)

describe("Sliding Maze twists", function()
	it("Pull the Plug: the doors stay shut until their plate is pressed", function()
		local L, section = Maze.layoutOf(8, 1)
		expect(Maze.solve(L, section, 0) ~= nil).toBe(true)
		local noPlates = table.clone(L)
		noPlates.plates = {}
		expect(Maze.solve(noPlates, section, 0)).toBeNil()
	end)

	it("The Chaser: the flood rolls down the maze a row at a time and catches a runner who dawdles", function()
		local L, section = Maze.layoutOf(10, 1)
		local last = -math.huge
		for _, part in section.parts do
			if part.hazard and part.motion and part.motion.kind == "rise" then
				expect(part.start).toBe("chaser")
				expect(part.motion.delay :: number > last).toBe(true)
				last = part.motion.delay :: number
			end
		end
		-- Starting the clock 4 s before the runner sets off: the flood is already on its heels everywhere.
		local slow = table.clone(L)
		slow.chaser = table.clone(L.chaser)
		slow.chaser.delay -= 4
		local caught = 0
		for t0 = 0, 2.9, 0.5 do
			if Maze.solve(slow, section, t0) == nil then
				caught += 1
			end
		end
		expect(caught > 0).toBe(true)
	end)

	it("Lookout Maze: the start pad sits 4 studs over the maze floor", function()
		local L, section = Maze.layoutOf(4, 1)
		expect(L.tops[1]).toBe(-4)
		expect(section.parts[1].pos[2] + section.parts[1].size[2] / 2).toBe(0)
	end)

	it("Climbing Maze: three terraces 2 studs apart, climbing 6", function()
		local section = SlidingMaze.variants[9].build(1)
		expect(section.rise).toBe(6)
	end)
end)
