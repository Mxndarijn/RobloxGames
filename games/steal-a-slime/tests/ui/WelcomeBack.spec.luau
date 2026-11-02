--!strict
-- The welcome back / daily reward card: what it shows per mode, its buttons, and its size on clamped screens.
local Config = require("../../src/shared/Config")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local WelcomeBack = require("../../src/ui/WelcomeBack")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function state(extra: { [string]: any }?): any
	local s: any = {
		tutorialStepId = nil,
		rebirthMultiplier = 1,
		welcomeBack = { away = 19800, cash = 12400, grown = 3, onPads = true },
		daily = { available = true, streak = 2, amount = 300, day = 3 },
	}
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

-- A State that offers both Robux buttons: an unused offline payout to double and a broken streak to keep.
local function withOffers(s: any): any
	s.exclusiveShop = { offlineDouble = { available = true, cash = 12400, used = false }, streakKeepable = true }
	return s
end

describe("WelcomeBack.view", function()
	it("join mode: cash on the pads, the daily row with seven tiles, growth, and Claim", function()
		local view = WelcomeBack.view(state(), "join", Config)
		assert(view, "view")
		expect(view.title).toBe("Welcome back")
		expect((view.cash :: any).name).toBe("+$12.4K")
		expect((view.cash :: any).desc).toBe("Earned in 5h 30m, waiting on your cash pads")
		local daily = view.daily :: any
		expect(daily.name).toBe("Daily reward")
		expect(daily.amount).toBe("$300")
		expect(daily.status).toBe("Day 3 of your streak")
		expect(#daily.tiles).toBe(Config.DAILY_STREAK_CAP)
		expect(daily.tiles[2].state).toBe("claimed")
		expect(daily.tiles[3].state).toBe("today")
		expect(daily.tiles[3].label).toBe("Day 3")
		expect(daily.tiles[4].amount).toBe(`${Config.DAILY_BASE * 4}`)
		expect((view.growth :: any).name).toBe("3 slimes grew")
		expect(view.action.kind).toBe("claim")
		expect(view.action.text).toBe("Claim $300")
	end)
	it("cash pads off: the cash was already added; no cash earned says so", function()
		local s = state()
		s.welcomeBack = { away = 19800, cash = 12400, grown = 0 }
		local view = WelcomeBack.view(s, "join", Config) :: any
		expect(view.cash.desc).toBe("Earned in 5h 30m, added to your cash")
		s.welcomeBack = { away = 90000, cash = 0, grown = 0 }
		view = WelcomeBack.view(s, "join", Config) :: any
		expect(view.cash.name).toBe("Away 1d 1h")
	end)
	it("no growth row when no slime grew (or slimes don't grow)", function()
		local s = state()
		s.welcomeBack.grown = 0
		expect((WelcomeBack.view(s, "join", Config) :: any).growth).toBeNil()
	end)
	it("daily already claimed: tomorrow's amount and Got it", function()
		local view = WelcomeBack.view(
			state({ daily = { available = false, streak = 3, amount = 300, day = 3 } }),
			"join",
			Config
		) :: any
		expect(view.daily.name).toBe("Daily reward claimed")
		expect(view.daily.status).toBe(`${Config.DAILY_BASE * 4} tomorrow`)
		expect(view.daily.amount).toBeNil()
		expect(view.daily.tiles[3].state).toBe("claimed")
		expect(view.action.kind).toBe("close")
		expect(view.action.text).toBe("Got it")
	end)
	it("a broken streak says so", function()
		local s = withOffers(state({ daily = { available = true, streak = 3, amount = 100, day = 1 } }))
		expect((WelcomeBack.view(s, "join", Config) :: any).daily.status).toBe("Your 3-day streak broke")
	end)
	it("daily mode (and join without a report): only the daily row, titled Daily reward", function()
		for _, v in
			{
				WelcomeBack.view(state(), "daily", Config),
				WelcomeBack.view(state({ welcomeBack = false }), "join", Config),
			}
		do
			local view = v :: any
			expect(view.mode).toBe("daily")
			expect(view.title).toBe("Daily reward")
			expect(view.cash).toBeNil()
			expect(view.growth).toBeNil()
			expect(view.daily ~= nil).toBe(true)
		end
	end)
	it("daily mode leads with the streak and tomorrow's amount; the title and Claim say the rest", function()
		local view = WelcomeBack.view(state(), "daily", Config) :: any
		expect(view.daily.name).toBe("Day 3 of your streak")
		expect(view.daily.status).toBe(`${Config.DAILY_BASE * 4} tomorrow`)
		expect(view.daily.amountShown).toBe(false)
		expect(view.action.text).toBe("Claim $300")
		local s = state({ daily = { available = false, streak = 3, amount = 300, day = 3 } })
		expect((WelcomeBack.view(s, "daily", Config) :: any).daily.name).toBe("Claimed today")
		expect((WelcomeBack.view(state(), "join", Config) :: any).daily.amountShown).toBe(true)
	end)
	it("is nil with nothing to show", function()
		expect(WelcomeBack.view(nil, "join", Config)).toBeNil()
		expect(WelcomeBack.view({ welcomeBack = false }, "daily", Config)).toBeNil()
	end)
	it("formats the away time", function()
		expect(WelcomeBack.awayText(19200)).toBe("5h 20m")
		expect(WelcomeBack.awayText(90000)).toBe("1d 1h")
		expect(WelcomeBack.awayText(720)).toBe("12m")
	end)
end)

describe("Welcome panel", function()
	local function build(): (any, { any }, { string })
		local sent, toggled = {}, {}
		local ctx: any = {
			Config = Config,
			send = function(...)
				table.insert(sent, { ... })
			end,
			togglePanel = function(key: string)
				table.insert(toggled, key)
			end,
		}
		return UiHarness.ui("Panels/Welcome").new(UiHarness.root(), ctx), sent, toggled
	end

	it("starts hidden; join mode fills the cash, daily and growth rows", function()
		local panel = build()
		expect(panel.frame.Visible).toBe(false)
		panel.setMode("join")
		panel.update(state())
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Welcome back")
		expect(UiHarness.find(panel.frame, "CashRow").Visible).toBe(true)
		expect(UiHarness.find(UiHarness.find(panel.frame, "CashRow"), "Name").Text).toBe("+$12.4K")
		expect(UiHarness.find(panel.frame, "DailyRow").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "GrowthRow").Visible).toBe(true)
	end)
	it("daily mode shows the daily row alone", function()
		local panel = build()
		panel.setMode("daily")
		panel.update(state())
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Daily reward")
		expect(UiHarness.find(panel.frame, "CashRow").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "GrowthRow").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "DailyRow").Visible).toBe(true)
	end)
	it("today's tile is gold, claimed tiles show the check", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		panel.update(state())
		expect(UiHarness.find(panel.frame, "Day3").BackgroundColor3).toBe(Theme.Gold)
		expect(UiHarness.find(panel.frame, "Day4").BackgroundColor3).toBe(Theme.Row)
		expect(UiHarness.find(UiHarness.find(panel.frame, "Day1"), "Claimed").Visible).toBe(true)
	end)
	it("Claim sends Daily; with nothing to claim the button reads Got it and closes the card", function()
		local panel, sent, toggled = build()
		panel.setMode("join")
		panel.update(state())
		local action = UiHarness.find(panel.frame, "Action")
		expect(action.Text).toBe("Claim $300")
		UiHarness.fire(action, "Activated")
		expect(#sent).toBe(1)
		expect(sent[1][1]).toBe("Daily")
		expect(#toggled).toBe(0)
		panel.update(state({ daily = { available = false, streak = 3, amount = 300, day = 3 } }))
		expect(action.Text).toBe("Got it")
		UiHarness.fire(action, "Activated")
		expect(toggled[1]).toBe("Welcome")
	end)
	it("a claim while the card is open shows a Claimed well", function()
		local panel = build()
		panel.frame.Visible = true
		panel.update(state())
		panel.update(state({ daily = { available = false, streak = 3, amount = 300, day = 3 } }))
		expect(UiHarness.find(panel.frame, "Action").Text).toBe("Claimed")
	end)
	it("shows both Robux offers side by side under the rows, none without the shop", function()
		local panel = build()
		panel.setMode("join")
		panel.update(withOffers(state({ daily = { available = true, streak = 3, amount = 100, day = 1 } })))
		local double = UiHarness.find(panel.frame, "DoubleIt")
		local keep = UiHarness.find(panel.frame, "KeepStreak")
		expect(double.Visible).toBe(true)
		expect(keep.Visible).toBe(true)
		expect(double.Parent.Name).toBe("Offers")
		expect(keep.Position.X.Scale).toBe(0.5)
		panel.update(state())
		expect(double.Visible).toBe(false)
		expect(keep.Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Offers").Visible).toBe(false)
	end)
	it("sizes its card to its rows: daily mode is shorter than join mode", function()
		local Widgets = UiHarness.ui("Widgets")
		local panel = build()
		panel.setMode("join")
		panel.update(state())
		local join = Widgets.contentHeight(UiHarness.find(panel.frame, "Body"))
		panel.setMode("daily")
		panel.update(state())
		local daily = Widgets.contentHeight(UiHarness.find(panel.frame, "Body"))
		expect(daily < join).toBe(true)
	end)
end)

describe("Welcome card on real screens", function()
	local Widgets = UiHarness.ui("Widgets")

	-- The card init.client places on `screen` for the worst case (join, both offers), its body box and content.
	local function place(screen: any): (any, any, any, any)
		local ctx: any = { Config = Config, togglePanel = function() end, send = function() end }
		local panel = UiHarness.ui("Panels/Welcome").new(UiHarness.root(), ctx)
		panel.setMode("join")
		panel.update(withOffers(state({ daily = { available = true, streak = 3, amount = 100, day = 1 } })))
		local card = Layout.panelFor(screen, "Welcome", Widgets.contentHeight(UiHarness.find(panel.frame, "Body")))
		panel.layout(card, screen)
		local content = Widgets.contentHeight(UiHarness.find(panel.frame, "Body"))
		card = Layout.panelFor(screen, "Welcome", content)
		return panel, card, Layout.panelBody(card), content
	end

	local function topIn(h: number, inst: any): number
		return inst.Position.Y.Scale * h + inst.Position.Y.Offset
	end

	for _, vp in { { name = "800x334", w = 800, h = 334 }, { name = "844x332", w = 844, h = 332 } } do
		it(
			`{vp.name} landscape phone: offers sit in their rows, growth joins the cash row, the button stays in the card`,
			function()
				local screen = Layout.screen(vp.w, vp.h, { touch = true })
				expect(screen.short).toBe(true)
				local panel, card, b, content = place(screen)
				expect(UiHarness.find(panel.frame, "DoubleIt").Parent.Name).toBe("CashRow")
				expect(UiHarness.find(panel.frame, "KeepStreak").Parent.Name).toBe("DailyRow")
				expect(UiHarness.find(panel.frame, "GrowthRow").Visible).toBe(false)
				local desc = UiHarness.find(UiHarness.find(panel.frame, "CashRow"), "Desc").Text
				expect(string.find(desc, "3 slimes grew", 1, true) ~= nil).toBe(true)
				expect(card.h).toBe(Layout.cardHeight(content)) -- fits without scrolling
				local action = UiHarness.find(panel.frame, "Action")
				local top = topIn(b.h, action)
				local check = LayoutAssert.new(vp.name, screen)
				check.inside("Action", Layout.rect(b.x, b.y + top, b.w, action.Size.Y.Offset), "card", card)
				expect(#check.problems).toBe(0)
			end
		)
	end

	it("1920x1080: the card fits its content and the button sits under the last row", function()
		local panel, card, b, content = place(Layout.screen(1920, 1080))
		expect(card.h).toBe(Layout.cardHeight(content))
		local offers = UiHarness.find(panel.frame, "Offers")
		local action = UiHarness.find(panel.frame, "Action")
		local offersEnd = offers.Position.Y.Offset + offers.Size.Y.Offset
		local Welcome = UiHarness.ui("Panels/Welcome")
		expect(math.abs(topIn(b.h, action) - (offersEnd + Welcome.ACTION_GAP)) < 0.5).toBe(true)
	end)
end)
