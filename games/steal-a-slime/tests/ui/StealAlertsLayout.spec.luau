--!strict
-- FEATURES.StealAlerts layout at the five gate viewports: the thief arrow and the edge flash never cover the
-- HUD, the banner stack or the nav (Layout.screen rects; the Hud / StealAlertFx build Instances only in .new).
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local StealAlert = require("../../src/shared/StealAlert")
local StealAlertLayout = require("../../src/ui/StealAlertLayout")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("StealAlerts arrow and flash vs the banners and nav", function()
	local ANGLES = {}
	for i = 0, 23 do
		table.insert(ANGLES, (i / 24) * 2 * math.pi - math.pi)
	end
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		local s = entry.screen
		it(`{entry.label}: the arrow + distance label stay clear of the banner stack and nav (all angles)`, function()
			local check = LayoutAssert.new(entry.label, s)
			for _, bannerH in { 0, 34, 150, 260 } do
				local stack = Layout.rect(s.banners.x, s.banners.y, s.banners.w, math.max(bannerH, 1))
				for _, angle in ANGLES do
					local box = StealAlertLayout.arrowBox(s, bannerH, StealAlert.edgePoint, angle)
					local name = string.format("Arrow(banners %d, angle %.2f)", bannerH, angle)
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
	it("StealAlertFx lays out through StealAlertLayout", function()
		local fx = fs.readFile("src/ui/StealAlertFx.luau")
		expect(string.find(fx, "StealAlertLayout.arrowBox(", 1, true) ~= nil).toBe(true)
		expect(string.find(fx, "StealAlertLayout.flashThickness(", 1, true) ~= nil).toBe(true)
	end)
	it("the StealAlerts flag stays default off", function()
		expect(Config.FEATURES.StealAlerts).toBe(false)
	end)
end)
