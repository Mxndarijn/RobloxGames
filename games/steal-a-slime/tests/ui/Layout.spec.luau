--!strict
-- Overlay layers, scroll list rules and the phone UIScale (src/ui/Layout.luau).
local fs = require("@lune/fs")

local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function read(path: string): string
	return fs.readFile(path)
end

describe("Layout.SCROLL_LIST", function()
	it("stacks rows from the top with edge padding (v15: Center clipped rows)", function()
		expect(Layout.SCROLL_LIST.paddingTop > 0).toBe(true)
		expect(Layout.SCROLL_LIST.paddingBottom > 0).toBe(true)
		local ys = Layout.stackRows({ 20, 20 }, 6)
		expect(ys[1]).toBe(Layout.SCROLL_LIST.paddingTop)
	end)
	it("is placed by Widgets.restack, not a UIListLayout (v26 stacked rows)", function()
		-- Instance-level checks: tests/ui/ScrollLists.spec.luau.
		local src = read("src/ui/Widgets.luau")
		local body = string.match(src, "function Widgets%.restack(.-)\nend") :: string
		expect(body ~= nil).toBe(true)
		expect(string.find(body, "Layout.stackRows", 1, true) ~= nil).toBe(true)
		local list = string.match(src, "function Widgets%.scrollList(.-)\nend") :: string
		expect(string.find(list, "UIListLayout", 1, true)).toBeNil()
		expect(string.find(list, "Widgets.restack", 1, true) ~= nil).toBe(true)
	end)
	it("is used by every panel list (no bare Widgets.scroll + Center list)", function()
		for _, name in { "Shop", "Goals", "Plot", "Merge", "Dex", "Leaderboard" } do
			local src = read(`src/ui/Panels/{name}.luau`)
			expect(string.find(src, "Widgets.scrollList(", 1, true) ~= nil).toBe(true)
			expect(string.find(src, "Widgets.scroll(", 1, true)).toBeNil()
		end
	end)
end)

describe("Layout.ZINDEX", function()
	it("puts the tutorial over the daily popup and the carry panel over both", function()
		local z = Layout.ZINDEX
		expect(z.Base < z.Daily).toBe(true)
		expect(z.Daily < z.Tutorial).toBe(true)
		expect(z.Tutorial < z.Carry).toBe(true)
	end)
	it("is what the overlays use", function()
		local uses = {
			Carry = "Layout.ZINDEX.Carry",
			TutorialOverlay = "Layout.ZINDEX.Tutorial",
			DailyPopup = "Layout.ZINDEX.Daily",
		}
		for name, needle in uses do
			local src = read(`src/ui/Panels/{name}.luau`)
			expect(string.find(src, needle, 1, true) ~= nil).toBe(true)
		end
	end)
end)

describe("Layout.uiScale", function()
	it("keeps desktop at 1", function()
		expect(Layout.uiScale(1920, 1080)).toBe(1)
		expect(Layout.uiScale(1280, 720)).toBe(1)
		expect(Layout.uiScale(2560, 1369)).toBe(1)
	end)
	it("shrinks on phones, never below MIN_SCALE", function()
		local phone = Layout.uiScale(844, 390) -- iPhone landscape
		expect(phone < 1).toBe(true)
		expect(phone >= Layout.MIN_SCALE).toBe(true)
		expect(math.abs(Layout.uiScale(1152, 720) - 0.9) < 1e-9).toBe(true)
		expect(Layout.uiScale(390, 844)).toBe(Layout.MIN_SCALE) -- portrait phone
		expect(Layout.uiScale(320, 200)).toBe(Layout.MIN_SCALE)
	end)
	it("ignores bad viewports", function()
		expect(Layout.uiScale(0, 0)).toBe(1)
		expect(Layout.uiScale(0 / 0, 720)).toBe(1)
	end)
end)

describe("Layout touch targets", function()
	it("keeps every MIN_TOUCH_DESIGN button >= MIN_TOUCH px at any reachable scale", function()
		expect(Layout.MIN_TOUCH).toBe(44)
		expect(Layout.MIN_TOUCH_DESIGN * Layout.MIN_SCALE >= Layout.MIN_TOUCH).toBe(true)
		expect(Layout.BUTTON >= Layout.MIN_TOUCH_DESIGN).toBe(true)
		expect(Layout.minTouchDesignSize(1)).toBe(44)
		expect(Layout.minTouchDesignSize(0.5)).toBe(88)
		expect(Layout.minTouchDesignSize(0)).toBe(44)
	end)
	it("calls phones and scaled-down windows compact, desktop not", function()
		expect(Layout.isCompact(390, 844)).toBe(true)
		expect(Layout.isCompact(1024, 768)).toBe(true)
		expect(Layout.isCompact(1920, 1080)).toBe(false)
		expect(Layout.isCompact(1280, 720)).toBe(false)
		expect(Layout.navDefaultCollapsed(390, 844)).toBe(true)
		expect(Layout.navDefaultCollapsed(1920, 1080)).toBe(false)
	end)
end)

describe("Layout rect helpers", function()
	it("overlaps / fitsInViewport / drawsAbove", function()
		local a = Layout.rect(0, 0, 10, 10)
		expect(Layout.overlaps(a, Layout.rect(9, 9, 5, 5))).toBe(true)
		expect(Layout.overlaps(a, Layout.rect(10, 0, 5, 5))).toBe(false) -- touching edges
		expect(Layout.fitsInViewport(Layout.rect(12, 12, 10, 10), 100, 100, 12)).toBe(true)
		expect(Layout.fitsInViewport(Layout.rect(95, 12, 10, 10), 100, 100)).toBe(false)
		expect(Layout.drawsAbove("Carry", "Tutorial")).toBe(true)
		expect(Layout.drawsAbove("Daily", "Tutorial")).toBe(false)
	end)
	it("estimates text: wider for longer / bold, taller when wrapped", function()
		expect(Layout.lineWidth("Rebirth", 18) < Layout.lineWidth("Rebirths", 18)).toBe(true)
		expect(Layout.lineWidth("Shop", 18) < Layout.lineWidth("Shop", 18, true)).toBe(true)
		local _, h = Layout.textSize("a\nb", 10)
		expect(h).toBeCloseTo(2 * 10 * Layout.LINE_HEIGHT)
		expect(Layout.wrappedHeight(string.rep("word ", 40), 14, 100) > Layout.wrappedHeight("word", 14, 100)).toBe(
			true
		)
	end)
end)

describe("text that must not be cut off (v15 playtest)", function()
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	it("HUD banners (boss countdown) wrap and grow", function()
		local src = read("src/ui/Hud.luau")
		local body = string.match(src, "local function banner(.-)\nend") :: string
		expect(has(body, "TextWrapped = true")).toBe(true)
		expect(has(body, "TextTruncate.None")).toBe(true)
		expect(has(body, "AutomaticSize = Enum.AutomaticSize.Y")).toBe(true)
	end)
	it("the rebirth disclaimer wraps onto a tall-enough line, list from the top", function()
		local src = read("src/ui/Panels/Rebirth.luau")
		expect(has(src, "warnLine.AutomaticSize = Enum.AutomaticSize.Y")).toBe(true)
		expect(has(src, "layout.VerticalAlignment = Enum.VerticalAlignment.Top")).toBe(true)
		expect(has(src, "and SlimeDex.")).toBe(true)
	end)
end)

describe("root UIScale", function()
	it("init.client scales the ScreenGui from its size and follows changes", function()
		local src = read("src/ui/init.client.luau")
		expect(string.find(src, 'create("UIScale"', 1, true) ~= nil).toBe(true)
		expect(string.find(src, "Layout.uiScale(", 1, true) ~= nil).toBe(true)
		expect(string.find(src, 'GetPropertyChangedSignal("AbsoluteSize")', 1, true) ~= nil).toBe(true)
	end)
end)
