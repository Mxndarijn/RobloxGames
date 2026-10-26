--!strict
local HomePlotMarker = require("../src/visuals/shared/HomePlotMarker")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("HomePlotMarker.ownPlot", function()
	it("finds the plot the player owns", function()
		local plots = { { index = 1, owner = 0 }, { index = 2, owner = 42 }, { index = 3, owner = 7 } }
		expect(HomePlotMarker.ownPlot(plots, 7)).toBe(3)
		expect(HomePlotMarker.ownPlot(plots, 42)).toBe(2)
	end)
	it("is nil without a plot and never matches the empty owner 0", function()
		local plots = { { index = 1, owner = 0 }, { index = 2, owner = nil } }
		expect(HomePlotMarker.ownPlot(plots, 5)).toBeNil()
		expect(HomePlotMarker.ownPlot(plots, 0)).toBeNil()
	end)
end)

describe("HomePlotMarker.pastEdge", function()
	it("is 0 anywhere on the round floor, its edge included", function()
		expect(HomePlotMarker.pastEdge(0, 0, 40)).toBe(0)
		expect(HomePlotMarker.pastEdge(-40, 0, 40)).toBe(0)
		expect(HomePlotMarker.pastEdge(24, -32, 40)).toBe(0)
	end)
	it("measures straight out from the edge in every direction", function()
		expect(HomePlotMarker.pastEdge(50, 0, 40)).toBe(10)
		expect(HomePlotMarker.pastEdge(0, -45, 40)).toBe(5)
		expect(HomePlotMarker.pastEdge(30, 40, 40)).toBe(10)
	end)
	it("counts the old square plot's corners as off the round floor", function()
		expect(HomePlotMarker.pastEdge(39, 39, 40) > 15).toBe(true)
	end)
end)

describe("HomePlotMarker.rim", function()
	local radius = 40
	local rim = HomePlotMarker.rim(radius)
	it("goes all the way round in RIM_SEGMENTS equal strips", function()
		expect(#rim).toBe(HomePlotMarker.RIM_SEGMENTS)
		local step = 2 * math.pi / HomePlotMarker.RIM_SEGMENTS
		for k, seg in rim do
			expect(math.abs(seg.angle - (k - 1) * step) < 1e-9).toBe(true)
		end
	end)
	it("keeps the ring inside the floor with its outer edge on the floor's edge", function()
		for _, seg in rim do
			local outer = seg.mid + HomePlotMarker.RIM_WIDTH / 2
			expect(math.abs(outer - radius) < 1e-9).toBe(true)
			-- the strip's outer corners stay within a hair of the round edge
			local corner = math.sqrt(outer ^ 2 + (seg.length / 2) ^ 2)
			expect(corner - radius < 0.2).toBe(true)
		end
	end)
	it("leaves no gap between neighbouring strips", function()
		local seg = rim[1]
		local outer = seg.mid + HomePlotMarker.RIM_WIDTH / 2
		local chord = 2 * outer * math.sin(math.pi / HomePlotMarker.RIM_SEGMENTS)
		expect(seg.length >= chord).toBe(true)
	end)
end)

describe("HomePlotMarker.fade", function()
	it("hides the markers while standing on the plot", function()
		expect(HomePlotMarker.fade(0)).toBe(0)
	end)
	it("fades in over FADE_BAND studs past the edge", function()
		local band = HomePlotMarker.FADE_BAND
		expect(HomePlotMarker.fade(band / 2)).toBe(0.5)
		expect(HomePlotMarker.fade(band)).toBe(1)
		expect(HomePlotMarker.fade(500)).toBe(1)
	end)
end)

describe("HomePlotMarker.edgeRect", function()
	it("keeps the full insets on a desktop screen", function()
		local r = HomePlotMarker.edgeRect(1920, 1080)
		local inset = HomePlotMarker.EDGE_INSETS
		expect(r.left).toBe(inset.left)
		expect(r.top).toBe(inset.top)
		expect(r.right).toBe(1920 - inset.right)
		expect(r.bottom).toBe(1080 - inset.bottom)
	end)
	it("leaves a landscape phone a box at least half the screen tall, not a strip at head height", function()
		for _, v in { { 800, 370 }, { 740, 340 }, { 844, 390 } } do
			local r = HomePlotMarker.edgeRect(v[1], v[2])
			expect(r.bottom - r.top >= v[2] * 0.45).toBe(true)
			expect(r.right - r.left >= v[1] * 0.6).toBe(true)
		end
	end)
end)

describe("HomePlotMarker.arrowScale", function()
	it("is 1 on desktop and smaller, but not tiny, on phones", function()
		expect(HomePlotMarker.arrowScale(1080)).toBe(1)
		expect(HomePlotMarker.arrowScale(370) < 1).toBe(true)
		expect(HomePlotMarker.arrowScale(200)).toBe(HomePlotMarker.ARROW_MIN_SCALE)
	end)
end)
