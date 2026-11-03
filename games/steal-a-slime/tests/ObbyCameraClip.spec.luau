--!strict
-- Keeping the camera out of the obby's non-collide course parts (src/visuals/shared/ObbyCameraClip.luau): which parts
-- stop the camera, where the line from the focus to the camera enters a part, and how far in front of the face it stops.
local Config = require("../src/shared/Config")
local ObbyCameraClip = require("../src/visuals/shared/ObbyCameraClip")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local TUNE = Config.OBBY.CAMERA_CLIP
local EPS = 1e-6

describe("ObbyCameraClip.blocks", function()
	it("stops the camera at the course's lava floors", function()
		expect(ObbyCameraClip.blocks(107, 6, 24, 0.25)).toBe(true)
		expect(ObbyCameraClip.blocks(57.25, 2, 24, 0.25)).toBe(true)
		expect(ObbyCameraClip.blocks(16, 0.6, 24, 0.25)).toBe(true)
	end)

	it("lets the camera past small parts: keys and rolling blobs", function()
		expect(ObbyCameraClip.blocks(5, 5, 5, 0.25)).toBe(false)
		expect(ObbyCameraClip.blocks(1, 1, 1, 0)).toBe(false)
	end)

	it("lets the camera past thin banners and see-through zones", function()
		expect(ObbyCameraClip.blocks(0.4, 8, 24, 0)).toBe(false)
		expect(ObbyCameraClip.blocks(20, 20, 20, TUNE.MAX_TRANSPARENCY)).toBe(false)
		expect(ObbyCameraClip.blocks(20, 20, 20, 1)).toBe(false)
	end)
end)

describe("ObbyCameraClip.entry", function()
	it("finds where the line enters the box", function()
		-- focus 10 studs above a 2-thick slab's centre, camera 20 below the focus: enters the top face at y = 1
		local t = ObbyCameraClip.entry(0, 10, 0, 0, -20, 0, 5, 1, 5)
		expect(t ~= nil).toBe(true)
		expect(math.abs((t :: number) - 9 / 20) < EPS).toBe(true)
	end)

	it("enters through the side on a slanted line", function()
		local t = ObbyCameraClip.entry(-10, 0, 0, 20, 2, 0, 2, 2, 2)
		expect(t ~= nil).toBe(true)
		expect(math.abs((t :: number) - 8 / 20) < EPS).toBe(true)
	end)

	it("misses a box beside the line or beyond the camera", function()
		expect(ObbyCameraClip.entry(0, 10, 0, 0, -5, 0, 5, 1, 5)).toBe(nil) -- camera stops above the slab
		expect(ObbyCameraClip.entry(10, 10, 0, 0, -20, 0, 5, 1, 5)).toBe(nil) -- slab off to the side
		expect(ObbyCameraClip.entry(0, 10, 0, 0, 20, 0, 5, 1, 5)).toBe(nil) -- camera looking away from it
	end)

	it("ignores a box the focus is already inside", function()
		expect(ObbyCameraClip.entry(0, 0, 0, 0, 20, 0, 5, 1, 5)).toBe(nil)
	end)

	it("handles a line parallel to a face", function()
		expect(ObbyCameraClip.entry(-10, 0, 0, 20, 0, 0, 2, 2, 2)).toBe(0.4)
		expect(ObbyCameraClip.entry(-10, 3, 0, 20, 0, 0, 2, 2, 2)).toBe(nil)
	end)
end)

describe("ObbyCameraClip.distance", function()
	it("stops MARGIN in front of the face", function()
		expect(math.abs(ObbyCameraClip.distance(20, 0.45) - (9 - TUNE.MARGIN)) < EPS).toBe(true)
	end)

	it("never goes past the focus", function()
		expect(ObbyCameraClip.distance(20, 0)).toBe(0)
		expect(ObbyCameraClip.distance(0.2, 1)).toBe(0)
	end)
end)
