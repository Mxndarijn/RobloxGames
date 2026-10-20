--!strict
local GuideTrail = require("../../src/guide/GuideTrail")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function p(x: number, y: number, z: number): GuideTrail.Point
	return { x = x, y = y, z = z }
end

local STRAIGHT = { p(0, 0, 0), p(50, 0, 0) }
local PLAIN = { startGap = 0, endGap = 0, fadeIn = 0, fadeOut = 0, spacing = 5, maxLength = 1000, maxCount = 100 }

describe("GuideTrail.layout", function()
	it("returns no arrows for a route shorter than two points", function()
		expect(#GuideTrail.layout({}, 0)).toBe(0)
		expect(#GuideTrail.layout({ p(1, 2, 3) }, 0)).toBe(0)
	end)

	it("places arrows every spacing studs along a straight route", function()
		local arrows = GuideTrail.layout(STRAIGHT, 0, PLAIN)
		expect(#arrows).toBe(11) -- 0, 5, ..., 50
		expect(arrows[1].x).toBeCloseTo(0)
		expect(arrows[2].x).toBeCloseTo(5)
		expect(arrows[11].x).toBeCloseTo(50)
		expect(arrows[3].dirX).toBeCloseTo(1)
		expect(arrows[3].dirZ).toBeCloseTo(0)
	end)

	it("shifts every arrow forward by the phase", function()
		local arrows = GuideTrail.layout(STRAIGHT, 2, PLAIN)
		expect(arrows[1].x).toBeCloseTo(2)
		expect(arrows[2].x).toBeCloseTo(7)
	end)

	it("stops endGap studs before the target and starts startGap studs from the player", function()
		local arrows =
			GuideTrail.layout(STRAIGHT, 0, { spacing = 5, startGap = 3, endGap = 6, fadeIn = 0, fadeOut = 0 })
		expect(arrows[1].x).toBeCloseTo(3)
		for _, arrow in arrows do
			expect(arrow.x <= 44 + 1e-6).toBe(true)
		end
	end)

	it("shows nothing when the player is already close to the target", function()
		local arrows = GuideTrail.layout({ p(0, 0, 0), p(7, 0, 0) }, 0, { startGap = 2, endGap = 6 })
		expect(#arrows).toBe(0)
	end)

	it("caps the visible length and the arrow count", function()
		local long = { p(0, 0, 0), p(1000, 0, 0) }
		local byLength =
			GuideTrail.layout(long, 0, { spacing = 5, startGap = 0, endGap = 0, maxLength = 20, maxCount = 100 })
		expect(byLength[#byLength].x <= 20 + 1e-6).toBe(true)
		local byCount =
			GuideTrail.layout(long, 0, { spacing = 5, startGap = 0, endGap = 0, maxLength = 1000, maxCount = 7 })
		expect(#byCount).toBe(7)
	end)

	it("fades arrows in near the player and out near the end", function()
		local arrows = GuideTrail.layout(
			STRAIGHT,
			0,
			{ spacing = 2, startGap = 0, endGap = 0, fadeIn = 10, fadeOut = 10, maxLength = 1000, maxCount = 100 }
		)
		expect(arrows[1].alpha).toBeCloseTo(0) -- at the player
		expect(arrows[3].alpha).toBeCloseTo(0.4) -- 4 studs in
		expect(arrows[13].alpha).toBeCloseTo(1) -- the middle
		expect(arrows[#arrows].alpha).toBeCloseTo(0) -- at the end
	end)

	it("follows a route with corners and points along each segment", function()
		local route = { p(0, 0, 0), p(10, 0, 0), p(10, 0, 10) }
		local arrows = GuideTrail.layout(route, 0, PLAIN)
		-- 0, 5, 10 on the first leg, then 15 and 20 turn the corner
		expect(#arrows).toBe(5)
		expect(arrows[4].x).toBeCloseTo(10)
		expect(arrows[4].z).toBeCloseTo(5)
		expect(arrows[4].dirX).toBeCloseTo(0)
		expect(arrows[4].dirZ).toBeCloseTo(1)
	end)

	it("interpolates height along the route", function()
		local arrows = GuideTrail.layout({ p(0, 0, 0), p(10, 10, 0) }, 0, PLAIN)
		expect(arrows[2].y).toBeCloseTo(arrows[2].x)
	end)

	it("skips vertical segments, which have no ground direction", function()
		local arrows = GuideTrail.layout({ p(0, 0, 0), p(0, 10, 0), p(10, 10, 0) }, 0, PLAIN)
		for _, arrow in arrows do
			expect(arrow.dirX).toBeCloseTo(1)
		end
	end)
end)

describe("GuideTrail.advance", function()
	it("moves the phase by speed per second and wraps at the spacing", function()
		expect(GuideTrail.advance(0, 0.5, { speed = 6, spacing = 4 })).toBeCloseTo(3)
		expect(GuideTrail.advance(3, 0.5, { speed = 6, spacing = 4 })).toBeCloseTo(2)
	end)
end)

describe("GuideTrail.length", function()
	it("sums the segments", function()
		expect(GuideTrail.length({ p(0, 0, 0), p(3, 4, 0), p(3, 4, 10) })).toBeCloseTo(15)
	end)
end)
