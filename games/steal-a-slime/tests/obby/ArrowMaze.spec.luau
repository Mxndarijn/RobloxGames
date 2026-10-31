--!strict
-- Arrow Maze (obby idea 23): every variant through ObbyCheck, plus what the shared checks can't see in a belt maze:
-- every layout solves in the cell model (ArrowMaze.solve), the generator is deterministic and solvable for many
-- seeds with its tier's rules (dumps, belts pointing away from the route), the maze is not walked forward even
-- without the exit hop, and turning-belt windows sit in the tier's band (contract §10).
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local ArrowMaze = require("../../src/shared/ObbySections/ArrowMaze")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

-- Seconds a turning belt points the route's way past riding across it (contract §10 bands).
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}
local GEN_SEEDS = 300

-- The section with its exit ledge lowered to the last column: the maze alone.
local function withoutExitHop(section: Kit.Section, hop: number): Kit.Section
	local parts = {}
	for i, part in section.parts do
		local copy = table.clone(part)
		if i == #section.parts then
			copy.pos = { part.pos[1], part.pos[2] - hop, part.pos[3] }
		end
		table.insert(parts, copy)
	end
	return { length = section.length, rise = section.rise - hop, parts = parts }
end

local function hopOf(layout: any): number
	return layout.exitHop or ArrowMaze.EXIT_HOP
end

describe("ArrowMaze", function()
	it("is idea 23 with every variant of the design file and a generator", function()
		expect(ArrowMaze.id).toBe("ArrowMaze")
		expect(ArrowMaze.idea).toBe(23)
		expect(#ArrowMaze.variants).toBe(20)
		expect(ArrowMaze.generator ~= nil).toBe(true)
	end)

	it("passes every shared check", function()
		local problems = {}
		for _, case in ObbyCheck.cases(ArrowMaze) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		expect(#problems).toBe(0)
	end)

	it("solves every hand-made layout in the cell model", function()
		local bad = {}
		for i, v in ArrowMaze.variants do
			if not ArrowMaze.solve(ArrowMaze.layoutOf(i, 1)) then
				table.insert(bad, v.name)
			end
		end
		if #bad > 0 then
			print("unsolvable: " .. table.concat(bad, ", "))
		end
		expect(#bad).toBe(0)
	end)

	it("can't be walked forward even without the exit hop", function()
		local bad = {}
		for i, v in ArrowMaze.variants do
			local layout = ArrowMaze.layoutOf(i, 1)
			local why = ObbyCheck.straightWalk(withoutExitHop(v.build(1), hopOf(layout)))
			if why then
				table.insert(bad, `{v.name}: {why}`)
			end
		end
		if #bad > 0 then
			print(table.concat(bad, "\n"))
		end
		expect(#bad).toBe(0)
	end)

	it("generates deterministic, solvable mazes with its tier's rules for many seeds", function()
		local bad = {}
		local fell = 0
		for _, tier in ArrowMaze.generator.tiers do
			for seed = 1, GEN_SEEDS do
				local a, fallback = ArrowMaze.generate(seed, tier)
				local b = ArrowMaze.generate(seed, tier)
				if ObbyCheck.encode(a) ~= ObbyCheck.encode(b) then
					table.insert(bad, `{tier} {seed}: not deterministic`)
				end
				if fallback then
					fell += 1
				end
				if not ArrowMaze.solve(a) then
					table.insert(bad, `{tier} {seed}: unsolvable`)
				end
				local dumps = ArrowMaze.dumps(a)
				if tier == "easy" and dumps > 0 and not fallback then
					table.insert(bad, `{tier} {seed}: {dumps} dumps on easy`)
				end
				if ArrowMaze.partCount(a) > ObbyCheck.PARTS_MAX then
					table.insert(bad, `{tier} {seed}: too many parts`)
				end
				local cols = #a.lanes[1]
				local range = ArrowMaze.TIER[tier].cols
				if not fallback and (cols < range[1] or cols > range[2]) then
					table.insert(bad, `{tier} {seed}: {cols} columns`)
				end
			end
		end
		if #bad > 0 then
			print(table.concat(bad, "\n"))
		end
		expect(#bad).toBe(0)
		expect(fell).toBe(0)
	end)

	it("keeps generated mazes from being walked forward even without the exit hop", function()
		local cleared = 0
		local total = 0
		for _, tier in ArrowMaze.generator.tiers do
			for seed = 1, 40 do
				local layout = ArrowMaze.generate(seed, tier)
				total += 1
				if ObbyCheck.straightWalk(withoutExitHop(ArrowMaze.grid(layout), hopOf(layout))) then
					cleared += 1
				end
			end
		end
		-- The exit hop alone stops the rest (the shared straight-walk check); most mazes stop a walker on their own.
		print(`generated mazes a forward walk crosses without the exit hop: {cleared} of {total}`)
		expect(cleared * 4 <= total).toBe(true)
	end)

	it("gives turning belts a window in the tier's band", function()
		local bad = {}
		local function check(name: string, tier: string, section: Kit.Section)
			for _, part in section.parts do
				local m = part.motion
				if m and m.kind == "turn" then
					local c = part.conveyor :: Kit.Vec
					local speed = math.sqrt(c[1] * c[1] + c[3] * c[3])
					local open = (m.duty or 0.5) * (m.period or 1) - ArrowMaze.CELL / (Kit.WALK + speed)
					local band = BAND[tier]
					if open < band.lo - 1e-6 or open > band.hi + 1e-6 then
						table.insert(bad, `{name}: {math.floor(open * 100) / 100} s ({band.lo}..{band.hi})`)
					end
				end
			end
		end
		for _, v in ArrowMaze.variants do
			check(v.name, v.tier, v.build(1))
		end
		for _, tier in ArrowMaze.generator.tiers do
			for seed = 1, 20 do
				check(`generator {tier} {seed}`, tier, ArrowMaze.generator.build(seed, tier))
			end
		end
		if #bad > 0 then
			print(table.concat(bad, "\n"))
		end
		expect(#bad).toBe(0)
	end)
end)
