--!strict
-- Overlay layers, scroll list rules and the phone UIScale (src/ui/Layout.luau).
local InventoryLayout = require("../../src/ui/InventoryLayout")
local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Layout.SCROLL_LIST", function()
	it("stacks rows from the top with edge padding (v15: Center clipped rows)", function()
		expect(Layout.SCROLL_LIST.paddingTop > 0).toBe(true)
		expect(Layout.SCROLL_LIST.paddingBottom > 0).toBe(true)
		local ys = Layout.stackRows({ 20, 20 }, 6)
		expect(ys[1]).toBe(Layout.SCROLL_LIST.paddingTop)
	end)
end)

describe("Layout.ZINDEX", function()
	it("puts the banner stack (steal and tutorial cards) under the daily popup and the carry panel over all", function()
		local z = Layout.ZINDEX
		expect(z.Base < z.Banners).toBe(true)
		expect(z.Banners < z.Daily).toBe(true)
		expect(z.Daily < z.Carry).toBe(true)
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
	end)
end)

describe("Layout rect helpers", function()
	it("overlaps / fitsInViewport / drawsAbove", function()
		local a = Layout.rect(0, 0, 10, 10)
		expect(Layout.overlaps(a, Layout.rect(9, 9, 5, 5))).toBe(true)
		expect(Layout.overlaps(a, Layout.rect(10, 0, 5, 5))).toBe(false) -- touching edges
		expect(Layout.fitsInViewport(Layout.rect(12, 12, 10, 10), 100, 100, 12)).toBe(true)
		expect(Layout.fitsInViewport(Layout.rect(95, 12, 10, 10), 100, 100)).toBe(false)
		expect(Layout.drawsAbove("Carry", "Daily")).toBe(true)
		expect(Layout.drawsAbove("Banners", "Daily")).toBe(false)
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

describe("Layout.screen nav and bottom row", function()
	it("the nav ends above the carry card and the hotbar", function()
		for _, v in { { 390, 844 }, { 1920, 1080 }, { 1366, 768 }, { 1024, 768 } } do
			local s = Layout.screen(v[1], v[2])
			expect(s.nav.y + s.nav.h + Layout.GAP <= s.carry.y + 0.001).toBe(true)
			expect(s.nav.y + s.nav.h + Layout.GAP <= s.hotbar.y + 0.001).toBe(true)
		end
	end)
	it("portrait phone and desktop keep the carry card above the bottom inset", function()
		for _, v in { { 390, 844 }, { 1920, 1080 } } do
			local s = Layout.screen(v[1], v[2])
			expect(s.short).toBe(false)
			-- Portrait phones (H1 HUD): the carry card sits above the two bottom clusters, which sit above the
			-- touch-controls rise; desktop keeps it on the inset line.
			local barH = InventoryLayout.height(s.compact, Layout.MIN_TOUCH_DESIGN, s.tight)
			local lift = if s.width
					< Layout.CARRY.w + s.money.rect.w + s.status.rect.w + 2 * (Layout.MARGIN + Layout.GAP)
				then math.ceil(Layout.TOUCH_RISE / s.scale) + math.max(s.money.rect.h, s.status.rect.h, barH) + Layout.GAP
				else 0
			if s.phone then
				expect(s.hotbar.y + s.hotbar.h).toBe(s.height - s.bottomInset - Layout.TOUCH_RISE / s.scale)
			else
				expect(s.hotbar.y + s.hotbar.h).toBe(s.height - s.bottomInset - lift)
			end
			expect(s.carry.y + s.carry.h).toBe(s.height - s.bottomInset - lift)
		end
	end)
	it("844x390: the carry card hugs the bottom edge", function()
		local s = Layout.screen(844, 390)
		expect(s.phone).toBe(true)
		expect((s.carry.y + s.carry.h) * s.scale >= 390 - 12).toBe(true)
		expect(Layout.fitsInViewport(s.carry, s.width, s.height)).toBe(true)
	end)
end)

describe("Layout.screen landscape phone under the top bar", function()
	-- 800x334 / 740x320: a landscape phone's ScreenGui below Roblox's top bar, narrower than 844x390.
	for _, v in { { 800, 334 }, { 740, 320 } } do
		local s = Layout.screen(v[1], v[2], { touch = true })
		it(`{v[1]}x{v[2]}: the carry / move card hugs the bottom edge in the hotbar's place, not mid-screen`, function()
			expect((s.carry.y + s.carry.h) * s.scale >= v[2] - 16).toBe(true)
			expect(Layout.overlaps(s.carry, s.money.rect)).toBe(false)
			expect(Layout.overlaps(s.carry, s.status.rect)).toBe(false)
			expect(Layout.fitsInViewport(s.carry, s.width, s.height)).toBe(true)
		end)
	end
end)
