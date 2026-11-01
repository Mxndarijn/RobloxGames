--!strict
-- Merry-go-round (obby idea 9): every variant through ObbyCheck, plus the idea's own rules: spinning floors show
-- their arrows, spokes stay welded to the disk they lie on, and the hazard windows sit in their tier's band (§10).
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local MerryGoRound = require("../../src/shared/ObbySections/MerryGoRound")
local ObbyCheck = require("../ObbyCheck")

local idea: Kit.Idea = MerryGoRound :: any

-- The most a hazard window may be per tier (§10: easy <= 2.0, medium 1.0..1.4, hard 0.75..1.0); the least is
-- ObbyCheck.WINDOW.
local WINDOW_MAX = { easy = 2.0, medium = 1.4, hard = 1.0 }

local function count(list: { any }, keep: (any) -> boolean): number
	local n = 0
	for _, v in list do
		if keep(v) then
			n += 1
		end
	end
	return n
end

describe("MerryGoRound", function()
	it("builds all 18 designed variants in the design's order, at least 4 / 4 / 3 per tier", function()
		expect(#idea.variants).toBe(18)
		expect(idea.variants[1].name).toBe("Slow Ride")
		expect(idea.variants[18].name).toBe("Gear Train")
		expect(idea.generator).toBeNil()
		for tier, least in { easy = 4, medium = 4, hard = 3 } do
			local n = count(idea.variants, function(v)
				return v.tier == tier
			end)
			expect(`{tier}: {n >= least}`).toBe(`{tier}: true`)
		end
	end)

	it("passes every ObbyCheck for seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(idea) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("puts turning arrows on every spinning or sweeping floor", function()
		for _, v in idea.variants do
			for _, part in v.build(1).parts do
				local kind = part.motion and part.motion.kind
				if part.step and (kind == "spin" or kind == "sweep") then
					expect(`{v.name}: {part.marker}`).toBe(`{v.name}: arrows`)
				end
			end
		end
	end)

	it("keeps each spoke welded to the disk it lies on", function()
		local checked = 0
		for _, v in idea.variants do
			local parts = v.build(1).parts
			for _, part in parts do
				local m = part.motion
				if part.hazard and m and m.kind == "spin" then
					-- a spoke lies on its disk (bottom on the disk's top) and spans it; an arm floats above
					for _, p in parts do
						local pm = p.motion
						local onTop = math.abs((part.pos[2] - part.size[2] / 2) - (p.pos[2] + p.size[2] / 2)) < 1e-6
						if p.step and pm and pm.kind == "spin" and onTop and p.pos[1] == part.pos[1] then
							expect(`{v.name}: {pm.period} {pm.phase or 0}`).toBe(`{v.name}: {m.period} {m.phase or 0}`)
							expect(part.size[1] <= p.size[1]).toBe(true)
							checked += 1
						end
					end
				end
			end
		end
		expect(checked).toBe(5)
	end)

	it("keeps hazard windows inside the tier's band", function()
		for _, v in idea.variants do
			local max = WINDOW_MAX[v.tier]
			for _, w in ObbyCheck.windows(v.build(1)) do
				expect(`{v.name}: {w.slack <= max + 1e-6}`).toBe(`{v.name}: true`)
			end
		end
	end)

	it("gives most variants a hazard on top of the moving floor", function()
		local with = count(idea.variants, function(v)
			return count(v.build(1).parts, function(p)
				return p.hazard == true
			end) > 0
		end)
		expect(with >= 12).toBe(true)
	end)

	it("never lets a straight walk clear a variant", function()
		for _, v in idea.variants do
			expect(`{v.name}: {ObbyCheck.straightWalk(v.build(1))}`).toBe(`{v.name}: nil`)
		end
	end)
end)
