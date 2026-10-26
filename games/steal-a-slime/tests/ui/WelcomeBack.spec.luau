--!strict
-- v20 welcome-back card: contents, content-sized panel and queue ordering with Daily / tutorial.
local Config = require("../../src/shared/Config")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
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

describe("Welcome card on a clamped screen", function()
	local Widgets = UiHarness.ui("Widgets")

	-- The card init.client places on `screen` for the full four-row report, its body box, and the body's parts.
	local function place(screen: any): (any, any, any, any)
		local ctx: any = { Config = Config, togglePanel = function() end }
		local panel = UiHarness.ui("Panels/Welcome").new(UiHarness.root(), ctx)
		panel.update(state({ daily = { available = true, streak = 2, amount = 250 } }))
		local body = UiHarness.find(panel.frame, "Body")
		local content = Widgets.contentHeight(body)
		local card = Layout.panelFor(screen, "Welcome", content)
		return panel, card, Layout.panelBody(card), content
	end

	-- Top of a body child in body px, for a body `h` tall.
	local function topIn(h: number, inst: any): number
		return inst.Position.Y.Scale * h + inst.Position.Y.Offset
	end

	-- Landscape phone ScreenGuis short enough to clamp the four-row card.
	local phones = { { name = "800x334", w = 800, h = 334 }, { name = "844x332", w = 844, h = 332 } }
	for _, vp in phones do
		it(`{vp.name} touch: Collect sits inside the clamped card and the rows scroll above it`, function()
			local screen = Layout.screen(vp.w, vp.h, { touch = true })
			local panel, card, b, content = place(screen)
			expect(UiHarness.find(panel.frame, "Row4").Visible).toBe(true)
			expect(Layout.cardHeight(content) > card.h).toBe(true) -- the screen clamps this card
			local collect = UiHarness.find(panel.frame, "Collect")
			local top = topIn(b.h, collect)
			expect(top >= 0).toBe(true)
			expect(top + collect.Size.Y.Offset <= b.h + 0.5).toBe(true)
			local check = LayoutAssert.new(vp.name, screen)
			check.inside("Collect", Layout.rect(b.x, b.y + top, b.w, collect.Size.Y.Offset), "card", card)
			expect(#check.problems).toBe(0)
			local scroll = UiHarness.find(panel.frame, "Content")
			local view = b.h - Layout.BUTTON
			expect(topIn(b.h, scroll) + view <= top + 0.5).toBe(true) -- the rows end where Collect starts
			local row4 = UiHarness.find(panel.frame, "Row4")
			expect(scroll.CanvasSize.Y.Offset > view).toBe(true)
			expect(scroll.CanvasSize.Y.Offset >= row4.Position.Y.Offset + row4.Size.Y.Offset).toBe(true)
		end)
	end

	it("1920x1080: the card fits its content and Collect sits the collect gap under the last row", function()
		local panel, card, b, content = place(Layout.screen(1920, 1080))
		expect(card.h).toBe(Layout.cardHeight(content))
		local row4 = UiHarness.find(panel.frame, "Row4")
		local collect = UiHarness.find(panel.frame, "Collect")
		local rowsEnd = row4.Position.Y.Offset + row4.Size.Y.Offset
		expect(math.abs(topIn(b.h, collect) - (rowsEnd + UiHarness.ui("Panels/Welcome").ROWS.collectGap)) < 0.5).toBe(
			true
		)
	end)
end)
