--!strict
-- v18: nav badges (SlimeDex "NN%", "!", "$") sit fully inside their button at
-- all five gate sizes (B5: on the top-right corner of their rounded tile, not on the label).
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Layout.navBadge", function()
	it("is inset from the button's top-right corner", function()
		local b = Layout.rect(10, 20, 56, 56)
		local r = Layout.navBadge(b, "100%")
		expect(r.x + r.w).toBe(b.x + b.w - Layout.NAV_BADGE.inset)
		expect(r.y).toBe(b.y + Layout.NAV_BADGE.inset)
	end)
end)

describe("nav badges stay inside their buttons", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		for _, entry in LayoutAssert.screens({ vp }) do
			it(entry.label, function()
				local check = LayoutAssert.new(entry.label, entry.screen)
				LayoutAssert.navBadges(check)
				expect(check.report()).toBe("")
			end)
		end
	end
end)

describe("the SlimeDex % badge stays on its tile (B5)", function()
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		it(entry.label, function()
			local s = entry.screen
			for i in require("../../src/ui/Nav").ENTRIES do
				local b = s.navButtons[i]
				local tile = Layout.navTile(s.compact, b)
				local badge = Layout.navBadge(b, "100%")
				expect(Layout.overlaps(badge, tile)).toBe(true) -- sits on the tile's corner ...
				expect(badge.y + badge.h <= tile.y + tile.h).toBe(true) -- ... above the label row
				expect(badge.x >= b.x and badge.x + badge.w <= b.x + b.w).toBe(true) -- ... inside its button
			end
		end)
	end
end)
