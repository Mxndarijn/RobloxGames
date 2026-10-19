--!strict
-- Daily reward popup helpers (src/ui/Daily.luau).
local Daily = require("../../src/ui/Daily")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Daily.dayOf", function()
	it("decodes the claim day from amount = base * day * multiplier", function()
		expect(Daily.dayOf({ available = true, streak = 2, amount = 300 }, 100, 1, 7)).toBe(3)
		expect(Daily.dayOf({ available = true, streak = 0, amount = 150 }, 100, 1.5, 7)).toBe(1)
		-- floored amounts still round to the right day
		expect(Daily.dayOf({ available = true, streak = 3, amount = 599 }, 100, 1.5, 7)).toBe(4)
	end)
	it("sees a reset streak through the amount", function()
		expect(Daily.dayOf({ available = true, streak = 5, amount = 100 }, 100, 1, 7)).toBe(1)
	end)
	it("clamps to 1..cap", function()
		expect(Daily.dayOf({ available = true, streak = 9, amount = 1000 }, 100, 1, 7)).toBe(7)
		expect(Daily.dayOf({ available = false, streak = 0, amount = 0 }, 100, 1, 7)).toBe(1)
	end)
	it("falls back to the stored streak when the amount can't be decoded", function()
		expect(Daily.dayOf({ available = true, streak = 2, amount = 0 }, 0, 1, 7)).toBe(3)
		expect(Daily.dayOf({ available = false, streak = 4, amount = 0 }, 100, 1, 7)).toBe(4)
	end)
end)

describe("Daily.track", function()
	it("marks earlier days claimed, today, and upcoming", function()
		local cells = Daily.track(3, 5, true)
		expect(#cells).toBe(5)
		expect(cells[1].state).toBe("claimed")
		expect(cells[2].state).toBe("claimed")
		expect(cells[3].state).toBe("today")
		expect(cells[4].state).toBe("upcoming")
	end)
	it("shows today as claimed once nothing is available", function()
		expect(Daily.track(3, 5, false)[3].state).toBe("claimed")
	end)
end)

describe("Daily.reward", function()
	it("pays base * day * multiplier, floored", function()
		expect(Daily.reward(1, 100, 1)).toBe(100)
		expect(Daily.reward(7, 100, 1)).toBe(700)
		expect(Daily.reward(3, 100, 1.5)).toBe(450)
		expect(Daily.reward(3, 33, 1.5)).toBe(148)
	end)
end)

describe("Daily.shouldAutoOpen", function()
	it("opens on the first available snapshot and on each false -> true edge only", function()
		expect(Daily.shouldAutoOpen(nil, true)).toBe(true)
		expect(Daily.shouldAutoOpen(false, true)).toBe(true)
		expect(Daily.shouldAutoOpen(true, true)).toBe(false)
		expect(Daily.shouldAutoOpen(nil, false)).toBe(false)
	end)
end)

describe("Daily popup card", function()
	local Config = require("../../src/shared/Config")
	local Layout = require("../../src/ui/Layout")
	local LayoutAssert = require("./LayoutAssert")
	local UiHarness = require("./UiHarness")

	local function build(): (any, { any })
		local sent = {}
		local ctx: any = {
			Config = Config,
			send = function(...)
				table.insert(sent, { ... })
			end,
		}
		return UiHarness.ui("Panels/DailyPopup").new(UiHarness.root(), ctx), sent
	end
	local function today(day: number): any
		return { daily = { available = true, streak = day - 1, amount = Config.DAILY_BASE * day } }
	end

	it("uses the shared panel frame and its red X, which closes the popup", function()
		local Widgets = UiHarness.ui("Widgets")
		local popup = build()
		local close = UiHarness.find(popup.frame, "Close")
		expect(close.BackgroundColor3).toBe(Widgets.Theme.Bad)
		popup.open()
		UiHarness.fire(close, "Activated")
		expect(popup.isOpen()).toBe(false)
	end)
	it("today is the gold tile, level with the other days; short labels between Day N and Day 7", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local popup = build()
		popup.update(today(1))
		local cap = Config.DAILY_STREAK_CAP
		local first = UiHarness.find(popup.frame, "Day1")
		expect(first.BackgroundColor3).toBe(Theme.Gold)
		expect(UiHarness.find(first, "DayLabel").Text).toBe("Day 1")
		for day = 2, cap do
			local tile = UiHarness.find(popup.frame, `Day{day}`)
			expect(tile.BackgroundColor3).toBe(Theme.Row)
			expect(tile.Position).toBe(first.Position)
			expect(tile.Size.Y).toBe(first.Size.Y)
			expect(UiHarness.find(tile, "DayLabel").Text).toBe(if day == cap then `Day {cap}` else tostring(day))
			expect(UiHarness.find(tile, "DayAmount").TextColor3).toBe(Theme.Gold)
		end
	end)
	it("shows the big amount, tomorrow's reward and sends Daily from Claim", function()
		local popup, sent = build()
		popup.update(today(1))
		expect(UiHarness.find(popup.frame, "Amount").Text).toBe(`+${Config.DAILY_BASE}`)
		expect(UiHarness.find(popup.frame, "Streak").Text).toBe("Day 1 of your streak")
		local chip = UiHarness.find(popup.frame, "Tomorrow")
		expect(chip.Visible).toBe(true)
		expect(string.find(chip.Text, "Come back tomorrow for", 1, true) ~= nil).toBe(true)
		UiHarness.fire(UiHarness.find(popup.frame, "Claim"), "Activated")
		expect(#sent).toBe(1)
		expect(sent[1][1]).toBe("Daily")
	end)
	it("fits the strip, amount and Claim in the card body at every gate viewport", function()
		local rows = UiHarness.ui("Panels/DailyPopup").ROWS
		for _, vp in LayoutAssert.GATE_VIEWPORTS do
			local s = Layout.screen(vp.w, vp.h)
			local body = Layout.panelBody(Layout.rect(0, 0, s.daily.w, s.daily.h))
			local needed = rows.amount.y + rows.amount.h + Layout.BUTTON
			expect(`{vp.name}: {body.h >= needed}`).toBe(`{vp.name}: true`)
		end
	end)
end)
