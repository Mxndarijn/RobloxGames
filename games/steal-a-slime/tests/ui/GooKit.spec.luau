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

describe("the game's check", function()
	local Widgets = UiHarness.ui("Widgets")

	it("is a mint disc with an Ink ring and a two-leg Ink tick that join at the corner", function()
		local check = Widgets.check(32, { Name = "Tick" })
		expect(check.Name).toBe("Tick")
		expect(check.Size.X.Offset).toBe(32)
		expect(check.Size.Y.Offset).toBe(32)
		expect(check:FindFirstChildOfClass("UIStroke").Color).toBe(Widgets.Theme.Ink)
		expect(check:FindFirstChildOfClass("UIStroke").Thickness >= 2).toBe(true)
		local short, long = check:FindFirstChild("Tick1"), check:FindFirstChild("Tick2")
		expect(short.BackgroundColor3).toBe(Widgets.Theme.Ink)
		expect(long.Size.X.Scale > short.Size.X.Scale).toBe(true)
		expect(short.Rotation > 0 and long.Rotation < 0).toBe(true)
		local p = Widgets.CHECK.points
		for _, pt in p do
			expect(pt[1] > 0.15 and pt[1] < 0.85 and pt[2] > 0.15 and pt[2] < 0.85).toBe(true)
		end
	end)

	it("sits left of a status well's text, the pair centred, and hides without leaving room", function()
		local well = Widgets.status({ Text = "Owned", TextSize = 15 })
		local w = well.Size.X.Offset
		Widgets.setStatusCheck(well, true)
		local check = well:FindFirstChild("Check")
		local room = Widgets.checkRoom(15)
		local textW = Layout.lineWidth("Owned", 15, true)
		expect(check.Visible).toBe(true)
		expect(well:FindFirstChild("CheckPad").PaddingLeft.Offset).toBe(room)
		-- centre of the pair = the well's centre, give or take the rounding of half the text
		local contentCentre = (w + room) / 2
		local left = contentCentre + check.Position.X.Offset
		local right = contentCentre + textW / 2
		expect(math.abs((left + right) / 2 - w / 2) <= 1).toBe(true)
		Widgets.setStatusCheck(well, true)
		expect(#well:GetChildren()).toBe(4) -- corner, stroke, check, padding: no second check
		Widgets.setStatusCheck(well, false)
		expect(check.Visible).toBe(false)
		expect(well:FindFirstChild("CheckPad").PaddingLeft.Offset).toBe(0)
	end)

	it("showCheck builds a check only once it shows, then reuses it", function()
		local row = Widgets.status({})
		expect(Widgets.showCheck(row, false, 20, { Name = "Tick" })).toBeNil()
		expect(row:FindFirstChild("Tick")).toBeNil()
		local shown = Widgets.showCheck(row, true, 20, { Name = "Tick" })
		expect(shown.Visible).toBe(true)
		expect(Widgets.showCheck(row, false, 20, { Name = "Tick" })).toBe(shown)
		expect(shown.Visible).toBe(false)
	end)

	it("a claimed Daily tile shows the check instead of its day label", function()
		local DailyPopup = UiHarness.ui("Panels/DailyPopup")
		expect(DailyPopup.dayLabel(3, "claimed", 7)).toBe("")
		expect(DailyPopup.dayLabel(3, "today", 7)).toBe("Day 3")
	end)
end)
