--!strict
-- The Plot skins menu (FEATURES.PlotSkins, contract/plot-skins.md): its own nav tile and panel. One row per skin
-- with its unlock progress, and a pane for the selected skin with the slimes that unlock it, found or not, and
-- Equip / Equipped / how many are still needed. Nothing but an empty line without State.plotSkins.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Nav = require("../../src/ui/Nav")
local PlayerData = require("../../src/shared/PlayerData")
local PlotSkins = require("../../src/shared/PlotSkins")
local PlotSkinsView = require("../../src/ui/PlotSkinsView")
local Remotes = require("../../src/shared/Remotes")
local SlimeDex = require("../../src/ui/SlimeDex")
local SlimeLooks = require("../../src/shared/SlimeLooks")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = (require("@lune/roblox") :: any).UDim2

-- The Garden skin (the second row): its family's slimes and how many found unlock it.
local GARDEN_SKIN = PlotSkins.get("garden") :: Config.PlotSkin
local GARDEN = PlotSkins.slimes(GARDEN_SKIN)
local NEED = PlotSkins.needed(GARDEN_SKIN)

local function found(gardenOwned: number): { string }
	local ids = {}
	for i, id in GARDEN do
		if i <= gardenOwned then
			table.insert(ids, id)
		end
	end
	return ids
end

local function view(gardenOwned: number, equipped: string?): { any }
	local data = PlayerData.new()
	for _, id in found(gardenOwned) do
		data.found[id] = true
	end
	data.plotSkin = equipped or "classic"
	return PlotSkins.view(data)
end

local function lookup(id: string): (string?, { number }?, string?)
	local entry, look = SlimeRoster.get(id), SlimeLooks.get(id)
	return if entry then entry.name else nil, if look then look.color else nil, SpeciesDex.setName(id)
end

local function slimesOf(id: string): { string }
	return PlotSkins.slimes(PlotSkins.get(id) :: Config.PlotSkin)
end

local function ctx(requests: { any }?): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		SlimeRoster = SlimeRoster,
		SlimeLooks = SlimeLooks,
		PlotSkins = PlotSkins,
		setName = SpeciesDex.setName,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
		request = function(action: string, _cb: any, ...: any)
			table.insert(requests or {}, { action, ... })
		end,
	}
end

local function openSkins(w: number, h: number, state: any, requests: { any }?): (any, Layout.Rect)
	local panel = UiHarness.ui("Panels/Skins").new(UiHarness.root(), ctx(requests))
	local raw = Layout.panelFor(Layout.screen(w, h), "Skins")
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	panel.layout(r)
	panel.update(state)
	panel.setOpen(true)
	panel.frame.Visible = true
	return panel, r
end

describe("PlotSkinsView.rows", function()
	it("is empty without State.plotSkins (flag off)", function()
		expect(#PlotSkinsView.rows(nil, Config)).toBe(0)
		expect(#PlotSkinsView.rows("junk", Config)).toBe(0)
		expect(#PlotSkinsView.rows({}, Config)).toBe(0)
	end)
	it("one row per skin, classic first and equipped; a locked one counts toward unlocking it", function()
		local rows = PlotSkinsView.rows(view(NEED - 1), Config)
		expect(#rows).toBe(#Config.PLOT_SKINS)
		expect(rows[1].key).toBe("skin:classic")
		expect(rows[1].state).toBe("equipped")
		expect(rows[1].count).toBe("")
		expect(rows[2].title).toBe("Garden")
		expect(rows[2].state).toBe("locked")
		expect(rows[2].count).toBe(`{NEED - 1}/{NEED}`)
		expect(rows[2].fraction).toBeCloseTo((NEED - 1) / NEED)
		expect(PlotSkinsView.summary(rows)).toBe(`1/{#rows} unlocked`)
	end)
	it("an unlocked skin is unlocked, an equipped one equipped", function()
		expect(PlotSkinsView.rows(view(NEED), Config)[2].state).toBe("unlocked")
		expect(PlotSkinsView.rows(view(NEED, "garden"), Config)[2].state).toBe("equipped")
		expect(PlotSkinsView.firstSelected(PlotSkinsView.rows(view(NEED, "garden"), Config))).toBe("garden")
	end)
end)

describe("PlotSkinsView.detail", function()
	it("lists the skin's slimes, found or not, and how many are still needed", function()
		local cards = SlimeDex.cards(Fixtures.dex(found(1)), Config, lookup)
		local d = PlotSkinsView.detail(view(1), "garden", cards, slimesOf) :: PlotSkinsView.Detail
		expect(d.title).toBe("Garden")
		expect(d.line).toBe(`Find {NEED} of these {#GARDEN} slimes`)
		expect(d.count).toBe(`1/{NEED}`)
		expect(#d.slimes).toBe(#GARDEN)
		expect(d.slimes[1].found).toBe(true)
		expect(d.slimes[1].tag).toBe("Found")
		expect(d.slimes[2].found).toBe(false)
		expect(d.slimes[2].tag).toBe("Garden")
		local left = NEED - 1
		expect(d.action).toBe(`Need {left} more slime{if left == 1 then "" else "s"}`)
	end)
	it("a collection skin tags an unfound hybrid Merge", function()
		local cards = SlimeDex.cards(Fixtures.dex({}), Config, lookup)
		local d = PlotSkinsView.detail(view(0), "candy", cards, slimesOf) :: PlotSkinsView.Detail
		local tags = {}
		for _, s in d.slimes do
			tags[s.species] = s.tag
		end
		expect(tags.soda).toBe("Merge")
		expect(tags.gummy).toBe("Meadow")
	end)
	it("classic needs nothing; Equip once unlocked, Equipped once worn", function()
		local cards = SlimeDex.cards(Fixtures.dex({}), Config, lookup)
		local classic = PlotSkinsView.detail(view(0), "classic", cards, slimesOf) :: PlotSkinsView.Detail
		expect(classic.line).toBe("Every player has this skin")
		expect(classic.count).toBeNil()
		expect(classic.action).toBe("Equipped")
		local ready = PlotSkinsView.detail(view(NEED), "garden", cards, slimesOf) :: PlotSkinsView.Detail
		expect(ready.action).toBe("Equip")
		expect(PlotSkinsView.detail(nil, "garden", cards, slimesOf)).toBeNil()
		expect(PlotSkinsView.detail(view(0), "nope", cards, slimesOf)).toBeNil()
	end)
end)

describe("Plot skins panel", function()
	it("has its own nav tile after Codes, with a plot skin picture", function()
		local index: { [string]: number } = {}
		for i, entry in Nav.ENTRIES do
			index[entry.key] = i
			if entry.key == "Skins" then
				expect(entry.label).toBe("Skins")
				expect(string.sub(entry.item, 1, 9)).toBe("PlotSkin_")
			end
		end
		expect(index.Skins).toBe(index.Codes + 1)
	end)
	it("lists every skin with its state, the equipped one selected and shown in the pane", function()
		local panel = openSkins(1920, 1080, { dex = Fixtures.dex(found(NEED)), plotSkins = view(NEED) })
		local list = UiHarness.find(panel.frame, "List")
		local classic = UiHarness.find(list, "skin:classic")
		local garden = UiHarness.find(list, "skin:garden")
		local candy = UiHarness.find(list, "skin:candy")
		expect(classic:GetAttribute("Selected")).toBe(true)
		expect(UiHarness.find(classic, "State").Text).toBe("Equipped")
		expect(UiHarness.find(garden, "State").Text).toBe("Unlocked")
		expect(UiHarness.find(candy, "Progress").Visible).toBe(true)
		expect(UiHarness.find(garden, "Progress").Visible).toBe(false)
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "PaneTitle").Text).toBe("Classic ranch")
		expect(UiHarness.find(pane, "Well").Text).toBe("Equipped")
		expect(UiHarness.find(pane, "Equip").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Summary").Text).toBe(`2/{#Config.PLOT_SKINS} unlocked`)
	end)
	it("picking a skin shows its slimes; Equip asks the server with EquipPlotSkin(skinId)", function()
		local requests = {}
		local panel = openSkins(1920, 1080, { dex = Fixtures.dex(found(NEED)), plotSkins = view(NEED) }, requests)
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "List"), "skin:garden"), "Activated")
		expect(panel.selected()).toBe("garden")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Slime1"):GetAttribute("Species")).toBe(GARDEN[1])
		expect(UiHarness.find(pane, "Slime1"):GetAttribute("Found")).toBe(true)
		local equip = UiHarness.find(pane, "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		expect(#requests).toBe(1)
		expect(requests[1][1]).toBe("EquipPlotSkin")
		expect(requests[1][2]).toBe("garden")
	end)
	it("a locked skin's pane says how many slimes are still needed and has no Equip", function()
		local panel = openSkins(1920, 1080, { dex = Fixtures.dex({}), plotSkins = view(0) })
		panel.select("garden")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Equip").Visible).toBe(false)
		expect(UiHarness.find(pane, "Well").Text).toBe(`Need {NEED} more slimes`)
		expect(UiHarness.find(pane, "Slime1"):GetAttribute("Found")).toBe(false)
	end)
	it("measures as a full-height list menu once open, so init.client fills the window with it", function()
		local panel = openSkins(1920, 1080, { dex = Fixtures.dex({}), plotSkins = view(0) })
		local content = UiHarness.ui("Widgets").contentHeight(UiHarness.find(panel.frame, "Body"))
		local c = Layout.PANEL_CHROME
		expect(content).toBe(Layout.menuHeight("Skins") - c.header - c.pad)
	end)
	it("shows only its empty line without State.plotSkins", function()
		local panel = openSkins(1920, 1080, { dex = Fixtures.dex({}) })
		expect(UiHarness.find(panel.frame, "Empty").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "Empty").Text).toBe(PlotSkinsView.EMPTY)
		expect(UiHarness.find(panel.frame, "List").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Pane").Visible).toBe(false)
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: rows, pane and slime cells stay inside the body`, function()
			local panel, r = openSkins(vp.w, vp.h, { dex = Fixtures.dex({}), plotSkins = view(0) })
			panel.select("starlight")
			local body = Layout.panelBody(r)
			local list = UiHarness.find(panel.frame, "List")
			local pane = UiHarness.find(panel.frame, "Pane")
			expect(list.Size.X.Offset <= pane.Position.X.Offset).toBe(true)
			expect(pane.Position.X.Offset + pane.Size.X.Offset <= body.w + 1e-6).toBe(true)
			for _, child in pane:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					local w = child.Size.X.Scale * pane.Size.X.Offset + child.Size.X.Offset
					local x = child.Position.X.Scale * pane.Size.X.Offset + child.Position.X.Offset
					local left = x - child.AnchorPoint.X * w
					expect(left >= 0).toBe(true)
					expect(left + w <= pane.Size.X.Offset + 1e-6).toBe(true)
				end
			end
		end)
	end
end)
