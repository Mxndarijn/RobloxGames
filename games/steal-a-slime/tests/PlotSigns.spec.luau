--!nocheck
-- Plot Signs (v10 bug: all 8 plot Signs were blank boards, nothing wrote
-- text). Pure text from PlotSigns.lines, the SurfaceGuis PlotSigns.ensure
-- builds with @lune/roblox, and the Sign of a real built-place plot.
local roblox = require("@lune/roblox")

local PlotSigns = require("../src/server/PlotSigns")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DEPS = { Instance = roblox.Instance, Enum = roblox.Enum, UDim2 = roblox.UDim2, Color3 = roblox.Color3 }

local function owner(name, cash, rebirths, stolen)
	return { name = name, data = { cash = cash, rebirths = rebirths, totalStolen = stolen } }
end

local function texts(sign)
	local out = {}
	for _, d in sign:GetDescendants() do
		if d:IsA("TextLabel") then
			table.insert(out, d.Text)
		end
	end
	return out
end

describe("PlotSigns.lines", function()
	it("shows a placeholder on free plots, never blank", function()
		local lines = PlotSigns.lines(3, nil)
		expect(lines.title).toBe("Plot 3")
		expect(lines.stats).toBe("Empty plot")
	end)
	it("shows the owner's name, cash, rebirths and steals", function()
		local lines = PlotSigns.lines(1, owner("Merijn", 12345, 2, 1))
		expect(lines.title).toBe("Merijn's Plot")
		expect(string.find(lines.stats, "$12.3K", 1, true) ~= nil).toBe(true)
		expect(string.find(lines.stats, "2 Rebirths", 1, true) ~= nil).toBe(true)
		expect(string.find(lines.stats, "1 Steal", 1, true) ~= nil).toBe(true)
		expect(string.find(lines.stats, "1 Steals", 1, true)).toBe(nil)
	end)
end)

describe("PlotSigns.apply", function()
	it("adds a SurfaceGui with Title / Stats on the front and back of a bare Sign", function()
		local sign = roblox.Instance.new("Part")
		sign.Name = "Sign"
		PlotSigns.apply(sign, PlotSigns.lines(2, nil), DEPS)
		for _, face in PlotSigns.FACES do
			local gui = sign:FindFirstChild(PlotSigns.GUI_PREFIX .. face)
			expect(gui ~= nil).toBe(true)
			expect(gui.Face).toBe(roblox.Enum.NormalId[face])
			expect(gui.Title.Text).toBe("Plot 2")
			expect(gui.Stats.Text).toBe("Empty plot")
		end
	end)
	it("updates in place when the owner changes (no duplicate guis)", function()
		local sign = roblox.Instance.new("Part")
		PlotSigns.apply(sign, PlotSigns.lines(1, nil), DEPS)
		PlotSigns.apply(sign, PlotSigns.lines(1, owner("Ann", 50, 0, 0)), DEPS)
		expect(#sign:GetChildren()).toBe(#PlotSigns.FACES)
		local all = texts(sign)
		expect(#all).toBe(2 * #PlotSigns.FACES)
		for _, text in all do
			expect(text ~= "" and text ~= "Plot 1" and text ~= "Empty plot").toBe(true)
		end
		expect(sign[PlotSigns.GUI_PREFIX .. "Front"].Title.Text).toBe("Ann's Plot")
	end)
end)
