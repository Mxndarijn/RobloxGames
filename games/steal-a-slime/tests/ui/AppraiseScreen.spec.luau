--!strict
-- My Plot's Appraise screen (src/ui/Panels/Plot.luau with AppraiseView): the slime, its size tape and odds,
-- the hold-to-reroll request and the was -> now card.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Enum = roblox.Enum

local function hold(button: any)
	UiHarness.virtualTime(true)
	UiHarness.fire(button, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
	UiHarness.advance(Config.HOLD_CONFIRM_SECONDS + 0.1)
	UiHarness.renderStep()
	UiHarness.advance(1)
	UiHarness.virtualTime(false)
end

local function setup(size: number): (any, { any }, { number })
	local requests: { any } = {}
	local relayouts = { 0 }
	local c = {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		send = function() end,
		playerName = function()
			return "Tester"
		end,
		request = function(action: string, callback: any, ...: any)
			table.insert(requests, { action = action, callback = callback, args = { ... } })
		end,
		relayout = function()
			relayouts[1] += 1
		end,
	}
	local panel = UiHarness.ui("Panels/Plot").new(UiHarness.root(), c)
	panel.setOpen(true)
	local slime = Fixtures.slime("goo", 3, { size = size })
	panel.update({
		slimes = { { slime = slime, income = 1000, sellPrice = 5000, appraiseCost = 1500 } },
		padsUnlocked = 4,
		incomePerSec = 1000,
	})
	return panel, requests, relayouts
end

local function find(panel: any, name: string): any
	return UiHarness.find(panel.frame, name)
end

describe("Appraise screen", function()
	it("swaps the list for the slime, its size on the tape and the odds", function()
		local panel, _, relayouts = setup(1.97)
		UiHarness.fire(UiHarness.find(find(panel, "goo"), "Appraise"), "Activated")
		expect(find(panel, "AppraisePopup").Visible).toBe(true)
		expect(find(panel, "List").Visible).toBe(false)
		expect(find(panel, "Title").Text).toBe("Appraise")
		expect(relayouts[1] >= 1).toBe(true)
		expect(find(panel, "SizeChip").Text).toBe("1.97")
		local tag = UiHarness.find(find(panel, "NowPin"), "Tag")
		expect(tag.Text).toBe("1.97")
		expect(math.abs(find(panel, "NowPin").Position.X.Scale - 0.975) < 0.001).toBe(true)
		expect(string.find(find(panel, "Odds").Text, "2% chance", 1, true) ~= nil).toBe(true)
		expect(find(panel, "RerollSize").Text).toBe("Reroll for $1.5K")
		expect(find(panel, "Result").Visible).toBe(false)
		-- The card is sized to the screen, not to the hidden list.
		expect(find(panel, "AppraisePopup").Size.Y.Offset > 300).toBe(true)
	end)
	it("rerolls on a hold and shows was -> now once the new size arrives", function()
		local panel, requests, relayouts = setup(1.97)
		UiHarness.fire(UiHarness.find(find(panel, "goo"), "Appraise"), "Activated")
		hold(find(panel, "RerollSize"))
		expect(#requests).toBe(1)
		expect(requests[1].action).toBe("Appraise")
		expect(requests[1].args[1]).toBe("goo")
		expect(requests[1].args[2]).toBe("size")
		local before = relayouts[1]
		requests[1].callback({ ok = true, appraisal = { slimeId = "goo", beforeSize = 1.97, afterSize = 1.42 } })
		-- The answer shows at once, before the State push with the new size.
		expect(find(panel, "Result").Visible).toBe(true)
		expect(find(panel, "SizeChip").Text).toBe("1.42")
		panel.update({
			slimes = {
				{
					slime = Fixtures.slime("goo", 3, { size = 1.42 }),
					income = 721,
					sellPrice = 3600,
					appraiseCost = 1080,
				},
			},
			padsUnlocked = 4,
			incomePerSec = 721,
		})
		expect(find(panel, "Result").Visible).toBe(true)
		-- The card grew for the result card without waiting for a layout pass.
		expect(relayouts[1] > before).toBe(true)
		expect(find(panel, "WasSize").Text).toBe("1.97")
		expect(find(panel, "NowSize").Text).toBe("1.42")
		expect(find(panel, "WasPin").Visible).toBe(true)
		expect(find(panel, "Rule").Visible).toBe(false)
		expect(find(panel, "RerollSize").Text).toBe("Reroll for $1.08K")
	end)
	it("Back and closing the menu return to the list", function()
		local panel = setup(1.2)
		UiHarness.fire(UiHarness.find(find(panel, "goo"), "Appraise"), "Activated")
		UiHarness.fire(find(panel, "Done"), "Activated")
		expect(find(panel, "AppraisePopup").Visible).toBe(false)
		expect(find(panel, "List").Visible).toBe(true)
		expect(find(panel, "Title").Text).toBe("My Plot")
		UiHarness.fire(UiHarness.find(find(panel, "goo"), "Appraise"), "Activated")
		panel.setOpen(false)
		expect(find(panel, "AppraisePopup").Visible).toBe(false)
		expect(find(panel, "Title").Text).toBe("My Plot")
	end)
end)
