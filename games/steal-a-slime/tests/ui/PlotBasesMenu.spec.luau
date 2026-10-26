--!strict
-- The base strip in the Plot skins menu (FEATURES.BaseShapes, contract/base-shapes.md): one button per base across
-- the top, each saying Equip, Equipped or the rebirth it unlocks at; Equip asks the server (EquipPlotBase). Without
-- State.plotBases there is no strip and the menu looks as before.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local PlayerData = require("../../src/shared/PlayerData")
local PlotBases = require("../../src/shared/PlotBases")
local PlotBasesView = require("../../src/ui/PlotBasesView")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local SlimeLooks = require("../../src/shared/SlimeLooks")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = (require("@lune/roblox") :: any).UDim2

local function bases(rebirths: number, equipped: string?): { any }
	local data = PlayerData.new()
	data.rebirths = rebirths
	data.plotBase = equipped or "jar"
	return PlotBases.view(data)
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

local function open(w: number, h: number, state: any, requests: { any }?): (any, Layout.Rect)
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

local function skins(): { any }
	return PlotSkins.view(PlayerData.new())
end

describe("PlotBasesView.rows", function()
	it("is empty without State.plotBases (flag off)", function()
		expect(#PlotBasesView.rows(nil)).toBe(0)
		expect(#PlotBasesView.rows("junk")).toBe(0)
	end)
	it("one button per base, the jar first: Equipped, Equip once unlocked, else the rebirth it needs", function()
		local rows = PlotBasesView.rows(bases(20))
		expect(#rows).toBe(#Config.PLOT_BASES)
		expect(rows[1].id).toBe("jar")
		expect(rows[1].action).toBe(PlotBasesView.EQUIPPED)
		expect(rows[2].action).toBe(PlotBasesView.EQUIP)
		expect(rows[3].state).toBe("locked")
		expect(rows[3].action).toBe("Rebirth 25")
	end)
end)

describe("Plot skins menu: the base strip", function()
	it("shows one button per base above the skins, and none without State.plotBases", function()
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) })
		local strip = UiHarness.find(panel.frame, "Bases")
		expect(strip.Visible).toBe(true)
		expect(UiHarness.find(strip, "Base1"):GetAttribute("BaseId")).toBe("jar")
		expect(UiHarness.find(UiHarness.find(strip, "Base2"), "State").Text).toBe("Rebirth 20")
		local list = UiHarness.find(panel.frame, "List")
		expect(list.Position.Y.Offset >= strip.Size.Y.Offset).toBe(true)
		local plain = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins() })
		expect(UiHarness.find(plain.frame, "Bases").Visible).toBe(false)
		expect(UiHarness.find(plain.frame, "List").Position.Y.Offset).toBe(0)
	end)
	it("Equip asks the server with EquipPlotBase(baseId); a locked or equipped base asks nothing", function()
		local requests = {}
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(20) }, requests)
		local strip = UiHarness.find(panel.frame, "Bases")
		UiHarness.fire(UiHarness.find(strip, "Base1"), "Activated")
		UiHarness.fire(UiHarness.find(strip, "Base3"), "Activated")
		expect(#requests).toBe(0)
		UiHarness.fire(UiHarness.find(strip, "Base2"), "Activated")
		expect(#requests).toBe(1)
		expect(requests[1][1]).toBe("EquipPlotBase")
		expect(requests[1][2]).toBe("factory")
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(
			`{vp.name}: the strip's buttons fit the body side by side, their text fits, and the list sits below`,
			function()
				local panel, r =
					open(vp.w, vp.h, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(25) })
				local body = Layout.panelBody(r)
				local strip = UiHarness.find(panel.frame, "Bases")
				local right = 0
				for i = 1, #Config.PLOT_BASES do
					local b = UiHarness.find(strip, `Base{i}`)
					expect(b.Position.X.Offset >= right - 1e-6).toBe(true)
					right = b.Position.X.Offset + b.Size.X.Offset
					for _, name in { "Title", "State" } do
						local label = UiHarness.find(b, name)
						local problem = LayoutAssert.textFits({
							text = label.Text,
							size = label.TextSize,
							w = b.Size.X.Offset - 8,
							h = math.floor(b.Size.Y.Offset / 2) - 2,
							bold = true,
						} :: any)
						expect(problem).toBeNil()
					end
				end
				expect(right <= body.w + 1e-6).toBe(true)
				local list = UiHarness.find(panel.frame, "List")
				expect(list.Position.Y.Offset + list.Size.Y.Offset <= body.h + 1e-6).toBe(true)
			end
		)
	end
end)
