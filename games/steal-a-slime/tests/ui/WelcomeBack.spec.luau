--!strict
-- v20 welcome-back card: contents, content-sized panel and queue ordering with Daily / tutorial.
local Config = require("../../src/shared/Config")
local Layout = require("../../src/ui/Layout")
local PopupQueue = require("../../src/ui/PopupQueue")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local WelcomeBack = require("../../src/ui/WelcomeBack")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function state(extra: { [string]: any }?): any
	local s: any = {
		tutorialStepId = nil,
		welcomeBack = { away = 19800, cash = 12400, grown = 3 },
		daily = { available = false, streak = 4, amount = 100, day = 4 },
		goals = {
			{ id = "a", title = "Catch 10 slimes", progress = 10, target = 10, done = true },
			{ id = "b", title = "Merge 5 times", progress = 2, target = 5, done = false },
		},
	}
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

describe("WelcomeBack.view", function()
	it("is nil without a report", function()
		expect(WelcomeBack.view(state({ welcomeBack = false }))).toBeNil()
		expect(WelcomeBack.view(nil)).toBeNil()
	end)
	it("summarises away time, offline cash, growth, streak and the next goal", function()
		local view = WelcomeBack.view(state())
		assert(view, "view")
		expect(view.away).toBe("You were away 5h 30m")
		expect(#view.rows).toBe(4)
		expect(view.rows[1].name).toBe("Cash")
		expect(string.find(view.rows[1].text, "earned while away", 1, true) ~= nil).toBe(true)
		expect(view.rows[2].text).toBe("3 slimes grew on your pads")
		expect(view.rows[3].text).toBe("Daily streak: 4 days")
		expect(view.rows[4].text).toBe("Merge 5 times (2/5)")
	end)
	it("shows a ready daily reward, singular growth and skips missing rows", function()
		local s = state({ daily = { available = true, streak = 1, amount = 250, day = 2 }, goals = {} })
		s.welcomeBack = { away = 90000, cash = 0, grown = 1 }
		local view = WelcomeBack.view(s)
		assert(view, "view")
		expect(view.away).toBe("You were away 1d 1h")
		expect(view.rows[2].text).toBe("1 slime grew on your pads")
		expect(string.find(view.rows[3].text, "Daily reward ready", 1, true) ~= nil).toBe(true)
		expect(#view.rows).toBe(3)
	end)
	it("every row names an item icon", function()
		for _, row in (WelcomeBack.view(state()) :: any).rows do
			expect(#row.icon > 0).toBe(true)
		end
	end)
end)

describe("Welcome panel", function()
	local function build(): any
		local ctx: any = { Config = Config, togglePanel = function() end }
		return UiHarness.ui("Panels/Welcome").new(UiHarness.root(), ctx)
	end
	it("starts hidden and fills its rows from State", function()
		local panel = build()
		expect(panel.frame.Visible).toBe(false)
		panel.update(state())
		expect(UiHarness.find(panel.frame, "Row4").Visible).toBe(true)
		panel.update(state({ goals = {} }))
		expect(UiHarness.find(panel.frame, "Row4").Visible).toBe(false)
	end)
	it("sizes its card to its rows plus Collect", function()
		local Widgets = UiHarness.ui("Widgets")
		local panel = build()
		panel.update(state())
		local full = Widgets.contentHeight(UiHarness.find(panel.frame, "Body"))
		panel.update(state({ goals = {} }))
		local fewer = Widgets.contentHeight(UiHarness.find(panel.frame, "Body"))
		expect(fewer < full).toBe(true)
		expect(Layout.cardHeight(full) <= Layout.menuHeight("Welcome") + 120).toBe(true)
	end)
end)

describe("PopupQueue with the welcome-back card", function()
	it("opens Welcome once, then Daily after it closes (no overlap)", function()
		local q = PopupQueue.new()
		local s = state({ daily = { available = true, streak = 1, amount = 100 } })
		expect(q.update(s)).toBe("Welcome")
		expect(q.update(s, true)).toBeNil() -- Welcome on screen: Daily waits
		expect(q.has("Daily")).toBe(true)
		expect(q.update(s, false)).toBe("Daily")
		expect(q.update(s)).toBeNil() -- welcome is shown once per join
	end)
	it("is held back by the tutorial like the Daily popup", function()
		local q = PopupQueue.new()
		expect(q.update(state({ tutorialStepId = "Grab" }))).toBeNil()
		expect(q.queued()[1]).toBe("Welcome")
		expect(q.update(state({ tutorialStepId = "Lock" }))).toBeNil()
		expect(q.update(state())).toBe("Welcome")
	end)
	it("does nothing without a report", function()
		local q = PopupQueue.new()
		expect(q.update(state({ welcomeBack = false }))).toBeNil()
	end)
	it("orders Welcome before Daily", function()
		expect(PopupQueue.ORDER[1]).toBe("Welcome")
		expect(PopupQueue.ORDER[2]).toBe("Daily")
	end)
end)

describe("Welcome panel look", function()
	local function build(): any
		local ctx: any = { Config = Config, togglePanel = function() end }
		return UiHarness.ui("Panels/Welcome").new(UiHarness.root(), ctx)
	end
	it("puts the earnings in a big gold headline under the away line", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		panel.update(state())
		expect(UiHarness.find(panel.frame, "Away").Text).toBe("You were away for 5h 30m and earned")
		local earned = UiHarness.find(panel.frame, "Earned")
		expect(earned.Visible).toBe(true)
		expect(earned.Text).toBe("+$12.4K")
		expect(earned.TextColor3).toBe(Theme.Gold)
		local s = state()
		s.welcomeBack = { away = 19800, cash = 0, grown = 0 }
		panel.update(s)
		expect(UiHarness.find(panel.frame, "Away").Text).toBe("You were away for 5h 30m")
		expect(UiHarness.find(panel.frame, "Earned").Visible).toBe(false)
	end)
	it("shows the ready daily amount on the right and the goal as a bar with its count", function()
		local panel = build()
		panel.update(state({ daily = { available = true, streak = 1, amount = 500 } }))
		local daily = UiHarness.find(panel.frame, "Row3")
		expect(UiHarness.find(daily, "Name").Text).toBe("Daily reward ready")
		expect(UiHarness.find(daily, "Amount").Visible).toBe(true)
		expect(UiHarness.find(daily, "Amount").Text).toBe("$500")
		local goal = UiHarness.find(panel.frame, "Row4")
		expect(UiHarness.find(goal, "Name").Text).toBe("Merge 5 times")
		expect(UiHarness.find(goal, "Count").Text).toBe("2/5")
		expect(UiHarness.find(goal, "Bar").Visible).toBe(true)
		expect(UiHarness.find(goal, "Amount").Visible).toBe(false)
	end)
end)
