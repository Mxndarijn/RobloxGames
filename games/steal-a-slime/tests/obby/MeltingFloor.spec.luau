--!strict
-- Melting Floor (obby idea 2): every variant through ObbyCheck, plus what the shared checks don't time: a runner
-- model crosses the route and every melting tile it stands on must still be there when it leaves (spreading melt
-- from tiles behind included), and the generator stays solvable and deterministic over many more seeds.
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local MeltingFloor = require("../../src/shared/ObbySections/MeltingFloor")
local ObbyCheck = require("../ObbyCheck")

local REACH = 0.9 -- share of a full running jump the runner counts on
local REJUMP = 0.1 -- seconds from landing to the next take-off

type Part = Kit.Part

local function airTime(rise: number): number
	local v, g = Kit.JUMP_SPEED, Kit.GRAVITY
	local disc = v * v - 2 * g * math.max(rise, 0)
	if disc < 0 then
		return 0
	end
	return (v + math.sqrt(disc)) / g
end

local function topOf(p: Part): number
	return p.pos[2] + p.size[2] / 2
end

-- Flat gap between two parts at rest (discs by their circles).
local function gapOf(a: Part, b: Part): number
	if a.shape == "disc" and b.shape == "disc" then
		local d = math.sqrt((a.pos[1] - b.pos[1]) ^ 2 + (a.pos[3] - b.pos[3]) ^ 2)
		return math.max(0, d - a.size[1] / 2 - b.size[1] / 2)
	end
	local ax0, ax1, _, _, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, _, bz0, bz1 = Kit.bounds(b)
	local dx = math.max(0, bx0 - ax1, ax0 - bx1)
	local dz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(dx * dx + dz * dz)
end

-- nil when the runner model crosses the main route before any melting tile under it goes; else why not.
local function runnerProblem(section: Kit.Section): string?
	local parts = section.parts
	local steps: { number } = {}
	for i, p in parts do
		if p.step and p.route == nil then
			table.insert(steps, i)
		end
	end
	-- each step's way in: the step before, or the nearest earlier step when that one is out of jump reach
	local land: { [number]: number } = {}
	local leave: { [number]: number } = {}
	local t = 0
	for k, i in steps do
		local p = parts[i]
		if k == 1 then
			land[i] = 0
		else
			local from = steps[k - 1]
			if gapOf(parts[from], p) > Kit.GAP_MAX then
				local best = math.huge
				for j = 1, k - 1 do
					local g = gapOf(parts[steps[j]], p)
					if g < best then
						best, from = g, steps[j]
					end
				end
			end
			land[i] = t + airTime(topOf(p) - topOf(parts[from]))
			local into = math.max(0, Kit.WALK * airTime(topOf(p) - topOf(parts[from])) * REACH - gapOf(parts[from], p))
			-- length along the way: the dominant axis from the step before to the step after
			local prev, nxt = parts[steps[k - 1]], parts[steps[math.min(k + 1, #steps)]]
			local dx, dz = math.abs(nxt.pos[1] - prev.pos[1]), math.abs(nxt.pos[3] - prev.pos[3])
			local long = if dx >= dz then p.size[1] else p.size[3]
			leave[i] = land[i] + math.max(0, long - into) / Kit.WALK + REJUMP
			t = leave[i]
		end
		if k == 1 then
			leave[i] = 0
		end
	end
	-- when every tile starts melting: on landing, or `spread` s after a spreading neighbour is gone
	local start: { [number]: number } = {}
	for _, i in steps do
		local m = parts[i].motion
		if m and m.kind == "melt" and m.on ~= "leave" then
			start[i] = land[i]
		end
	end
	for _ = 1, #parts do
		local changed = false
		for i, s in start do
			local m = parts[i].motion :: Kit.Motion
			if m.next then
				local gone = s + (m.delay or 0)
				for _, n in m.next do
					local j = n :: number
					local at = gone + (m.spread or 0)
					if start[j] == nil or at < start[j] - 1e-9 then
						start[j] = at
						changed = true
					end
				end
			end
		end
		if not changed then
			break
		end
	end
	for k, i in steps do
		local m = parts[i].motion
		if k > 1 and k < #steps and m and m.kind == "melt" and m.on ~= "leave" then
			local gone = start[i] + (m.delay or 0)
			if gone < leave[i] - 1e-6 then
				return `step {k} (part {i}) goes at {math.floor(gone * 100) / 100} s, the runner leaves it at {math.floor(
					leave[i] * 100
				) / 100} s`
			end
		end
	end
	return nil
end

describe("MeltingFloor", function()
	it("every variant and the generator pass ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(MeltingFloor :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("the runner leaves every melting tile before it goes (variants, seeds 1..20)", function()
		local problems = {}
		for _, case in ObbyCheck.cases(MeltingFloor :: any) do
			for seed = 1, ObbyCheck.SEEDS do
				local why = runnerProblem(case.build(seed))
				if why then
					table.insert(problems, `{case.name} seed {seed}: {why}`)
					break
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("the generator is deterministic, solvable and timed fairly over seeds 1..200", function()
		local problems = {}
		local gen = MeltingFloor.generator :: Kit.Generator
		for _, tier in gen.tiers do
			for seed = 1, 200 do
				local a, b = gen.build(seed, tier), gen.build(seed, tier)
				if ObbyCheck.encode(a) ~= ObbyCheck.encode(b) then
					table.insert(problems, `{tier} seed {seed}: not deterministic`)
				end
				for _, check in { ObbyCheck.budget, ObbyCheck.widths, ObbyCheck.makeable, ObbyCheck.fields } do
					local why = check(a)
					if why then
						table.insert(problems, `{tier} seed {seed}: {why}`)
					end
				end
				local why = runnerProblem(a)
				if why then
					table.insert(problems, `{tier} seed {seed}: {why}`)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("the generator's straight-walk check holds over seeds 1..60", function()
		local problems = {}
		local gen = MeltingFloor.generator :: Kit.Generator
		for _, tier in gen.tiers do
			for seed = 21, 60 do
				local why = ObbyCheck.straightWalk(gen.build(seed, tier))
				if why then
					table.insert(problems, `{tier} seed {seed}: {why}`)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it(
		"tiers earn their holds: easy tiles hold 0.9..2 s, medium under 0.75 s, hard under 0.6 s on the route",
		function()
			local limits = { easy = { 0.85, 2.0 }, medium = { 0.35, 0.75 }, hard = { 0.3, 0.6 } }
			local problems = {}
			for _, case in ObbyCheck.cases(MeltingFloor :: any) do
				local section = case.build(1)
				for i, p in section.parts do
					local m = p.motion
					if p.step and m and m.kind == "melt" and m.on ~= "leave" then
						local lim = limits[case.tier]
						if (m.delay or 0) < lim[1] - 1e-6 or (m.delay or 0) > lim[2] + 1e-6 then
							table.insert(problems, `{case.name}: part {i} holds {m.delay} s`)
						end
					end
				end
			end
			expect(table.concat(problems, "\n")).toBe("")
		end
	)
end)
