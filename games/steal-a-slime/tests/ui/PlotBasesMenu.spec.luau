--!strict
-- The Skins menu's Building tab (FEATURES.BaseShapes, contract/base-shapes.md) and Buy on Exclusive base skins: one
-- row per base like the Cloud tab's, Equipped / Unlocked or a gold Exclusive tag with its price; the pane's Equip asks
-- the server (EquipPlotBase), and Buy on an Exclusive base or skin prompts Base_<id> / Skin_<id> (or opens the
-- Exclusive shop on it while not on sale). Nothing sits above the tabs: every tab's list starts right under them.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local ExclusiveShopView = require("../../src/ui/ExclusiveShopView")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local PlayerData = require("../../src/shared/PlayerData")
local PlotBases = require("../../src/shared/PlotBases")
local PlotBasesView = require("../../src/ui/PlotBasesView")
local PlotSkins = require("../../src/shared/PlotSkins")
local PlotSkinsView = require("../../src/ui/PlotSkinsView")
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

-- Config with Base_rocket and Skin_fairground on sale (Roblox product ids), the rest not on sale yet (UnsoldConfig).
local function onSaleConfig(): any
	local products = setmetatable({
		Base_rocket = { productId = 4242, robux = 499, grant = { kind = "plotBase", style = "rocket" } },
		Skin_fairground = { productId = 4343, robux = 299, grant = { kind = "plotSkin", style = "fairground" } },
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

local function prompter(into: { any }): any
	return {
		prompt = function(p: any): boolean
			table.insert(into, p)
			return true
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

local function byId(rows: { any }): { [string]: any }
	local out = {}
	for _, row in rows do
		out[row.id] = row
	end
	return out
end

describe("ExclusiveShopView.offer", function()
	it("prices a product and gives its Purchase only while on sale", function()
		local sold = ExclusiveShopView.offer(onSaleConfig(), "Base_rocket") :: ExclusiveShopView.Offer
		expect(sold.price).toBe("R$499")
		expect(sold.text).toBe("Buy · R$499")
		expect(sold.purchase).toEqual({ kind = "product", id = 4242 })
		local unsold = ExclusiveShopView.offer(UnsoldConfig, "Base_carousel") :: ExclusiveShopView.Offer
		expect(unsold.price).toBe("R$599")
		expect(unsold.purchase).toBeNil()
		expect(ExclusiveShopView.offer(UnsoldConfig, "Base_nope")).toBeNil()
	end)
end)

describe("PlotBasesView", function()
	it("is empty without State.plotBases (flag off)", function()
		expect(#PlotBasesView.rows(nil)).toBe(0)
		expect(#PlotBasesView.rows("junk")).toBe(0)
		expect(PlotBasesView.detail(nil, "jar")).toBeNil()
	end)
	it("one row per base, the jar first and equipped; rebirths never unlock an Exclusive", function()
		local rows = PlotBasesView.rows(bases(30, nil, { "factory" }), Config)
		expect(#rows).toBe(#Config.PLOT_BASES)
		expect(rows[1].id).toBe("jar")
		expect(rows[1].key).toBe("base:jar")
		expect(rows[1].state).toBe("equipped")
		expect(rows[2].id).toBe("factory")
		expect(rows[2].state).toBe("unlocked")
		expect(rows[2].exclusive).toBe(false)
		expect(rows[3].id).toBe("pagoda")
		expect(rows[3].state).toBe("locked")
		expect(rows[3].exclusive).toBe(true)
		expect(rows[3].price).toBe("R$399")
		expect(PlotBasesView.summary(rows)).toBe(`2/{#Config.PLOT_BASES} unlocked`)
		expect(PlotBasesView.firstSelected(rows)).toBe("jar")
	end)
	it("the pane: Equip / Equipped once owned, Buy with its price, the shop while not on sale", function()
		local state = bases(0, "rocket", { "rocket", "lighthouse" })
		expect((PlotBasesView.detail(state, "rocket", UnsoldConfig) :: any).action).toBe(PlotBasesView.EQUIPPED)
		local lighthouse = PlotBasesView.detail(state, "lighthouse", UnsoldConfig) :: any
		expect(lighthouse.action).toBe(PlotBasesView.EQUIP)
		expect(lighthouse.line).toBe(PlotBasesView.OWNED_LINE)
		expect(lighthouse.exclusive).toBe(false)
		expect((PlotBasesView.detail(state, "jar", UnsoldConfig) :: any).line).toBe(PlotBasesView.FREE_LINE)
		local carousel = PlotBasesView.detail(state, "carousel", UnsoldConfig) :: any
		expect(carousel.exclusive).toBe(true)
		expect(carousel.heading).toBe("How to get it")
		expect(carousel.action).toBe(PlotBasesView.EXCLUSIVE_ACTION)
		expect(carousel.purchase).toBeNil()
		expect(carousel.shopKey).toBe("plotBase:carousel")
		local rocket = PlotBasesView.detail(bases(0), "rocket", onSaleConfig()) :: any
		expect(rocket.action).toBe("Buy · R$499")
		expect(rocket.purchase).toEqual({ kind = "product", id = 4242 })
		-- as shipped every Exclusive base is on sale: Buy prompts its Base_<id> product
		for _, row in PlotBasesView.rows(bases(0), Config) do
			if row.exclusive then
				local product = Config.EXCLUSIVE_SHOP.products[`Base_{row.id}`]
				expect(product.productId > 0).toBe(true)
				local detail = PlotBasesView.detail(bases(0), row.id, Config) :: any
				expect(detail.purchase).toEqual({ kind = "product", id = product.productId })
				expect(detail.action).toBe(`Buy · R${product.robux}`)
			end
		end
	end)
end)

describe("Skins menu: Building tab", function()
	it("has three tabs, Base, Building and Cloud, and nothing above the lists", function()
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) })
		for _, key in { "base", "building", "cloud" } do
			expect(UiHarness.find(panel.frame, `Tab_{key}`) ~= nil).toBe(true)
		end
		expect(UiHarness.find(panel.frame, "Bases")).toBeNil()
		local tab = UiHarness.find(panel.frame, "Tab_base")
		local list = UiHarness.find(panel.frame, "List")
		expect(list.Position.Y.Offset < tab.Size.Y.Offset + 20).toBe(true)
		panel.setTab("building")
		local baseList = UiHarness.find(panel.frame, "BaseList")
		expect(baseList.Visible).toBe(true)
		expect(list.Visible).toBe(false)
		expect(baseList.Position.Y.Offset).toBe(list.Position.Y.Offset)
		expect(UiHarness.find(panel.frame, "Summary").Text).toBe(`1/{#Config.PLOT_BASES} unlocked`)
	end)
	it("lists every base: the jar Equipped, an Exclusive with its gold tag and price", function()
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) })
		panel.setTab("building")
		local list = UiHarness.find(panel.frame, "BaseList")
		local jar = UiHarness.find(list, "base:jar")
		expect(UiHarness.find(jar, "State").Text).toBe("Equipped")
		expect(UiHarness.find(jar, "Exclusive").Visible).toBe(false)
		expect(UiHarness.find(jar, "Price").Visible).toBe(false)
		local carousel = UiHarness.find(list, "base:carousel")
		expect(carousel:GetAttribute("BaseId")).toBe("carousel")
		expect(UiHarness.find(carousel, "Exclusive").Visible).toBe(true)
		expect(UiHarness.find(carousel, "Price").Text).toBe("R$599")
		expect(UiHarness.find(carousel, "Progress").Visible).toBe(false)
		expect(UiHarness.find(carousel, "Line").Visible).toBe(false)
	end)
	it("without State.plotBases the tab says buildings are not on this server", function()
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins() })
		panel.setTab("building")
		expect(UiHarness.find(panel.frame, "Empty").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "Empty").Text).toBe(PlotBasesView.EMPTY)
		expect(UiHarness.find(panel.frame, "BaseList").Visible).toBe(false)
	end)
	it("Equip asks the server with EquipPlotBase(baseId)", function()
		local requests = {}
		local state = { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0, nil, { "factory" }) }
		local panel = open(1920, 1080, state, requests)
		panel.setTab("building")
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "BaseList"), "base:factory"), "Activated")
		expect(panel.selected()).toBe("factory")
		local equip = UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		expect(requests).toEqual({ { "EquipPlotBase", "factory" } })
	end)
	it("Buy on an Exclusive base on sale opens Roblox's prompt; once owned it is Equip", function()
		local requests, prompts = {}, {}
		local c = ctx(requests, onSaleConfig())
		c.purchase = prompter(prompts)
		local state = { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) }
		local panel = open(1920, 1080, state, nil, c)
		panel.setTab("building")
		panel.select("rocket")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Exclusive").Visible).toBe(true)
		local buy = UiHarness.find(pane, "Buy")
		expect(buy.Visible).toBe(true)
		expect(buy.Text).toBe("Buy · R$499")
		UiHarness.fire(buy, "Activated")
		expect(prompts).toEqual({ { kind = "product", id = 4242 } })
		expect(#requests).toBe(0)
		panel.update({ dex = state.dex, plotSkins = state.plotSkins, plotBases = bases(0, nil, { "rocket" }) })
		expect(buy.Visible).toBe(false)
		local equip = UiHarness.find(pane, "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		expect(#prompts).toBe(1)
		expect(requests).toEqual({ { "EquipPlotBase", "rocket" } })
	end)
	it("an Exclusive base not on sale opens the Exclusive shop on it", function()
		local opened = {}
		local c = ctx()
		c.purchase = prompter({})
		c.openExclusiveShop = function(key: string?)
			table.insert(opened, key)
		end
		local state = { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0), exclusiveShop = {} }
		local panel = open(1920, 1080, state, nil, c)
		panel.setTab("building")
		panel.select("carousel")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Buy").Visible).toBe(false)
		UiHarness.fire(UiHarness.find(pane, "ExclusiveShop"), "Activated")
		expect(opened).toEqual({ "plotBase:carousel" })
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: base rows, prices and the Buy pane stay inside the body`, function()
			local c = ctx(nil, onSaleConfig())
			c.purchase = prompter({})
			local state = { dex = Fixtures.dex({}), plotSkins = skins(), plotBases = bases(0) }
			local panel, r = open(vp.w, vp.h, state, nil, c)
			panel.setTab("building")
			panel.select("rocket")
			local body = Layout.panelBody(r)
			local list = UiHarness.find(panel.frame, "BaseList")
			local pane = UiHarness.find(panel.frame, "Pane")
			expect(list.Size.X.Offset <= pane.Position.X.Offset).toBe(true)
			expect(pane.Position.X.Offset + pane.Size.X.Offset <= body.w + 1e-6).toBe(true)
			expect(list.Position.Y.Offset + list.Size.Y.Offset <= body.h + 1e-6).toBe(true)
			for _, row in list:GetChildren() do
				local price = UiHarness.find(row, "Price")
				if price and price.Visible then
					local problem = LayoutAssert.textFits({
						text = price.Text,
						size = price.TextSize,
						w = price.Size.X.Offset,
						h = price.Size.Y.Offset,
						bold = true,
					} :: any)
					expect(problem).toBeNil()
				end
			end
			local buy = UiHarness.find(pane, "Buy")
			expect(buy.Visible).toBe(true)
			expect(buy.Position.X.Offset + buy.Size.X.Offset <= pane.Size.X.Offset + 1e-6).toBe(true)
			local problem = LayoutAssert.textFits({
				text = buy.Text,
				size = buy.TextSize,
				w = buy.Size.X.Offset - 16,
				h = buy.Size.Y.Offset,
				bold = true,
			} :: any)
			expect(problem).toBeNil()
		end)
	end
end)

describe("Skins menu: Exclusive base skins", function()
	it("an Exclusive skin's row shows its gold tag and price", function()
		local rows = byId(PlotSkinsView.rows(skins(), Config))
		local product = Config.EXCLUSIVE_SHOP.products.Skin_fairground
		expect(rows.fairground.exclusive).toBe(true)
		expect(rows.fairground.price).toBe(`R${product.robux}`)
		expect(rows.classic.price).toBe("")
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins() })
		local row = UiHarness.find(UiHarness.find(panel.frame, "List"), "skin:fairground")
		expect(UiHarness.find(row, "State").Text).toBe("Exclusive")
		expect(UiHarness.find(row, "Price").Visible).toBe(true)
		expect(UiHarness.find(row, "Price").Text).toBe(`R${product.robux}`)
	end)
	it("Buy on an Exclusive skin on sale opens Roblox's prompt for Skin_<id>", function()
		local prompts = {}
		local c = ctx(nil, onSaleConfig())
		c.purchase = prompter(prompts)
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins() }, nil, c)
		panel.select("fairground")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Line").Text).toBe("Buy it here or in the Exclusive shop.")
		local buy = UiHarness.find(pane, "Buy")
		expect(buy.Visible).toBe(true)
		expect(buy.Text).toBe("Buy · R$299")
		expect(UiHarness.find(pane, "Well").Visible).toBe(false)
		UiHarness.fire(buy, "Activated")
		expect(prompts).toEqual({ { kind = "product", id = 4343 } })
	end)
	it("not on sale it opens the Exclusive shop on that skin", function()
		local opened = {}
		local c = ctx()
		c.purchase = prompter({})
		c.openExclusiveShop = function(key: string?)
			table.insert(opened, key)
		end
		local panel = open(1920, 1080, { dex = Fixtures.dex({}), plotSkins = skins(), exclusiveShop = {} }, nil, c)
		panel.select("beach")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Buy").Visible).toBe(false)
		UiHarness.fire(UiHarness.find(pane, "ExclusiveShop"), "Activated")
		expect(opened).toEqual({ "plotSkin:beach" })
	end)
end)
