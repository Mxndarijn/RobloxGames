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
	it("every drip hangs inside the gap between the band and the body", function()
		local g, gap = Layout.GOO_EDGE, Layout.PANEL_CHROME.bodyGap
		for i, d in g.drips do
			local lowest = d[3]
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

describe("emoji icons sit in the middle of their spot", function()
	local Widgets = UiHarness.ui("Widgets")

	it("only emoji rise; text glyphs like the star, $ and digits stay centred", function()
		local body = Widgets.Theme.FontBody
		expect(Widgets.emojiRise(body, "♻️")).toBe(Widgets.EMOJI_RISE.Nunito)
		expect(Widgets.emojiRise(body, "🎁")).toBe(Widgets.EMOJI_RISE.Nunito)
		expect(Widgets.emojiRise(Widgets.Theme.Font, "⚡")).toBe(Widgets.EMOJI_RISE.FredokaOne)
		for _, text in { "★", "$", "25", "?", "" } do
			expect(`{text}: {Widgets.emojiRise(body, text)}`).toBe(`{text}: 0`)
		end
	end)

	it("a panel's header emoji is moved down by its rise; re-centring a new icon does not stack", function()
		local root = UiHarness.root()
		local panel = Widgets.panel(root, "RebirthPanel", "Rebirth", "♻️")
		local icon = panel.icon
		local drop = math.round(Widgets.EMOJI_RISE.Nunito * icon.TextSize)
		expect(drop > 0).toBe(true)
		expect(icon.Position.Y.Offset).toBe(drop)
		-- The harness fires no Text-changed signal, so run what the panel's hook runs.
		icon.Text = "A"
		Widgets.centreEmoji(icon)
		expect(icon.Position.Y.Offset).toBe(0)
		icon.Text = "🔊"
		Widgets.centreEmoji(icon)
		Widgets.centreEmoji(icon)
		expect(icon.Position.Y.Offset).toBe(drop)
	end)
end)
