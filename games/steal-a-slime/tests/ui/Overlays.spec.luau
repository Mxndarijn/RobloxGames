--!strict
-- Menu cards, panel frames and popup overlays start hidden and stay hidden
-- after a State update until their menu opens.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
	}
end

local MENUS = {
	Plot = "Plot",
	Merge = "Merge",
	Shop = "Shop",
	Rebirth = "Rebirth",
	Goals = "Goals",
	Dex = "Dex",
	Leaders = "Leaderboard",
	Codes = "Codes",
	Guide = "Guide",
	Welcome = "Welcome",
}

describe("overlays start hidden and follow their menu", function()
	it("every menu card is created hidden, and stays hidden after a State update", function()
		for _, file in MENUS do
			local panel = UiHarness.ui(`Panels/{file}`).new(UiHarness.root(), ctx())
			expect(panel.frame.Visible).toBe(false)
			if panel.update then
				pcall(
					panel.update,
					{ cash = 0, slimes = {}, rebirths = 0, dex = { found = 0, total = 50, entries = {} } }
				)
			end
			expect(panel.frame.Visible).toBe(false)
		end
	end)
	it("Widgets.panel frames are hidden by default", function()
		local Widgets = UiHarness.ui("Widgets")
		local panel = Widgets.panel(UiHarness.root(), "P", "T", "x", roblox.Color3.new(1, 1, 1))
		expect(panel.frame.Visible).toBe(false)
	end)
	it("popup overlays (daily, tutorial, hint) start hidden", function()
		local root = UiHarness.root()
		UiHarness.ui("Panels/DailyPopup").new(root, ctx())
		UiHarness.ui("Panels/TutorialOverlay").new(root, ctx())
		UiHarness.ui("Panels/HintOverlay").new(root)
		for _, name in { "DailyPopup", "HintRing" } do
			expect(UiHarness.find(root, name).Visible).toBe(false)
		end
	end)
end)
