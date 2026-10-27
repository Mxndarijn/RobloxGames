--!strict
-- FEATURES.StealAlerts layout at the five gate viewports: the thief arrow and the edge flash never cover the
-- HUD, the banner stack or the nav (Layout.screen rects; the Hud / StealAlertFx build Instances only in .new).
local EdgeArrow = require("../../src/shared/EdgeArrow")
local GooPalette = require("../../src/shared/GooPalette")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local StealAlertLayout = require("../../src/ui/StealAlertLayout")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("StealAlerts arrow and flash vs the banners and nav", function()
	local DIRECTIONS = {}
	for i = 0, 23 do
		local a = (i / 24) * 2 * math.pi
		table.insert(DIRECTIONS, { math.cos(a), math.sin(a) })
	end
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		local s = entry.screen
		it(`{entry.label}: the arrow + label stay clear of the banner stack and nav (all angles)`, function()
			local check = LayoutAssert.new(entry.label, s)
			for _, bannerH in { 0, 34, 150, 260 } do
				local stack = Layout.rect(s.banners.x, s.banners.y, s.banners.w, math.max(bannerH, 1))
				local rect = StealAlertLayout.arrowRect(s, bannerH)
				local origin = { x = s.width / 2, y = s.height / 2 }
				for _, d in DIRECTIONS do
					local arrow = EdgeArrow.place(origin, d[1], d[2], rect)
					local box = StealAlertLayout.box(arrow.x, arrow.y)
					local name = string.format("Arrow(banners %d, dir %.2f %.2f)", bannerH, d[1], d[2])
					check.onScreen(name, box, Layout.MARGIN - 0.001)
					check.noOverlap(name, box, "Nav", s.nav)
					if bannerH > 0 then
						check.noOverlap(name, box, "Banners", stack)
					end
				end
			end
			expect(check.report()).toBe("")
		end)
	end
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		it(
			`{vp.name}: the flash border stays in the viewport margin on phones, the stock thickness elsewhere`,
			function()
				local t = StealAlertLayout.flashThickness(s)
				if s.compact then
					expect(t > 0).toBe(true)
					expect(s.nav.x >= t).toBe(true)
					expect(s.nav.y >= t).toBe(true)
				else
					expect(t).toBe(StealAlertLayout.FLASH)
				end
			end
		)
	end
end)

describe("the thief ping", function()
	local thief = { Name = "Thief" }
	it("marks the thief for the whole theft, wherever they are and whether or not the arrow shows", function()
		expect(StealAlertLayout.pingTarget(true, false, thief)).toBe(thief)
	end)
	it("is gone once the theft ends, before the thief's character loads and in the Studio fake", function()
		expect(StealAlertLayout.pingTarget(false, false, thief)).toBe(nil)
		expect(StealAlertLayout.pingTarget(true, false, nil)).toBe(nil)
		expect(StealAlertLayout.pingTarget(true, true, thief)).toBe(nil)
	end)
	it("is red", function()
		local c = GooPalette.Thief
		expect(c[1] >= 200 and c[2] <= 80 and c[3] <= 80).toBe(true)
	end)
end)
