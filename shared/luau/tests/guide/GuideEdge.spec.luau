--!strict
local GuideEdge = require("../../src/guide/GuideEdge")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local W, H, M = 1000, 600, 50

describe("GuideEdge.place", function()
	it("hides the pointer while the target is on screen", function()
		expect(GuideEdge.place(500, 300, true, W, H, M).visible).toBe(false)
	end)

	it("pins a target off the right edge to the right margin, pointing right", function()
		local placed = GuideEdge.place(3000, 300, true, W, H, M)
		expect(placed.visible).toBe(true)
		expect(placed.x).toBeCloseTo(W - M)
		expect(placed.y).toBeCloseTo(300)
		expect(placed.angle).toBeCloseTo(0)
	end)

	it("pins a target above the screen to the top margin, pointing up", function()
		local placed = GuideEdge.place(500, -900, true, W, H, M)
		expect(placed.y).toBeCloseTo(M)
		expect(placed.angle).toBeCloseTo(-90)
	end)

	it("flips a target behind the camera", function()
		-- behind and projected to the right means it is really to the left
		local placed = GuideEdge.place(700, 300, false, W, H, M)
		expect(placed.visible).toBe(true)
		expect(placed.x).toBeCloseTo(M)
		expect(math.abs(placed.angle)).toBeCloseTo(180)
	end)

	it("points down for a target straight behind", function()
		local placed = GuideEdge.place(500, 300, false, W, H, M)
		expect(placed.y).toBeCloseTo(H - M)
		expect(placed.angle).toBeCloseTo(90)
	end)

	it("shows the pointer for an on-screen point inside the margin band", function()
		expect(GuideEdge.place(10, 300, true, W, H, M).visible).toBe(true)
	end)
end)
