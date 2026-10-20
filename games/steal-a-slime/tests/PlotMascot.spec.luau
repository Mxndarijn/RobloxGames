--!strict
-- The jar tower's mascot (PlotMascot, CONTRACT.md §5.3): it sits on the top jar's lid, grows with every jar and wears
-- the crown only on the full tower.
local Config = require("../src/shared/Config")
local PlotMascot = require("../src/visuals/shared/PlotMascot")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function fakePlot(floors: { number }): any
	local present = {}
	for _, f in floors do
		present[`Floor_{f}`] = true
	end
	return {
		FindFirstChild = function(_, name: string)
			return if present[name] then {} else nil
		end,
	}
end

describe("PlotMascot", function()
	it("counts the jars standing: 1 on a free plot, the highest Floor_<f> otherwise", function()
		expect(PlotMascot.version(fakePlot({}))).toBe(1)
		expect(PlotMascot.version(fakePlot({ 2 }))).toBe(2)
		expect(PlotMascot.version(fakePlot({ 2, 3, 4 }))).toBe(4)
	end)
	it("sits on the top jar's lid and grows with every version", function()
		local last = 0
		for v = 1, #Config.BASE_FLOORS do
			local pose = PlotMascot.pose(v)
			expect(pose.lidY).toBe(WorldLayout.floorTop(v + 1))
			expect(pose.scale > last).toBe(true)
			last = pose.scale
		end
	end)
	it("wears the crown only on the full tower", function()
		for v = 1, #Config.BASE_FLOORS do
			expect(PlotMascot.pose(v).crown).toBe(v == #Config.BASE_FLOORS)
		end
	end)
	it("fits the biggest mascot on the smallest lid", function()
		local top = #Config.BASE_FLOORS
		local d = PlotMascot.BODY * PlotMascot.pose(top).scale
		expect(d / 2 < WorldLayout.jarRadius(top)).toBe(true)
	end)
end)
