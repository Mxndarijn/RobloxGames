--!strict
-- The Goo kit's shared parts (Widgets): menus share one goo edge per ScreenGui, the drips stay in the gap
-- above a panel's body, and helpers that take a font pick the right label property.
local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function edges(root: any): { any }
	local out = {}
	for _, d in UiHarness.descendants(root) do
		if d.Name == "GooEdge" then
			table.insert(out, d)
		end
	end
	return out
end

describe("Goo kit", function()
	it("every drip and the lip hang inside the gap between the band and the body", function()
		local g, gap = Layout.GOO_EDGE, Layout.PANEL_CHROME.bodyGap
		expect(g.lip < gap).toBe(true)
		for i, d in g.drips do
			local w, len = d[2], d[3]
			local lowest = len - math.round(w * g.dropRise) + w
			expect(`drip {i}: {lowest < gap}`).toBe(`drip {i}: true`)
			expect(`drip {i} clear of the icon tile: {d[1] >= 0.14}`).toBe(`drip {i} clear of the icon tile: true`)
		end
	end)

	it("menus on one ScreenGui share a single goo edge", function()
		local Widgets = UiHarness.ui("Widgets")
		local root = UiHarness.root()
		Widgets.panel(root, "APanel", "A", "A")
		Widgets.panel(root, "BPanel", "B", "B")
		Widgets.panel(root, "CPanel", "C", "C")
		expect(#edges(root)).toBe(1)
	end)

	it("a destroyed panel's edge is rebuilt for the next panel", function()
		local Widgets = UiHarness.ui("Widgets")
		local root = UiHarness.root()
		local first = Widgets.panel(root, "APanel", "A", "A")
		first.frame:Destroy()
		expect(#edges(root)).toBe(0)
		Widgets.panel(root, "BPanel", "B", "B")
		expect(#edges(root)).toBe(1)
	end)

	it("fontKey sends Fredoka One to Font and Nunito to FontFace", function()
		local Widgets = UiHarness.ui("Widgets")
		expect(Widgets.fontKey(Widgets.Theme.Font)).toBe("Font")
		expect(Widgets.fontKey(Widgets.Theme.FontBody)).toBe("FontFace")
		local label = Widgets.label({ Name = "Body" })
		expect(label.FontFace.Family).toBe(Widgets.Theme.FontBody.Family)
	end)
end)
