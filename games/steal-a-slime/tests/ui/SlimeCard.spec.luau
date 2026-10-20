--!strict
-- The slime card (src/ui/Panels/Plot.luau): a pad slime's Manage prompt focuses the panel on that one slime.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function view(id: string, tier: number, income: number): any
	return { slime = Fixtures.slime(id, tier, { size = 1.2 }), income = income, sellPrice = income * 3 }
end

local function two(): any
	return { slimes = { view("goo", 3, 1000), view("blob", 2, 500) }, padsUnlocked = 4, incomePerSec = 1500 }
end

local function setup(): any
	local c = {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		send = function() end,
		playerName = function()
			return "Tester"
		end,
	}
	local panel = UiHarness.ui("Panels/Plot").new(UiHarness.root(), c)
	panel.setOpen(true)
	panel.update(two())
	return panel
end

local function find(panel: any, name: string): any
	return UiHarness.find(panel.frame, name)
end

describe("Slime card (a pad slime's Manage prompt focuses the panel on it)", function()
	it("shows only that slime's row under the My Slime title", function()
		local panel = setup()
		expect(find(panel, "blob") ~= nil).toBe(true)
		panel.focus("goo")
		expect(find(panel, "Title").Text).toBe("My Slime")
		expect(find(panel, "goo") ~= nil).toBe(true)
		expect(find(panel, "blob")).toBeNil()
		panel.update(two())
		expect(find(panel, "blob")).toBeNil()
	end)
	it("has Favorite and Sell on a slime's row, and no Appraise", function()
		local panel = setup()
		panel.focus("goo")
		local row = find(panel, "goo")
		expect(UiHarness.find(row, "Favorite") ~= nil).toBe(true)
		expect(UiHarness.find(row, "Sell").Visible).toBe(true)
		expect(UiHarness.find(row, "Appraise")).toBeNil()
	end)
	it("closes when the slime leaves the plot, and closing forgets the focus", function()
		local panel = setup()
		panel.frame.Visible = true
		panel.focus("goo")
		panel.update({ slimes = {}, padsUnlocked = 4, incomePerSec = 0 })
		expect(panel.frame.Visible).toBe(false)
		expect(find(panel, "Title").Text).toBe("My Plot")
		panel.focus("goo")
		panel.setOpen(false)
		panel.update(two())
		expect(find(panel, "Title").Text).toBe("My Plot")
		expect(find(panel, "blob") ~= nil).toBe(true)
	end)
end)
