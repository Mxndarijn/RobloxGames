--!strict
local HomePlotMarker = require("../src/visuals/shared/HomePlotMarker")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local VIEW = { width = 1000, height = 600 }

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

describe("HomePlotMarker.edgeArrow", function()
	it("is nil while the plot is on screen", function()
		expect(HomePlotMarker.edgeArrow(VIEW, { x = 500, y = 300, inFront = true }, 50)).toBeNil()
		expect(HomePlotMarker.edgeArrow(VIEW, { x = 60, y = 60, inFront = true }, 50)).toBeNil()
	end)
	it("pins to the right edge for a point off to the right", function()
		local arrow = HomePlotMarker.edgeArrow(VIEW, { x = 3000, y = 300, inFront = true }, 50) :: any
		expect(arrow.x).toBe(950)
		expect(arrow.y).toBe(300)
		expect(arrow.angle).toBe(0)
	end)
	it("pins to the top edge for a point above", function()
		local arrow = HomePlotMarker.edgeArrow(VIEW, { x = 500, y = -900, inFront = true }, 50) :: any
		expect(arrow.x).toBe(500)
		expect(arrow.y).toBe(50)
		expect(arrow.angle).toBe(-90)
	end)
	it("mirrors a point behind the camera", function()
		-- Projects to the right of centre, but it is behind us: the arrow points left.
		local arrow = HomePlotMarker.edgeArrow(VIEW, { x = 700, y = 300, inFront = false }, 50) :: any
		expect(arrow.x).toBe(50)
		expect(math.abs(arrow.angle)).toBe(180)
	end)
	it("points down when the plot is straight behind", function()
		local arrow = HomePlotMarker.edgeArrow(VIEW, { x = 500, y = 300, inFront = false }, 50) :: any
		expect(arrow.x).toBe(500)
		expect(arrow.y).toBe(550)
		expect(arrow.angle).toBe(90)
	end)
	it("keeps the arrow inside the margin box", function()
		for _, p in { { x = -5000, y = 4000 }, { x = 9000, y = -20 }, { x = 400, y = 9999 } } do
			local arrow = HomePlotMarker.edgeArrow(VIEW, { x = p.x, y = p.y, inFront = true }, 50) :: any
			expect(arrow.x >= 50 - 1e-6 and arrow.x <= 950 + 1e-6).toBe(true)
			expect(arrow.y >= 50 - 1e-6 and arrow.y <= 550 + 1e-6).toBe(true)
		end
	end)
end)

describe("HomePlotMarker.edgeArrow insets", function()
	local insets = { left = 200, right = 100, top = 100, bottom = 200 }
	it("keeps the arrow inside the inset box, clear of the HUD", function()
		local arrow = HomePlotMarker.edgeArrow(VIEW, { x = -4000, y = 250, inFront = true }, insets) :: any
		expect(arrow.x).toBe(200)
		expect(arrow.angle).toBe(180)
		local low = HomePlotMarker.edgeArrow(VIEW, { x = 550, y = 9000, inFront = true }, insets) :: any
		expect(low.y).toBe(400)
	end)
	it("treats a point inside the box as on screen", function()
		expect(HomePlotMarker.edgeArrow(VIEW, { x = 300, y = 350, inFront = true }, insets)).toBeNil()
	end)
	it("defaults to EDGE_INSETS", function()
		local arrow = HomePlotMarker.edgeArrow(VIEW, { x = 9999, y = 300, inFront = true }) :: any
		expect(arrow.x).toBe(VIEW.width - HomePlotMarker.EDGE_INSETS.right)
	end)
end)
