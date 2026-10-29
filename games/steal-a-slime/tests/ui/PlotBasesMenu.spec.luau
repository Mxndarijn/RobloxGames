--!strict
-- The base strip in the Plot skins menu (FEATURES.BaseShapes, contract/base-shapes.md): one button per base across
-- the top (two rows, scrolling sideways when they don't fit), each saying Equip, Equipped or the rebirth it unlocks
-- at; Equip asks the server (EquipPlotBase). An Exclusive base not owned yet has a gold Exclusive tag and Buy, which
-- prompts Base_<id> (or opens the Exclusive shop on it while not on sale). Without State.plotBases there is no strip.
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
local UnsoldConfig = require("./UnsoldConfig")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local roblox = require("@lune/roblox") :: any
local UDim2 = roblox.UDim2

local function bases(rebirths: number, equipped: string?, owned: { string }?): { any }
	local data = PlayerData.new()
	data.rebirths = rebirths
	data.plotBase = equipped or "jar"
	data.ownedStyles.plotBase = owned
	return PlotBases.view(data)
end

-- Config with Base_rocket on sale (a Roblox product id), everything else not on sale yet (UnsoldConfig).
local function onSaleConfig(): any
	local products = setmetatable({
		Base_rocket = { productId = 4242, robux = 499, grant = { kind = "plotBase", style = "rocket" } },
	}, { __index = UnsoldConfig.EXCLUSIVE_SHOP.products })
	local shop = setmetatable({ products = products }, { __index = UnsoldConfig.EXCLUSIVE_SHOP })
	return setmetatable({ EXCLUSIVE_SHOP = shop }, { __index = UnsoldConfig })
end

local function ctx(requests: { any }?, config: any?): any
	return {
		Config = config or UnsoldConfig, -- the shop ids cleared: nothing on sale unless a spec says so
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

local function open(w: number, h: number, state: any, requests: { any }?, c: any?): (any, Layout.Rect)
	local panel = UiHarness.ui("Panels/Skins").new(UiHarness.root(), c or ctx(requests))
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
		expect(rows[3].exclusive).toBe(false)
	end)
	it("an Exclusive base not owned is Exclusive with Buy and its price; owned it is Equip / Equipped", function()
		local rows = PlotBasesView.rows(bases(100, "rocket", { "rocket", "lighthouse" }), UnsoldConfig)
		local byId = {}
		for _, row in rows do
			byId[row.id] = row
		end
		expect(byId.carousel.exclusive).toBe(true)
		expect(byId.carousel.state).toBe("locked")
		expect(byId.carousel.action).toBe("Buy · R$599")
		expect(byId.carousel.shopKey).toBe("plotBase:carousel")
		expect(byId.carousel.purchase).toBeNil() -- productId 0: not on sale yet
		expect(byId.snowglobe.action).toBe("Buy · R$399")
		expect(byId.rocket.exclusive).toBe(false)
		expect(byId.rocket.action).toBe(PlotBasesView.EQUIPPED)
		expect(byId.lighthouse.action).toBe(PlotBasesView.EQUIP)
		local sale = PlotBasesView.rows(bases(0), onSaleConfig())
		for _, row in sale do
			if row.id == "rocket" then
				expect(row.purchase).toEqual({ kind = "product", id = 4242 })
			end
		end
		-- as shipped every Exclusive base is on sale: Buy prompts its Base_<id> product
		for _, row in PlotBasesView.rows(bases(0), Config) do
			if row.exclusive then
				local id = Config.EXCLUSIVE_SHOP.products[`Base_{row.id}`].productId
				expect(id > 0).toBe(true)
				expect(row.purchase).toEqual({ kind = "product", id = id })
			end
		end
	end)
end)

describe("Plot skins menu: the base strip", function()
	it("shows one button per base above the skins, and none without State.plotBases", function()
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) })
		local strip = UiHarness.find(panel.frame, "Bases")
		expect(strip.Visible).toBe(true)
		expect(UiHarness.find(strip, "Base1"):GetAttribute("BaseId")).toBe("jar")
		expect(UiHarness.find(UiHarness.find(strip, "Base2"), "State").Text).toBe("Rebirth 20")
		-- the strip sits under the tabs, the list under the strip
		local list = UiHarness.find(panel.frame, "List")
		expect(strip.Position.Y.Offset > 0).toBe(true)
		expect(list.Position.Y.Offset >= strip.Position.Y.Offset + strip.Size.Y.Offset).toBe(true)
		local plain = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins() })
		expect(UiHarness.find(plain.frame, "Bases").Visible).toBe(false)
		-- without bases the list starts right under the tabs, where the strip would be
		expect(UiHarness.find(plain.frame, "List").Position.Y.Offset).toBe(strip.Position.Y.Offset)
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
	it(
		"an Exclusive base not owned shows the gold Exclusive tag; Buy opens the shop on it while not on sale",
		function()
			local requests, opened = {}, {}
			local c = ctx(requests)
			c.openExclusiveShop = function(key: string?)
				table.insert(opened, key)
			end
			local panel =
				open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) }, nil, c)
			local strip = UiHarness.find(panel.frame, "Bases")
			local carousel = UiHarness.find(strip, "Base4")
			expect(carousel:GetAttribute("BaseId")).toBe("carousel")
			expect(UiHarness.find(carousel, "Exclusive").Visible).toBe(true)
			expect(UiHarness.find(carousel, "Exclusive").Text).toBe("Exclusive")
			expect(UiHarness.find(carousel, "State").Text).toBe("Buy · R$599")
			expect(UiHarness.find(UiHarness.find(strip, "Base1"), "Exclusive").Visible).toBe(false)
			UiHarness.fire(carousel, "Activated")
			expect(opened).toEqual({ "plotBase:carousel" })
			expect(#requests).toBe(0)
		end
	)
	it("Buy on an Exclusive base on sale opens Roblox's prompt; once owned it is Equip (EquipPlotBase)", function()
		local requests, prompts = {}, {}
		local c = ctx(requests, onSaleConfig())
		c.purchase = {
			prompt = function(p: any): boolean
				table.insert(prompts, p)
				return true
			end,
		}
		local state = { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) }
		local panel = open(1920, 1080, state, nil, c)
		local strip = UiHarness.find(panel.frame, "Bases")
		local rocket = UiHarness.find(strip, "Base5")
		expect(rocket:GetAttribute("BaseId")).toBe("rocket")
		UiHarness.fire(rocket, "Activated")
		expect(prompts).toEqual({ { kind = "product", id = 4242 } })
		expect(#requests).toBe(0)
		panel.update({ dex = state.dex, plotSkins = state.plotSkins, plotBases = bases(0, nil, { "rocket" }) })
		expect(UiHarness.find(rocket, "Exclusive").Visible).toBe(false)
		expect(UiHarness.find(rocket, "State").Text).toBe(PlotBasesView.EQUIP)
		UiHarness.fire(rocket, "Activated")
		expect(#prompts).toBe(1)
		expect(requests[1][1]).toBe("EquipPlotBase")
		expect(requests[1][2]).toBe("rocket")
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: the strip's buttons don't overlap, their text and tag fit, and the list sits below`, function()
			local panel, r = open(vp.w, vp.h, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(25) })
			local body = Layout.panelBody(r)
			local strip = UiHarness.find(panel.frame, "Bases")
			expect(LayoutAssert.box(strip).w <= body.w + 1e-6).toBe(true)
			local canvasW = strip.CanvasSize.X.Offset
			local boxes = {}
			for i = 1, #Config.PLOT_BASES do
				local b = UiHarness.find(strip, `Base{i}`)
				local x, y, w, h = b.Position.X.Offset, b.Position.Y.Offset, b.Size.X.Offset, b.Size.Y.Offset
				for _, o in boxes do
					local apart = x >= o.x + o.w or o.x >= x + w or y >= o.y + o.h or o.y >= y + h
					expect(apart).toBe(true)
				end
				table.insert(boxes, { x = x, y = y, w = w, h = h })
				expect(x + w <= canvasW + 1e-6).toBe(true)
				expect(y + h <= strip.Size.Y.Offset + 1e-6).toBe(true)
				for _, name in { "Title", "State" } do
					local label = UiHarness.find(b, name)
					local problem = LayoutAssert.textFits({
						text = label.Text,
						size = label.TextSize,
						w = label.Size.X.Offset + w * label.Size.X.Scale,
						h = label.Size.Y.Offset,
						bold = true,
					} :: any)
					expect(problem).toBeNil()
				end
				local tag = UiHarness.find(b, "Exclusive")
				if tag.Visible then
					local problem = LayoutAssert.textFits({
						text = tag.Text,
						size = tag.TextSize,
						w = w - 20,
						h = tag.Size.Y.Offset,
						bold = true,
					} :: any)
					expect(problem).toBeNil()
				end
			end
			if canvasW > strip.Size.X.Offset then
				expect(strip.ScrollingDirection).toBe(roblox.Enum.ScrollingDirection.X)
			end
			local list = UiHarness.find(panel.frame, "List")
			expect(list.Position.Y.Offset >= strip.Position.Y.Offset + strip.Size.Y.Offset).toBe(true)
			expect(list.Position.Y.Offset + list.Size.Y.Offset <= body.h + 1e-6).toBe(true)
			expect(list.Size.Y.Offset > 0).toBe(true)
		end)
	end
end)
