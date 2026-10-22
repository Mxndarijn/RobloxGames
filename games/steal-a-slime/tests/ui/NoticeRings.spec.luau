--!strict
-- Goo notices wear two rings (Widgets.ring): a coloured one that says what kind of notice it is (Gold = info
-- or guidance, the danger pink for a threat) and an Ink one around it. The left-menu tile shows the open
-- menu with the Gold ring (NavTile).
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function strokeOf(frame: any): any
	return frame:FindFirstChildOfClass("UIStroke")
end

describe("notice rings", function()
	it("Widgets.ring puts the colour on the card and an Ink ring around it", function()
		local Widgets = UiHarness.ui("Widgets")
		local root = UiHarness.root()
		local card = Widgets.create("Frame", { Name = "Card", Parent = root })
		local stroke, wrap = Widgets.ring(card, Widgets.Theme.Gold, 18)
		expect(stroke.Color).toBe(Widgets.Theme.Gold)
		expect(stroke.Parent == card).toBe(true)
		expect(wrap.Name).toBe("InkRing")
		expect(strokeOf(wrap).Color).toBe(Widgets.Theme.Ink)
		expect(wrap.Size.X.Offset).toBe(Widgets.KIT.stroke * 2)
	end)

	it("the carry card is Gold for a wild slime and the danger pink for a stolen one", function()
		local Widgets = UiHarness.ui("Widgets")
		local root = UiHarness.root()
		local carry = UiHarness.ui("Panels/Carry").new(root, {
			Genome = {
				displayName = function()
					return "Common Pebble"
				end,
			},
			send = function() end,
		})
		local slime = { id = "s1", name = "Pebble", tier = 1, color = { 170, 220, 170 } }
		carry.update({ carrying = { slime = slime, kind = "wild", startedAt = 0, walkSpeed = 16 } })
		local card = UiHarness.find(root, "CarryOverlay")
		expect(strokeOf(card).Color).toBe(Widgets.Theme.Gold)
		carry.update({ carrying = { slime = slime, kind = "stolen", ownerUserId = 2, startedAt = 0, walkSpeed = 16 } })
		expect(strokeOf(card).Color).toBe(Widgets.Theme.Bad)
	end)

	it("the open menu's tile wears the Gold ring and a gold label; the tile stays mint", function()
		local Widgets = UiHarness.ui("Widgets")
		local NavTile = UiHarness.ui("NavTile")
		local root = UiHarness.root()
		local tile = Widgets.create("Frame", { Name = "Tile", Parent = root })
		local label = Widgets.label({ Name = "Label", Parent = root })
		local stroke = NavTile.dress(tile)
		NavTile.paint(tile, stroke, label, true)
		expect(stroke.Color).toBe(Widgets.Theme.Gold)
		expect(label.TextColor3).toBe(Widgets.Theme.Gold)
		expect(tile.BackgroundColor3).toBe(Widgets.Theme.Good)
		NavTile.paint(tile, stroke, label, false)
		expect(stroke.Color).toBe(Widgets.Theme.Ink)
		expect(label.TextColor3).toBe(Widgets.Theme.Text)
		expect(tile.BackgroundColor3).toBe(Widgets.Theme.Good)
	end)
end)
