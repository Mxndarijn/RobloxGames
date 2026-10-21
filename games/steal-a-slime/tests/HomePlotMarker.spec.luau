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
	it("is 0 anywhere on the floor, corners and edges included", function()
		expect(HomePlotMarker.pastEdge(0, 0, 40, 30)).toBe(0)
		expect(HomePlotMarker.pastEdge(39, -29, 40, 30)).toBe(0)
		expect(HomePlotMarker.pastEdge(-40, 30, 40, 30)).toBe(0)
	end)
	it("measures straight out from a side and diagonally from a corner", function()
		expect(HomePlotMarker.pastEdge(50, 0, 40, 30)).toBe(10)
		expect(HomePlotMarker.pastEdge(0, -45, 40, 30)).toBe(15)
		expect(HomePlotMarker.pastEdge(43, 34, 40, 30)).toBe(5)
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
