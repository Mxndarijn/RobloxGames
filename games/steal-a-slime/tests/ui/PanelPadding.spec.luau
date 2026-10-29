--!strict
-- One padding for every menu card: the body sits PANEL_CHROME.pad in from the card's sides and bottom, rows in a
-- scroll area use its full width (no strip kept free for the bar), and every scroll list keeps PANEL_CHROME.ring
-- of room on both sides so an outline at its edge is never clipped.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local ServerFixtures = require("../ServerFixtures")
local Snapshot = require("../../src/server/Snapshot")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Enum, UDim2 = roblox.Enum, roblox.UDim2

local T0 = ServerFixtures.T0
local C = Layout.PANEL_CHROME

local function ctx(): any
	local function none() end
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		TripleMerge = require("../../src/shared/TripleMerge"),
		vat3Forced = function()
			return false
		end,
		actions = Remotes.ACTIONS,
		itemIcons = UiHarness.ui("ItemIcons").build(Config),
		send = none,
		request = none,
		ask = none,
		serverNow = function()
			return T0 + 1
		end,
		playerName = function()
			return "Tester"
		end,
		togglePanel = none,
		toast = none,
	}
end

local function realState(): any
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, {
		Fixtures.slime("a", 1),
		Fixtures.slime("b", 2),
		Fixtures.slime("c", 3),
	}, 1240)
	local state = Snapshot.build(world, session, T0 + 1) :: any
	state.welcomeBack = { away = 19800, cash = 12400, grown = 3 }
	state.plotSkins = state.plotSkins or PlotSkins.view(session.data)
	return state
end

-- Every scroll area under `root` that breaks the rules, as "Name: why".
local function scrollProblems(root: any): { string }
	local out = {}
	for _, node in UiHarness.descendants(root) do
		-- a list (no background of its own); a side pane is a card and pads its own content
		if node.ClassName == "ScrollingFrame" and node.BackgroundTransparency >= 1 then
			local ring = node:FindFirstChild("Ring")
			if not ring or ring.PaddingLeft.Offset ~= C.ring or ring.PaddingRight.Offset ~= C.ring then
				table.insert(out, `{node.Name}: no {C.ring} px ring padding (made without Widgets.scroll?)`)
			end
			for _, row in node:GetChildren() do
				if row:IsA("GuiObject") and row.Size.X.Scale == 1 and row.Size.X.Offset < 0 then
					table.insert(out, `{node.Name}/{row.Name}: {row.Size.X.Offset} px short of the list width`)
				end
			end
		end
	end
	return out
end

local function openPanel(key: string): any
	local panel = UiHarness.ui(`Panels/{key}`).new(UiHarness.root(), ctx())
	if panel.setShop then
		panel.setShop("ItemShop")
	end
	if panel.update then
		panel.update(realState())
	end
	if panel.setOpen then
		panel.setOpen(true)
	end
	panel.frame.Visible = true
	return panel
end

describe("menu cards share one padding", function()
	it("the body sits PANEL_CHROME.pad in from the sides and bottom, the icon tile stays at tileX", function()
		local panel = UiHarness.ui("Widgets").panel(UiHarness.root(), "Probe", "Probe", "x")
		expect(panel.body.Position.X.Offset).toBe(C.pad)
		expect(panel.body.Size.X.Offset).toBe(-C.pad * 2)
		expect(panel.body.Size.Y.Offset).toBe(-(C.header + C.pad))
		expect(UiHarness.find(panel.frame, "IconTile").Position.X.Offset).toBe(C.tileX)
	end)
	it("Widgets.scroll bleeds its box by the ring on both sides and pads the content back in", function()
		local Widgets = UiHarness.ui("Widgets")
		local frame = Widgets.scroll({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -40, 0, 100) })
		expect(frame.Position.X.Offset).toBe(10 - C.ring)
		expect(frame.Position.Y.Offset).toBe(4)
		expect(frame.Size.X.Scale).toBe(1)
		expect(frame.Size.X.Offset).toBe(-40 + C.ring * 2)
		expect(frame.Size.Y.Offset).toBe(100)
		expect(frame.VerticalScrollBarInset).toBe(Enum.ScrollBarInset.ScrollBar)
		Widgets.place(frame, UDim2.fromOffset(0, 0), UDim2.fromOffset(200, 50))
		expect(frame.Position.X.Offset).toBe(-C.ring)
		expect(frame.Size.X.Offset).toBe(200 + C.ring * 2)
	end)
	local MENUS = { "Codes", "Dex", "Goals", "Guide", "Merge", "Rebirth", "Welcome", "WorldShop" }
	for _, key in MENUS do
		it(`{key}: rows fill their list and no outline is clipped`, function()
			local panel = openPanel(key)
			expect(table.concat(scrollProblems(panel.frame), ", ")).toBe("")
		end)
	end
end)
