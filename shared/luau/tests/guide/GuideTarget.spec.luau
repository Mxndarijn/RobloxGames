--!strict
local GuideTarget = require("../../src/guide/GuideTarget")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function c(key: string, x: number, z: number): GuideTarget.Candidate<string>
	return { key = key, x = x, z = z, value = key }
end

local ORIGIN = { x = 0, z = 0 }

describe("GuideTarget.pick", function()
	it("returns nil for an empty list", function()
		expect(GuideTarget.pick({}, ORIGIN, nil)).toBeNil()
	end)

	it("picks the closest candidate on the ground plane", function()
		local picked = GuideTarget.pick({ c("far", 30, 0), c("near", 0, 10), c("mid", -20, 0) }, ORIGIN, nil)
		expect(picked and picked.key).toBe("near")
	end)

	it("measures from the given point", function()
		local picked = GuideTarget.pick({ c("a", 0, 0), c("b", 50, 50) }, { x = 45, z = 45 }, nil)
		expect(picked and picked.key).toBe("b")
	end)

	it("keeps the current target when a new one is only slightly closer", function()
		local picked = GuideTarget.pick({ c("current", 10, 0), c("other", 0, 9) }, ORIGIN, "current")
		expect(picked and picked.key).toBe("current")
	end)

	it("switches when a new target is more than the stickiness closer", function()
		local picked = GuideTarget.pick({ c("current", 10, 0), c("other", 0, 7) }, ORIGIN, "current")
		expect(picked and picked.key).toBe("other")
	end)

	it("uses a custom stickiness", function()
		local candidates = { c("current", 10, 0), c("other", 0, 9) }
		local picked = GuideTarget.pick(candidates, ORIGIN, "current", 0)
		expect(picked and picked.key).toBe("other")
	end)

	it("picks again when the current target left the list", function()
		local picked = GuideTarget.pick({ c("a", 20, 0), c("b", 5, 0) }, ORIGIN, "gone")
		expect(picked and picked.key).toBe("b")
	end)

	it("breaks exact ties by key so the result does not depend on list order", function()
		local one = GuideTarget.pick({ c("b", 5, 0), c("a", 0, 5) }, ORIGIN, nil)
		local two = GuideTarget.pick({ c("a", 0, 5), c("b", 5, 0) }, ORIGIN, nil)
		expect(one and one.key).toBe("a")
		expect(two and two.key).toBe("a")
	end)

	it("hands back the candidate's value", function()
		local picked = GuideTarget.pick({ { key = "k", x = 1, z = 1, value = 42 } }, ORIGIN, nil)
		expect(picked and picked.value).toBe(42)
	end)
end)
