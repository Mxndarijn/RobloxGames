--!strict
-- Small-screen sweep of the HUD overlay: the banner stack and the layout boxes around it at
-- the five gate viewports (390x844, 844x390, 1024x768, 1366x768, 1920x1080). Toasts are gone (B6).

local Config = require("../../src/shared/Config")
local Goals = require("../../src/shared/Goals")

local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local CHIP_H = 34 -- one banner at TextSize 15-16: Hud `banner` 34 px minimum

describe("HUD banners at the gate viewports", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		local label = vp.name

		it(`{label}: the banner column is inside the viewport and clear of the nav`, function()
			local check = LayoutAssert.new(label, s)
			local b = s.banners
			check.onScreen("Banners", Layout.rect(b.x, b.y, b.w, CHIP_H), 0)
			for count = 1, 3 do
				local bannerH = count * CHIP_H + (count - 1) * 6
				check.noOverlap(`Banners({count})`, Layout.rect(b.x, b.y, b.w, bannerH), "Nav", s.nav)
			end
			expect(check.report()).toBe("")
		end)
	end
end)

describe("Goals 'Next:' preview", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: every goal step's Next line fits one row line`, function()
			local s = Layout.screen(vp.w, vp.h)
			-- Row text width: the body (menu card minus its padding; rows use its full width), the row inset and the
			-- 40 px icon column.
			local textW = s.menuW - Layout.PANEL_CHROME.pad * 2 - (8 + 40 + 8) - 10
			local check = LayoutAssert.new(vp.name, s)
			for _, goal in Config.GOALS do
				for stage = 3, #goal.targets do
					check.text({
						name = `Next {goal.id}#{stage}`,
						text = `Next: {Goals.title(goal, goal.targets[stage])}`,
						size = 12,
						w = textW,
						h = 14,
					})
				end
			end
			expect(check.report()).toBe("")
		end)
	end
end)
