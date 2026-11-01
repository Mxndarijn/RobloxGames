--!strict
-- Speed Strip (obby idea 16): every variant through ObbyCheck, plus what the shared checks don't ask: every variant
-- needs its boost (take the strips' speed away and it can't be made), every one has a leap longer than a walking
-- jump, and the timed hazards' windows sit in the tier's band (contract §10).
local T = require("../TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")
local SpeedStrip = require("../../src/shared/ObbySections/SpeedStrip")

-- Hazard windows a tier earns (contract §10); a window longer than STILL s is a still hazard (steer round it).
local BAND = {
	easy = { lo = 1.4, hi = 2.0 },
	medium = { lo = 1.0, hi = 1.4 },
	hard = { lo = 0.75, hi = 1.0 },
}
local STILL = 5
local WALK_JUMP = Kit.WALK * 2 * Kit.JUMP_SPEED / Kit.GRAVITY -- about 8.7 studs on the flat

-- The section with every forward strip's boost taken away (back strips kept).
local function unboosted(section: Kit.Section): Kit.Section
	local parts = {}
	for _, part in section.parts do
		local copy = table.clone(part)
		if copy.boost and copy.boost.speed > Kit.WALK then
			copy.boost = nil
		end
		table.insert(parts, copy)
	end
	return { length = section.length, rise = section.rise, parts = parts }
end

-- The longest edge-to-edge hole along x between consecutive steps, at rest.
local function longestGap(section: Kit.Section): number
	local best, lastEnd = 0, nil
	for _, part in section.parts do
		if part.step then
			local x0, x1 = Kit.bounds(part)
			if lastEnd then
				best = math.max(best, x0 - lastEnd)
			end
			lastEnd = math.max(lastEnd or -math.huge, x1)
		end
	end
	return best
end

describe("SpeedStrip", function()
	it("is idea 16 with every variant of the design file", function()
		expect(SpeedStrip.id).toBe("SpeedStrip")
		expect(SpeedStrip.idea).toBe(16)
		expect(#SpeedStrip.variants).toBe(16)
		expect(SpeedStrip.generator).toBeNil()
	end)

	it("passes every shared check", function()
		local problems = {}
		for _, case in ObbyCheck.cases(SpeedStrip) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("can't be made without the boost", function()
		for _, case in ObbyCheck.cases(SpeedStrip) do
			local why = ObbyCheck.makeable(unboosted(case.build(1)))
			if why == nil then
				error(`{case.name} is makeable without its boost`)
			end
		end
	end)

	it("has a leap longer than a walking jump", function()
		for _, case in ObbyCheck.cases(SpeedStrip) do
			local gap = longestGap(case.build(1))
			if gap <= WALK_JUMP then
				error(`{case.name}: longest gap {gap} (a walking jump reaches {WALK_JUMP})`)
			end
		end
	end)

	it("times its moving hazards to the tier", function()
		for _, case in ObbyCheck.cases(SpeedStrip) do
			local band = BAND[case.tier]
			for _, w in ObbyCheck.windows(case.build(1)) do
				if w.slack < STILL and (w.slack < band.lo - 1e-6 or w.slack > band.hi + 1e-6) then
					error(`{case.name}: window {w.slack} s at x {w.from}..{w.to} (band {band.lo}..{band.hi})`)
				end
			end
		end
	end)
end)
