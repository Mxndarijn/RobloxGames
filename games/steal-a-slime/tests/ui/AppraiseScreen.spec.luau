--!strict
-- My Plot's Appraise screen (src/ui/Panels/Plot.luau with AppraiseView): the slime, its size tape and odds,
-- the hold-to-reroll request (one at a time, greyed out when it can't help or can't be paid), the was -> now
-- card from the server's answer, and a refusal's reason.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Enum = roblox.Enum

-- One full hold on a button. The caller turns virtual time on (and off), so timers survive between holds.
local function holdOnce(button: any)
	UiHarness.fire(button, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
	UiHarness.advance(Config.HOLD_CONFIRM_SECONDS + 0.1)
	UiHarness.renderStep()
	UiHarness.advance(1)
end

local function hold(button: any)
	UiHarness.virtualTime(true)
	holdOnce(button)
	UiHarness.virtualTime(false)
end

local function view(size: number, income: number, cost: number, stolenBy: number?): any
	return {
		slime = Fixtures.slime("goo", 3, { size = size }),
		income = income,
		sellPrice = cost * 3,
		appraiseCost = cost,
		stolenBy = stolenBy,
	}
end

local function state(v: any, cash: number): any
	return { slimes = { v }, padsUnlocked = 4, incomePerSec = v.income, cash = cash }
end

local function setup(size: number, cash: number?): (any, { any }, { number })
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
		ask = function(action: string, callback: any, ...: any)
			table.insert(requests, { action = action, callback = callback, args = { ... } })
		end,
		relayout = function()
			relayouts[1] += 1
		end,
	}
	local panel = UiHarness.ui("Panels/Plot").new(UiHarness.root(), c)
	panel.setOpen(true)
	panel.update(state(view(size, 1000, 1500), cash or 100_000))
	return panel, requests, relayouts
end

local function find(panel: any, name: string): any
	return UiHarness.find(panel.frame, name)
end

local function openScreen(panel: any)
	UiHarness.fire(UiHarness.find(find(panel, "goo"), "Appraise"), "Activated")
end

local function answer(beforeSize: number, afterSize: number, incomeBefore: number, incomeAfter: number): any
	return {
		ok = true,
		appraisal = {
			slimeId = "goo",
			kind = "size",
			cost = 1500,
			beforeSize = beforeSize,
			afterSize = afterSize,
			incomeBefore = incomeBefore,
			incomeAfter = incomeAfter,
			costAfter = 1080,
		},
	}
end

describe("Appraise screen", function()
	it("swaps the list for the slime, its size on the tape and the odds", function()
		local panel, _, relayouts = setup(1.97)
		openScreen(panel)
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
		expect(find(panel, "RerollSize").AutoButtonColor).toBe(true)
		expect(find(panel, "Result").Visible).toBe(false)
		expect(find(panel, "Status").Visible).toBe(false)
		-- The card is sized to the screen, not to the hidden list.
		expect(find(panel, "AppraisePopup").Size.Y.Offset > 300).toBe(true)
	end)
	it("rerolls on a hold and shows the server's was -> now at once", function()
		local panel, requests, relayouts = setup(1.97)
		openScreen(panel)
		hold(find(panel, "RerollSize"))
		expect(#requests).toBe(1)
		expect(requests[1].action).toBe("Appraise")
		expect(requests[1].args[1]).toBe("goo")
		expect(requests[1].args[2]).toBe("size")
		expect(find(panel, "RerollSize").Text).toBe("Rerolling...")
		local before = relayouts[1]
		requests[1].callback(answer(1.97, 1.42, 1000, 721))
		-- The answer shows before the State push with the new size, with the server's income and price.
		expect(find(panel, "Result").Visible).toBe(true)
		expect(relayouts[1] > before).toBe(true)
		expect(find(panel, "SizeChip").Text).toBe("1.42")
		expect(find(panel, "WasSize").Text).toBe("1.97")
		expect(find(panel, "NowSize").Text).toBe("1.42")
		expect(find(panel, "WasIncome").Text).toBe("$1K/s")
		expect(find(panel, "NowIncome").Text).toBe("$721/s")
		expect(find(panel, "RerollSize").Text).toBe("Reroll for $1.08K")
		expect(find(panel, "WasPin").Visible).toBe(true)
		expect(find(panel, "Rule").Visible).toBe(false)
		panel.update(state(view(1.42, 721, 1080), 98_500))
		expect(find(panel, "Result").Visible).toBe(true)
		expect(find(panel, "NowIncome").Text).toBe("$721/s")
		expect(find(panel, "RerollSize").Text).toBe("Reroll for $1.08K")
	end)
	it("greys out Reroll at the biggest size: it can't roll bigger", function()
		local panel, requests = setup(Config.MAX_SIZE)
		openScreen(panel)
		local btn = find(panel, "RerollSize")
		expect(btn.Text).toBe("Already the biggest size")
		expect(btn.AutoButtonColor).toBe(false)
		expect(string.find(find(panel, "Odds").Text, "No chance", 1, true) ~= nil).toBe(true)
		hold(btn)
		expect(#requests).toBe(0)
	end)
	it("greys out Reroll when the player can't pay for it, and frees it once they can", function()
		local panel, requests = setup(1.2, 1499)
		openScreen(panel)
		local btn = find(panel, "RerollSize")
		expect(btn.Text).toBe("Need $1.5K to reroll")
		expect(btn.AutoButtonColor).toBe(false)
		hold(btn)
		expect(#requests).toBe(0)
		panel.update(state(view(1.2, 1000, 1500), 1500))
		expect(btn.Text).toBe("Reroll for $1.5K")
		expect(btn.AutoButtonColor).toBe(true)
		hold(btn)
		expect(#requests).toBe(1)
	end)
	it("shows the server's reason when it refuses a reroll", function()
		local panel, requests = setup(1.2)
		openScreen(panel)
		hold(find(panel, "RerollSize"))
		requests[1].callback({ ok = false, message = "not enough cash" })
		local status = find(panel, "Status")
		expect(status.Visible).toBe(true)
		expect(status.Text).toBe("Not enough cash for this reroll.")
		expect(find(panel, "Result").Visible).toBe(false)
		expect(find(panel, "RerollSize").Text).toBe("Reroll for $1.5K")
		-- Another try clears it.
		hold(find(panel, "RerollSize"))
		expect(#requests).toBe(2)
		expect(status.Visible).toBe(false)
		requests[2].callback({ ok = false, message = "slime is busy" })
		expect(status.Text).toBe("This slime is busy right now.")
		requests[2].callback(nil)
		expect(status.Text).toBe("The reroll didn't go through. Try again.")
	end)
	it("sends one request for two holds while the first is in flight, and frees up after the wait", function()
		local panel, requests = setup(1.2)
		openScreen(panel)
		local btn = find(panel, "RerollSize")
		UiHarness.virtualTime(true)
		holdOnce(btn)
		expect(btn.AutoButtonColor).toBe(false)
		holdOnce(btn)
		expect(#requests).toBe(1)
		-- No answer at all: after the wait the button takes holds again.
		UiHarness.advance(Config.HOLD_CONFIRM_SECONDS * 10)
		expect(btn.AutoButtonColor).toBe(true)
		holdOnce(btn)
		UiHarness.virtualTime(false)
		expect(#requests).toBe(2)
	end)
	it("a second reroll before the State push takes its was values from the server", function()
		local panel, requests = setup(1.2)
		openScreen(panel)
		hold(find(panel, "RerollSize"))
		requests[1].callback(answer(1.2, 1.6, 1000, 1333))
		hold(find(panel, "RerollSize"))
		expect(#requests).toBe(2)
		requests[2].callback(answer(1.6, 1.0, 1333, 833))
		expect(find(panel, "WasSize").Text).toBe("1.60")
		expect(find(panel, "WasIncome").Text).toBe("$1.33K/s")
		expect(find(panel, "NowSize").Text).toBe("1.00")
		expect(find(panel, "NowIncome").Text).toBe("$833/s")
		expect(find(panel, "SizeChip").Text).toBe("1.00")
		-- A late State push from before the rerolls doesn't undo the answer.
		panel.update(state(view(1.2, 1000, 1500), 97_000))
		expect(find(panel, "SizeChip").Text).toBe("1.00")
	end)
	it("closes back to the list when the slime is stolen or gone", function()
		local panel = setup(1.2)
		openScreen(panel)
		panel.update(state(view(1.2, 0, 1500, 42), 100_000))
		expect(find(panel, "AppraisePopup").Visible).toBe(false)
		expect(find(panel, "List").Visible).toBe(true)
		expect(find(panel, "Title").Text).toBe("My Plot")
		panel.update(state(view(1.2, 1000, 1500), 100_000))
		openScreen(panel)
		panel.update({ slimes = {}, padsUnlocked = 4, incomePerSec = 0, cash = 100_000 })
		expect(find(panel, "AppraisePopup").Visible).toBe(false)
	end)
	it("keeps the slime's preview on a State push that doesn't change it", function()
		local panel = setup(1.2)
		openScreen(panel)
		local preview = UiHarness.find(find(panel, "AppraisePopup"), "Preview")
		local look = preview:GetAttribute("Look")
		local children = preview:GetChildren()
		expect(look ~= nil).toBe(true)
		panel.update(state(view(1.2, 1000, 1500), 100_000))
		expect(preview:GetAttribute("Look")).toBe(look)
		local after = preview:GetChildren()
		expect(#after).toBe(#children)
		for i, child in children do
			expect(after[i] == child).toBe(true)
		end
	end)
	it("Back and closing the menu return to the list", function()
		local panel = setup(1.2)
		openScreen(panel)
		UiHarness.fire(find(panel, "Done"), "Activated")
		expect(find(panel, "AppraisePopup").Visible).toBe(false)
		expect(find(panel, "List").Visible).toBe(true)
		expect(find(panel, "Title").Text).toBe("My Plot")
		openScreen(panel)
		panel.setOpen(false)
		expect(find(panel, "AppraisePopup").Visible).toBe(false)
		expect(find(panel, "Title").Text).toBe("My Plot")
	end)
end)
