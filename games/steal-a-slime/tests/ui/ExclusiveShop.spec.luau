--!strict
-- The Exclusive shop client (contract/exclusive-shop.md §1, §5, §8): ExclusiveShopView's cards, details and
-- quick-buys, the PurchasePrompt adapter, the Panels/ExclusiveShop card (tabs, owned / equipped / not on sale, the
-- restricted potion, Buy prompting Roblox with the right id, Bought, flag off) and its layout at the gate sizes.
local Config = require("./UnsoldConfig") -- every Exclusive id cleared: the specs start from "not on sale yet"
local Constants = require("../../src/shared/Constants")
local ExclusiveShopView = require("../../src/ui/ExclusiveShopView")
local Format = require("../../src/ui/Format")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local PurchasePrompt = require("../../src/ui/PurchasePrompt")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = (require("@lune/roblox") :: any).UDim2

-- Config with Roblox ids on every product and pass (id = 1000 + n), or only on `only` keys.
local function sellingConfig(only: { [string]: boolean }?): any
	local cat = Config.EXCLUSIVE_SHOP
	local products, passes = {}, {}
	local n = 0
	local keys = {}
	for key in cat.products do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		n += 1
		local def = table.clone(cat.products[key])
		def.productId = if only == nil or only[key] then 1000 + n else 0
		products[key] = def
	end
	local passKeys = {}
	for key in cat.passes do
		table.insert(passKeys, key)
	end
	table.sort(passKeys)
	for i, key in passKeys do
		local copy = table.clone(cat.passes[key])
		copy.passId = if only == nil or only[key] then 5000 + i else 0
		passes[key] = copy
	end
	local subs = {}
	for key, def in cat.subscriptions do
		local copy = table.clone(def)
		copy.subscriptionId = if only == nil or only[key] then `EXP-{key}` else ""
		subs[key] = copy
	end
	local shop = table.clone(cat)
	shop.products = products
	shop.passes = passes
	shop.subscriptions = subs
	local config = table.clone(Config)
	config.EXCLUSIVE_SHOP = shop
	return config
end

local function shopState(fields: { [string]: any }?): any
	local shop: any = {
		owned = {},
		passes = { Income2x = false, Offline2x = false },
		starterClaimed = false,
		credits = { brew = 0, hatch = 0 },
		offlineDouble = nil,
		paidRandomAllowed = true,
		featured = { "storm_cloud", "ufo", "leaf", "bubble" },
	}
	for k, v in fields or {} do
		shop[k] = v
	end
	return { exclusiveShop = shop, petSeat = "cloud", slimes = {}, vat = { ids = {} } }
end

local function fakeMarket(): any
	local calls = {}
	local function signal(): any
		local handlers = {}
		return {
			handlers = handlers,
			Connect = function(_self: any, fn: any)
				table.insert(handlers, fn)
			end,
		}
	end
	return {
		calls = calls,
		PromptProductPurchaseFinished = signal(),
		PromptGamePassPurchaseFinished = signal(),
		PromptProductPurchase = function(_self: any, who: any, id: number)
			table.insert(calls, { "product", who, id })
		end,
		PromptGamePassPurchase = function(_self: any, who: any, id: number)
			table.insert(calls, { "pass", who, id })
		end,
	}
end

local PLAYER = { UserId = 77 }

local function ctx(config: any, extra: { [string]: any }?): any
	local c: { [string]: any } = {
		Config = config,
		Constants = Constants,
		actions = Remotes.ACTIONS,
		send = function() end,
		request = function() end,
		ask = function() end,
		userId = PLAYER.UserId,
		giftPlayers = function()
			return {}
		end,
		serverNow = function()
			return 1000
		end,
	}
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

local function openShop(w: number, h: number, state: any, c: any, key: string?): (any, Layout.Rect)
	local panel = UiHarness.ui("Panels/ExclusiveShop").new(UiHarness.root(), c)
	local raw = Layout.panelFor(Layout.screen(w, h), "ExclusiveShop")
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	panel.layout(r)
	panel.update(state)
	panel.show(key)
	panel.setOpen(true)
	panel.frame.Visible = true
	return panel, r
end

local function keysOf(cards: { ExclusiveShopView.Card }): { string }
	local out = {}
	for _, card in cards do
		table.insert(out, card.key)
	end
	return out
end

describe("ExclusiveShopView cards", function()
	it("nothing at all without State.exclusiveShop (flag off)", function()
		expect(#ExclusiveShopView.tabs({}, Config)).toBe(0)
		for _, tab in Config.EXCLUSIVE_SHOP.tabs do
			expect(#ExclusiveShopView.cards(tab, {}, Config)).toBe(0)
		end
		expect(ExclusiveShopView.detail("seat:ufo", {}, Config)).toBeNil()
		expect(ExclusiveShopView.brewQuickBuy({ vat = { endsAt = 2000 } }, 1000, Config)).toBeNil()
		expect(ExclusiveShopView.doubleQuickBuy({}, Config)).toBeNil()
		expect(ExclusiveShopView.potionQuickBuy({}, Config)).toBeNil()
	end)
	it("tabs follow Config: Featured, Clouds, Style, Perks, Boosts", function()
		expect(table.concat(ExclusiveShopView.tabs(shopState(), Config), ",")).toBe(
			"Featured,Clouds,Style,Perks,Boosts"
		)
	end)
	it("Featured is the Starter bundle while unclaimed, then this week's seats", function()
		local keys = keysOf(ExclusiveShopView.cards("Featured", shopState(), Config))
		expect(table.concat(keys, ",")).toBe(
			"product:StarterBundle,product:BoutiqueBundle,product:SkyBundle,seat:storm_cloud,seat:ufo,seat:leaf,seat:bubble"
		)
		local claimed = keysOf(ExclusiveShopView.cards("Featured", shopState({ starterClaimed = true }), Config))
		expect(claimed[1]).toBe("product:BoutiqueBundle")
		expect(#claimed).toBe(6)
	end)
	it("Clouds lists the 16 Exclusive seats with their Robux price", function()
		local cards = ExclusiveShopView.cards("Clouds", shopState(), Config)
		expect(#cards).toBe(16)
		for _, card in cards do
			local robux = Config.EXCLUSIVE_SHOP.products[`Seat_{card.id}`].robux
			expect(card.tag).toBe(Format.robux(robux))
			expect(card.icon).toBe(`PetSeat_{card.id}`)
		end
	end)
	it("an owned seat says Owned, the worn one Equipped", function()
		local state = shopState({ owned = { ufo = true, leaf = true } })
		state.petSeat = "leaf"
		local byId = {}
		for _, card in ExclusiveShopView.cards("Clouds", state, Config) do
			byId[card.id] = card
		end
		expect(byId.ufo.state).toBe("owned")
		expect(byId.ufo.tag).toBe("Owned")
		expect(byId.leaf.state).toBe("equipped")
		expect(byId.leaf.tag).toBe("Equipped")
		expect(byId.bubble.state).toBe("offsale")
		expect(ExclusiveShopView.ownedSummary(state, Config)).toBe("2/16 owned")
	end)
	it(
		"Perks are the passes in their order, then the Slime Club; Boosts the server and personal boosts, then where the skips are sold",
		function()
			local perks = keysOf(ExclusiveShopView.cards("Perks", shopState(), Config))
			expect(table.concat(perks, ",")).toBe(
				"pass:VIP,pass:Income2x,pass:Offline2x,pass:FastBrew,pass:WarmNest,pass:LuckyCharmPlus,pass:ThiefRadar,pass:AutoCollect,sub:SlimeClub"
			)
			local boosts = keysOf(ExclusiveShopView.cards("Boosts", shopState(), Config))
			expect(table.concat(boosts, ",")).toBe(
				"product:ServerLuckPotion,product:SlimeRain,product:WeatherTotem,product:SummonBoss,product:IncomeBoost15,"
					.. "product:IncomeBoost60,info:FinishBrew,info:HatchNow,info:DoubleOffline,info:KeepStreak,info:GrowthSnack"
			)
		end
	)
	it(
		"restricted paid random items hide every odds changer: the potion, Slime Rain, the totem and Lucky Charm+",
		function()
			local state = shopState({ paidRandomAllowed = false })
			local boosts = keysOf(ExclusiveShopView.cards("Boosts", state, Config))
			expect(table.concat(boosts, ",")).toBe(
				"product:SummonBoss,product:IncomeBoost15,product:IncomeBoost60,info:FinishBrew,info:HatchNow,"
					.. "info:DoubleOffline,info:KeepStreak,info:GrowthSnack"
			)
			local perks = keysOf(ExclusiveShopView.cards("Perks", state, Config))
			expect(table.find(perks, "pass:LuckyCharmPlus")).toBeNil()
		end
	)
	it("the paid Luck Potion is hidden where paid random items are restricted", function()
		local boosts = keysOf(ExclusiveShopView.cards("Boosts", shopState({ paidRandomAllowed = false }), Config))
		expect(table.find(boosts, "product:ServerLuckPotion")).toBeNil()
		expect(ExclusiveShopView.detail("product:ServerLuckPotion", shopState({ paidRandomAllowed = false }), Config)).toBeNil()
		expect(ExclusiveShopView.potionQuickBuy(shopState({ paidRandomAllowed = false }), Config)).toBeNil()
	end)
end)

describe("ExclusiveShopView details", function()
	it("id 0 shows the price and a disabled Not on sale yet, never Coming soon", function()
		local d = ExclusiveShopView.detail("seat:ufo", shopState(), Config) :: ExclusiveShopView.Detail
		expect(d.priceText).toBe("R$399")
		expect(d.action.kind).toBe("offsale")
		expect(d.action.text).toBe("Not on sale yet")
		for _, tab in Config.EXCLUSIVE_SHOP.tabs do
			for _, card in ExclusiveShopView.cards(tab, shopState(), Config) do
				local detail = ExclusiveShopView.detail(card.key, shopState(), Config) :: ExclusiveShopView.Detail
				expect(string.find(string.lower(detail.action.text .. detail.text), "coming soon", 1, true)).toBeNil()
			end
		end
	end)
	it("with an id Buy carries the product or pass to prompt", function()
		local config = sellingConfig()
		local seat = ExclusiveShopView.detail("seat:ufo", shopState(), config) :: ExclusiveShopView.Detail
		expect(seat.action.kind).toBe("buy")
		expect(seat.action.text).toBe("Buy · R$399")
		expect((seat.action.purchase :: any).kind).toBe("product")
		expect((seat.action.purchase :: any).id).toBe(config.EXCLUSIVE_SHOP.products.Seat_ufo.productId)
		local pass = ExclusiveShopView.detail("pass:Income2x", shopState(), config) :: ExclusiveShopView.Detail
		expect((pass.action.purchase :: any).kind).toBe("pass")
		expect((pass.action.purchase :: any).id).toBe(config.EXCLUSIVE_SHOP.passes.Income2x.passId)
		local potion = ExclusiveShopView.detail("product:ServerLuckPotion", shopState(), config) :: any
		expect(potion.action.text).toBe("Buy · R$79")
	end)
	it("owned seats Equip, owned passes are a well", function()
		local state = shopState({ owned = { ufo = true }, passes = { Income2x = true } })
		expect((ExclusiveShopView.detail("seat:ufo", state, Config) :: any).action.kind).toBe("equip")
		local pass = ExclusiveShopView.detail("pass:Income2x", state, Config) :: any
		expect(pass.action.kind).toBe("well")
		expect(pass.action.text).toBe("Owned")
	end)
	it("the potion's odds add up to 100 % without and with it, rare tiers up by LUCK_POTION_MULT", function()
		local rows = ExclusiveShopView.potionOdds(Config)
		expect(#rows).toBe(#Config.RARITIES)
		local total, boostedTotal = 0, 0
		for _, r in Config.RARITIES do
			total += r.weight
			boostedTotal += if r.tier >= 3 then r.weight * Config.LUCK_POTION_MULT else r.weight
		end
		expect(rows[1].base).toBe(ExclusiveShopView.percent(Config.RARITIES[1].weight / total))
		expect(rows[3].boosted).toBe(
			ExclusiveShopView.percent(Config.RARITIES[3].weight * Config.LUCK_POTION_MULT / boostedTotal)
		)
		local sumBase, sumBoost = 0, 0
		for _, row in rows do
			sumBase += tonumber((string.gsub(row.base, "%%", ""))) :: number
			sumBoost += tonumber((string.gsub(row.boosted, "%%", ""))) :: number
		end
		expect(sumBase).toBeCloseTo(100, 0.5)
		expect(sumBoost).toBeCloseTo(100, 0.5)
		local effect = ExclusiveShopView.potionEffect(Config)
		expect(effect[1]).toBe(`{Config.RARITIES[3].name} and rarer: x{Config.LUCK_POTION_MULT} chance`)
		expect(effect[2]).toBe(`+{Config.LUCK_POTION_SECONDS // 60} min for everyone on the server`)
		expect(effect[3]).toBe(`Up to {Config.LUCK_POTION_MAX_SECONDS // 60} min queued`)
	end)
	it("percent keeps rare tiers readable", function()
		expect(ExclusiveShopView.percent(0.52)).toBe("52%")
		expect(ExclusiveShopView.percent(0.052)).toBe("5.2%")
		expect(ExclusiveShopView.percent(0.002)).toBe("0.2%")
		expect(ExclusiveShopView.percent(0.00004)).toBe("0.004%")
	end)
end)

describe("ExclusiveShopView quick-buys", function()
	local brackets = Config.EXCLUSIVE_SHOP.finishBrewBrackets
	it("Finish now picks the product by the time left", function()
		expect(ExclusiveShopView.finishBrewKey(10, Config)).toBe("FinishBrew_1")
		expect(ExclusiveShopView.finishBrewKey(brackets[1], Config)).toBe("FinishBrew_1")
		expect(ExclusiveShopView.finishBrewKey(brackets[1] + 1, Config)).toBe("FinishBrew_2")
		expect(ExclusiveShopView.finishBrewKey(brackets[3] + 1, Config)).toBe("FinishBrew_4")
		local config = sellingConfig()
		local state = shopState()
		state.vat = { ids = { "a", "b", "c" }, endsAt = 1000 + brackets[1] + 60 }
		local q = ExclusiveShopView.brewQuickBuy(state, 1000, config) :: ExclusiveShopView.QuickBuy
		expect(q.mode).toBe("buy")
		expect(q.key).toBe("FinishBrew_2")
		expect(q.text).toBe(`Finish now · {Format.robux(config.EXCLUSIVE_SHOP.products.FinishBrew_2.robux)}`)
		expect((q.purchase :: any).id).toBe(config.EXCLUSIVE_SHOP.products.FinishBrew_2.productId)
	end)
	it("Finish now hides when not brewing or ready, and is Use credit with a brew credit", function()
		local state = shopState({ credits = { brew = 1, hatch = 0 } })
		expect(ExclusiveShopView.brewQuickBuy(state, 1000, Config)).toBeNil()
		state.vat = { ids = {}, endsAt = 900 }
		expect(ExclusiveShopView.brewQuickBuy(state, 1000, Config)).toBeNil()
		state.vat = { ids = {}, endsAt = 1100 }
		expect((ExclusiveShopView.brewQuickBuy(state, 1000, Config, true) :: any).mode).toBe("credit")
		expect((ExclusiveShopView.brewQuickBuy(state, 1000, Config, true) :: any).text).toBe("Use credit")
		-- without the UseCredit request the credit can't be spent: the buy button stays
		expect((ExclusiveShopView.brewQuickBuy(state, 1000, Config, false) :: any).mode).toBe("offsale")
	end)
	it("Hatch now: only for an incubating egg, priced by its kind", function()
		local config = sellingConfig()
		local state = shopState()
		state.slimes = {
			{ slime = { id = "egg1", egg = { kind = "golden", hatchAt = 1500 } } },
			{ slime = { id = "egg2", egg = { kind = "cosmic", hatchAt = 900 } } },
			{ slime = { id = "s1" } },
		}
		local q = ExclusiveShopView.hatchQuickBuy(state, "egg1", 1000, config) :: ExclusiveShopView.QuickBuy
		expect(q.key).toBe("HatchNow_golden")
		expect(q.text).toBe(`Hatch now · {Format.robux(config.EXCLUSIVE_SHOP.products.HatchNow_golden.robux)}`)
		expect(ExclusiveShopView.hatchQuickBuy(state, "egg2", 1000, config)).toBeNil() -- ready
		expect(ExclusiveShopView.hatchQuickBuy(state, "s1", 1000, config)).toBeNil()
		state.exclusiveShop.credits = { brew = 0, hatch = 2 }
		expect((ExclusiveShopView.hatchQuickBuy(state, "egg1", 1000, config, true) :: any).mode).toBe("credit")
	end)
	it("Double it only while the payout can still be doubled", function()
		local config = sellingConfig()
		expect(ExclusiveShopView.doubleQuickBuy(shopState(), config)).toBeNil()
		expect(
			ExclusiveShopView.doubleQuickBuy(shopState({ offlineDouble = { cash = 500, available = false } }), config)
		).toBeNil()
		local q =
			ExclusiveShopView.doubleQuickBuy(shopState({ offlineDouble = { cash = 500, available = true } }), config)
		expect((q :: any).text).toBe("Double it · R$49")
	end)
	it("Buy for the server respects paidRandomAllowed", function()
		local config = sellingConfig()
		expect((ExclusiveShopView.potionQuickBuy(shopState(), config) :: any).text).toBe("Buy for the server · R$79")
		expect((ExclusiveShopView.potionQuickBuy(shopState(), Config) :: any).text).toBe("Not on sale yet")
	end)
end)

describe("PurchasePrompt adapter", function()
	it("prompts a product or a pass with its id; never for id 0", function()
		local market = fakeMarket()
		local adapter = PurchasePrompt.new(market, PLAYER)
		expect(adapter.prompt({ kind = "product", id = 123 })).toBe(true)
		expect(adapter.prompt({ kind = "pass", id = 456 })).toBe(true)
		expect(adapter.prompt({ kind = "product", id = 0 })).toBe(false)
		expect(#market.calls).toBe(2)
		expect(market.calls[1][1]).toBe("product")
		expect(market.calls[1][2]).toBe(PLAYER)
		expect(market.calls[1][3]).toBe(123)
		expect(market.calls[2][1]).toBe("pass")
		expect(market.calls[2][3]).toBe(456)
	end)
	it("tells listeners when this player's prompt closes", function()
		local market = fakeMarket()
		local adapter = PurchasePrompt.new(market, PLAYER)
		local closed = {}
		adapter.onClosed(function(bought: boolean)
			table.insert(closed, bought)
		end)
		market.PromptProductPurchaseFinished.handlers[1](999, 1, true) -- someone else
		market.PromptProductPurchaseFinished.handlers[1](PLAYER.UserId, 1, false)
		market.PromptGamePassPurchaseFinished.handlers[1](PLAYER, 2, true)
		expect(#closed).toBe(2)
		expect(closed[1]).toBe(false)
		expect(closed[2]).toBe(true)
	end)
end)

describe("Exclusive shop panel", function()
	it("is titled Exclusive shop and opens on Featured", function()
		local panel = openShop(1920, 1080, shopState(), ctx(Config))
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Exclusive shop")
		expect(panel.tab()).toBe("Featured")
		expect(UiHarness.find(panel.frame, "Tab_Featured"):GetAttribute("Selected")).toBe(true)
		expect(panel.selected()).toBe("product:StarterBundle")
		expect(UiHarness.find(UiHarness.find(panel.frame, "Grid"), "seat:storm_cloud") ~= nil).toBe(true)
	end)
	it("flag off: one closed line, no tabs, no cards", function()
		local panel = openShop(1920, 1080, { petSeat = "cloud" }, ctx(Config))
		expect(UiHarness.find(panel.frame, "Empty").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "Empty").Text).toBe(ExclusiveShopView.EMPTY)
		expect(UiHarness.find(panel.frame, "Tab_Featured").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Grid").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Pane").Visible).toBe(false)
	end)
	it("tapping a tab switches the grid; Clouds shows the owned count", function()
		local panel = openShop(1920, 1080, shopState({ owned = { ufo = true } }), ctx(Config))
		UiHarness.fire(UiHarness.find(panel.frame, "Tab_Clouds"), "Activated")
		expect(panel.tab()).toBe("Clouds")
		local grid = UiHarness.find(panel.frame, "Grid")
		expect(UiHarness.find(grid, "seat:hoverboard") ~= nil).toBe(true)
		expect(UiHarness.find(grid, "product:StarterBundle")).toBeNil()
		expect(UiHarness.find(panel.frame, "Summary").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "Summary").Text).toBe("1/16 owned")
		expect(UiHarness.find(UiHarness.find(grid, "seat:ufo"), "Tag").Text).toBe("Owned")
	end)
	it("id 0: the price shows and Buy is a disabled Not on sale yet", function()
		local market = fakeMarket()
		local panel = openShop(1920, 1080, shopState(), ctx(Config, { purchase = PurchasePrompt.new(market, PLAYER) }))
		panel.setTab("Clouds")
		panel.select("seat:ufo")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Price").Text).toBe("R$399")
		local buy = UiHarness.find(pane, "Buy")
		expect(buy.Visible).toBe(true)
		expect(buy.Text).toBe("Not on sale yet")
		UiHarness.fire(buy, "Activated")
		expect(#market.calls).toBe(0)
	end)
	it("Buy prompts Roblox with the seat's product id and waits for Roblox", function()
		local config = sellingConfig()
		local market = fakeMarket()
		local adapter = PurchasePrompt.new(market, PLAYER)
		local panel = openShop(1920, 1080, shopState(), ctx(config, { purchase = adapter }), "seat:ufo")
		expect(panel.tab()).toBe("Clouds")
		expect(panel.selected()).toBe("seat:ufo")
		local pane = UiHarness.find(panel.frame, "Pane")
		local buy = UiHarness.find(pane, "Buy")
		expect(buy.Text).toBe("Buy · R$399")
		UiHarness.fire(buy, "Activated")
		expect(#market.calls).toBe(1)
		expect(market.calls[1][1]).toBe("product")
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.products.Seat_ufo.productId)
		expect(buy.Visible).toBe(false)
		expect(UiHarness.find(pane, "Well").Text).toBe("Waiting for Roblox")
		-- the prompt closes without a purchase: Buy is back
		market.PromptProductPurchaseFinished.handlers[1](PLAYER.UserId, 1, false)
		expect(buy.Visible).toBe(true)
	end)
	it("a pass prompts the Game Pass", function()
		local config = sellingConfig()
		local market = fakeMarket()
		local panel = openShop(1920, 1080, shopState(), ctx(config, { purchase = PurchasePrompt.new(market, PLAYER) }))
		panel.setTab("Perks")
		panel.select("pass:Offline2x")
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Buy"), "Activated")
		expect(market.calls[1][1]).toBe("pass")
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.passes.Offline2x.passId)
	end)
	it("once State owns the seat the pane says Bought, and Equip asks EquipPetSeat", function()
		local requests = {}
		local config = sellingConfig()
		local c = ctx(config, {
			purchase = PurchasePrompt.new(fakeMarket(), PLAYER),
			request = function(action: string, _cb: any, ...: any)
				table.insert(requests, { action, ... })
			end,
		})
		local panel = openShop(1920, 1080, shopState(), c, "seat:ufo")
		panel.update(shopState({ owned = { ufo = true } }))
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "BoughtTitle").Visible).toBe(true)
		expect(UiHarness.find(pane, "Buy").Visible).toBe(false)
		local equip = UiHarness.find(pane, "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		expect(requests[1][1]).toBe("EquipPetSeat")
		expect(requests[1][2]).toBe("ufo")
		local worn = shopState({ owned = { ufo = true } })
		worn.petSeat = "ufo"
		panel.update(worn)
		expect(equip.Visible).toBe(false)
		expect(UiHarness.find(pane, "Well").Text).toBe("Equipped")
	end)
	it("an already owned seat is not Bought, only Owned with Equip", function()
		local panel = openShop(1920, 1080, shopState({ owned = { ufo = true } }), ctx(Config), "seat:ufo")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "BoughtTitle").Visible).toBe(false)
		expect(UiHarness.find(pane, "Equip").Visible).toBe(true)
		expect(UiHarness.find(pane, "Price").Visible).toBe(false)
	end)
	it("Boosts: the potion has Details with its odds; restricted, it is gone", function()
		local panel = openShop(1920, 1080, shopState(), ctx(sellingConfig()))
		panel.setTab("Boosts")
		expect(panel.selected()).toBe("product:ServerLuckPotion")
		local pane = UiHarness.find(panel.frame, "Pane")
		local details = UiHarness.find(pane, "Details")
		expect(details.Visible).toBe(true)
		expect(UiHarness.find(pane, "Odds")).toBeNil()
		UiHarness.fire(details, "Activated")
		local odds = UiHarness.find(pane, "Odds")
		expect(odds.Visible).toBe(true)
		expect(UiHarness.find(odds, "Name1").Text).toBe(Config.RARITIES[1].name)
		expect(UiHarness.find(pane, "Buy").Text).toBe("Buy · R$79")
		local restricted = openShop(1920, 1080, shopState({ paidRandomAllowed = false }), ctx(sellingConfig()))
		restricted.setTab("Boosts")
		expect(UiHarness.find(UiHarness.find(restricted.frame, "Grid"), "product:ServerLuckPotion")).toBeNil()
		expect(restricted.selected()).toBe("product:SummonBoss")
	end)
	it("closing the card tells init (CloseShop for a shop-stand open) once", function()
		local hidden = 0
		local panel = openShop(
			1920,
			1080,
			shopState(),
			ctx(Config, {
				exclusiveShopHidden = function()
					hidden += 1
				end,
			})
		)
		panel.setOpen(false)
		panel.setOpen(false)
		expect(hidden).toBe(1)
	end)
	it("phone: the pane is a bottom sheet that opens on a tap and closes with its X", function()
		local panel = openShop(390, 844, shopState(), ctx(Config))
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(pane.Visible).toBe(false)
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "Grid"), "seat:ufo"), "Activated")
		expect(panel.sheetOpen()).toBe(true)
		expect(pane.Visible).toBe(true)
		local x = UiHarness.find(panel.frame, "SheetClose")
		expect(x.Visible).toBe(true)
		UiHarness.fire(x, "Activated")
		expect(pane.Visible).toBe(false)
	end)
	it("phone: opened on a seat (from Skins) the sheet is already up", function()
		local panel = openShop(390, 844, shopState(), ctx(Config), "seat:storm_cloud")
		expect(panel.tab()).toBe("Clouds")
		expect(UiHarness.find(panel.frame, "Pane").Visible).toBe(true)
	end)
	it("buying the Starter bundle lands on its seat, bought", function()
		local panel = openShop(1920, 1080, shopState(), ctx(sellingConfig()))
		expect(panel.selected()).toBe("product:StarterBundle")
		panel.update(shopState({ starterClaimed = true, owned = { leaf = true } }))
		expect(panel.tab()).toBe("Clouds")
		expect(panel.selected()).toBe("seat:leaf")
		expect(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "BoughtTitle").Visible).toBe(true)
	end)

	local viewports: { any } = {}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in viewports do
		it(`{vp.name}: tabs, cards and the pane stay inside the body, texts fit, buttons are touch-sized`, function()
			local screen = Layout.screen(vp.w, vp.h)
			local check = LayoutAssert.fullWindow(vp.name, screen)
			for _, tab in Config.EXCLUSIVE_SHOP.tabs do
				local state = shopState({ offlineDouble = { cash = 1, available = true } })
				local panel, r = openShop(vp.w, vp.h, state, ctx(sellingConfig()))
				panel.setTab(tab)
				local first = ExclusiveShopView.cards(tab, state, Config)[1]
				panel.select(first.key)
				local body = Layout.panelBody(r)
				local tabs = Config.EXCLUSIVE_SHOP.tabs
				local lastTab = UiHarness.find(panel.frame, `Tab_{tabs[#tabs]}`)
				expect(lastTab.Position.X.Offset + lastTab.Size.X.Offset <= body.w).toBe(true)
				check.touch(`{tab}.Tab`, Layout.rect(0, 0, lastTab.Size.X.Offset, lastTab.Size.Y.Offset))
				for _, key in tabs do
					local b = UiHarness.find(panel.frame, `Tab_{key}`)
					expect(b.TextSize >= Layout.MIN_TEXT).toBe(true)
					check.text({
						name = `{tab}.Tab_{key}`,
						text = b.Text,
						size = b.TextSize,
						bold = true,
						w = b.Size.X.Offset - 16,
						h = b.Size.Y.Offset,
					})
				end
				local grid = UiHarness.find(panel.frame, "Grid")
				local pane = UiHarness.find(panel.frame, "Pane")
				expect(grid.Position.Y.Offset >= lastTab.Size.Y.Offset).toBe(true)
				expect(grid.Position.X.Offset + grid.Size.X.Offset <= body.w).toBe(true)
				expect(pane.Position.X.Offset + pane.Size.X.Offset <= body.w + 1e-6).toBe(true)
				expect(pane.Position.Y.Offset + pane.Size.Y.Offset <= body.h + 1e-6).toBe(true)
				for _, card in grid:GetChildren() do
					if card:IsA("GuiObject") then
						expect(card.Position.X.Offset + card.Size.X.Offset <= grid.Size.X.Offset).toBe(true)
						local name = UiHarness.find(card, "CardName")
						check.text({
							name = `{tab}.{card.Name}.name`,
							text = name.Text,
							size = name.TextSize,
							bold = true,
							w = name.Size.X.Offset,
							h = name.Size.Y.Offset,
							wrapped = true,
						})
						local tag = UiHarness.find(card, "Tag")
						check.text({
							name = `{tab}.{card.Name}.tag`,
							text = tag.Text,
							size = tag.TextSize,
							bold = true,
							w = tag.Size.X.Offset - 8,
							h = tag.Size.Y.Offset,
						})
					end
				end
				for _, child in pane:GetChildren() do
					if child:IsA("GuiObject") and child.Visible then
						local w = child.Size.X.Scale * pane.Size.X.Offset + child.Size.X.Offset
						local x = child.Position.X.Scale * pane.Size.X.Offset + child.Position.X.Offset
						local left = x - child.AnchorPoint.X * w
						expect(left >= 0).toBe(true)
						expect(left + w <= pane.Size.X.Offset + 1e-6).toBe(true)
						if child:IsA("TextButton") then
							check.touch(`{tab}.{child.Name}`, Layout.rect(0, 0, w, child.Size.Y.Offset))
							check.text({
								name = `{tab}.{child.Name}`,
								text = child.Text,
								size = child.TextSize,
								bold = true,
								w = w - 16,
								h = child.Size.Y.Offset,
							})
						end
					end
				end
			end
			expect(check.report()).toBe("")
		end)
	end
end)

describe("quick-buy buttons", function()
	local function brewing(shop: any?): any
		local state = if shop then shopState(shop) else { vat = { ids = {} }, slimes = {} }
		state.vat = { ids = {}, tier = 1, startedAt = 900, endsAt = 1000 + 600, seconds = 700 }
		return state
	end
	local function merge(config: any, extra: { [string]: any }?): any
		local c = ctx(config, extra)
		c.Genome = require("../../src/shared/Genome")
		local panel = UiHarness.ui("Panels/Merge").new(UiHarness.root(), c)
		panel.frame.Visible = true
		return panel
	end

	it("Merge: Finish now while brewing, priced by the time left, prompting that product", function()
		local config = sellingConfig()
		local market = fakeMarket()
		local panel = merge(config, { purchase = PurchasePrompt.new(market, PLAYER) })
		panel.update(brewing({}))
		local button = UiHarness.find(panel.frame, "FinishNow")
		expect(button.Visible).toBe(true)
		local key = ExclusiveShopView.finishBrewKey(600, config)
		expect(button.Text).toBe(`Finish now · {Format.robux(config.EXCLUSIVE_SHOP.products[key].robux)}`)
		UiHarness.fire(button, "Activated")
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.products[key].productId)
	end)
	it("Merge: Use credit with a brew credit sends UseCredit", function()
		local sent = {}
		local panel = merge(sellingConfig(), {
			send = function(...: any)
				table.insert(sent, { ... })
			end,
		})
		panel.update(brewing({ credits = { brew = 1, hatch = 0 } }))
		local button = UiHarness.find(panel.frame, "FinishNow")
		expect(button.Text).toBe("Use credit")
		UiHarness.fire(button, "Activated")
		expect(sent[1][1]).toBe("UseCredit")
		expect(sent[1][2]).toBe("brew")
	end)
	it("Merge: nothing with the shop off, and it hides once the brew is not running", function()
		local off = merge(sellingConfig())
		off.update(brewing(nil))
		expect(UiHarness.find(off.frame, "FinishNow")).toBeNil()
		local panel = merge(sellingConfig())
		panel.update(brewing({}))
		panel.update(shopState())
		expect(UiHarness.find(panel.frame, "FinishNow").Visible).toBe(false)
	end)
	it("Merge: id 0 is a disabled Not on sale yet", function()
		local market = fakeMarket()
		local panel = merge(Config, { purchase = PurchasePrompt.new(market, PLAYER) })
		panel.update(brewing({}))
		local button = UiHarness.find(panel.frame, "FinishNow")
		expect(button.Text).toBe("Not on sale yet")
		UiHarness.fire(button, "Activated")
		expect(#market.calls).toBe(0)
	end)

	local function welcomeState(shop: any?): any
		local s: any = {
			welcomeBack = { away = 19800, cash = 12400, grown = 0 },
			daily = { available = false, streak = 1, amount = 100, day = 1 },
			goals = {},
		}
		if shop then
			s.exclusiveShop = shopState(shop).exclusiveShop
		end
		return s
	end
	it("Welcome: Double it while the payout can be doubled, prompting DoubleOffline", function()
		local config = sellingConfig()
		local market = fakeMarket()
		local panel = UiHarness.ui("Panels/Welcome").new(
			UiHarness.root(),
			ctx(config, { purchase = PurchasePrompt.new(market, PLAYER), togglePanel = function() end })
		)
		panel.update(welcomeState({ offlineDouble = { cash = 12400, available = true } }))
		local button = UiHarness.find(panel.frame, "DoubleIt")
		expect(button.Visible).toBe(true)
		expect(button.Text).toBe("Double it · R$49")
		UiHarness.fire(button, "Activated")
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.products.DoubleOffline.productId)
		panel.update(welcomeState({ offlineDouble = { cash = 12400, available = false } }))
		expect(button.Visible).toBe(false)
	end)
	it("Welcome: no button with the shop off", function()
		local panel = UiHarness.ui("Panels/Welcome")
			.new(UiHarness.root(), ctx(sellingConfig(), { togglePanel = function() end }))
		panel.update(welcomeState(nil))
		expect(UiHarness.find(panel.frame, "DoubleIt")).toBeNil()
	end)

	local function itemShop(config: any, extra: { [string]: any }?): any
		local c = table.clone(config)
		local features = table.clone(Config.FEATURES) :: any
		features.Consumables = true
		c.FEATURES = features
		local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx(c, extra))
		panel.setShop("ItemShop")
		return panel
	end
	local function shopFields(shop: any?): any
		local s: any = {
			cash = 1e6,
			consumables = {
				slot = 1,
				restockAt = 1190,
				luckUntil = 0,
				luckMult = 1,
				totemWeather = "Rain",
				items = {
					{
						id = "LuckPotion",
						name = "Luck Potion",
						icon = "x",
						text = "luck",
						price = 2000,
						left = 1,
						max = 4,
					},
				},
			},
			slimes = {},
		}
		if shop then
			s.exclusiveShop = shopState(shop).exclusiveShop
		end
		return s
	end
	it("Item shop: Buy for the server under the Luck Potion; Details opens the shop on its odds", function()
		local config = sellingConfig()
		local market = fakeMarket()
		local opened = {}
		local panel = itemShop(config, {
			purchase = PurchasePrompt.new(market, PLAYER),
			openExclusiveShop = function(key: string, details: boolean?)
				table.insert(opened, { key, details })
			end,
		})
		panel.update(shopFields({}))
		local list = UiHarness.find(panel.frame, "List")
		local row = UiHarness.find(list, "LuckPotionServer")
		local cashRow = UiHarness.find(list, "LuckPotion")
		expect(row.Visible).toBe(true)
		expect(row.LayoutOrder).toBe(cashRow.LayoutOrder)
		expect(row.Position.Y.Offset > cashRow.Position.Y.Offset).toBe(true)
		local buy = UiHarness.find(row, "Buy")
		expect(buy.Text).toBe("Buy for the server · R$79")
		UiHarness.fire(buy, "Activated")
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.products.ServerLuckPotion.productId)
		UiHarness.fire(UiHarness.find(row, "Details"), "Activated")
		expect(opened[1][1]).toBe("product:ServerLuckPotion")
		expect(opened[1][2]).toBe(true)
	end)
	it("Item shop: no server potion where paid random items are restricted or with the shop off", function()
		local panel = itemShop(sellingConfig())
		panel.update(shopFields({ paidRandomAllowed = false }))
		expect(UiHarness.find(panel.frame, "LuckPotionServer")).toBeNil()
		panel.update(shopFields(nil))
		expect(UiHarness.find(panel.frame, "LuckPotionServer")).toBeNil()
		panel.update(shopFields({}))
		expect(UiHarness.find(panel.frame, "LuckPotionServer").Visible).toBe(true)
		panel.update(shopFields({ paidRandomAllowed = false }))
		expect(UiHarness.find(panel.frame, "LuckPotionServer").Visible).toBe(false)
	end)

	it("Skins: an Exclusive seat's well is an Exclusive shop button that opens the shop on that seat", function()
		local PetSeats = require("../../src/shared/PetSeats")
		local PlayerData = require("../../src/shared/PlayerData")
		local PlotSkins = require("../../src/shared/PlotSkins")
		local Fixtures = require("../Fixtures")
		local opened = {}
		local function skins(shop: any?): any
			local panel = UiHarness.ui("Panels/Skins").new(
				UiHarness.root(),
				ctx(Config, {
					PlotSkins = PlotSkins,
					openExclusiveShop = function(key: string)
						table.insert(opened, key)
					end,
				})
			)
			local raw = Layout.panelFor(Layout.screen(1920, 1080), "Skins")
			panel.frame.Size = UDim2.fromOffset(raw.w, raw.h)
			panel.layout(raw)
			local state: any = {
				dex = Fixtures.dex({}),
				plotSkins = PlotSkins.view(PlayerData.new()),
				petSeats = PetSeats.view(PlayerData.new()),
			}
			if shop then
				state.exclusiveShop = shop
			end
			panel.update(state)
			panel.setOpen(true)
			panel.setTab("cloud")
			panel.select("storm_cloud")
			return UiHarness.find(panel.frame, "Pane")
		end
		local pane = skins(shopState().exclusiveShop)
		local button = UiHarness.find(pane, "ExclusiveShop")
		expect(button.Visible).toBe(true)
		expect(UiHarness.find(pane, "Well").Visible).toBe(false)
		UiHarness.fire(button, "Activated")
		expect(opened[1]).toBe("seat:storm_cloud")
		local off = skins(nil)
		expect(UiHarness.find(off, "ExclusiveShop").Visible).toBe(false)
		expect(UiHarness.find(off, "Well").Text).toBe("Exclusive shop")
	end)
end)

describe("Style tab and gifts (ExclusiveShopView)", function()
	local cat = Config.EXCLUSIVE_SHOP
	local function byKey(cards: { any }): { [string]: any }
		local out = {}
		for i, card in cards do
			card.index = i
			out[card.key] = card
		end
		return out
	end
	it("Style lists base skins, lock styles, trails, fanfares, hats, then Bat skins, priced from Config", function()
		local cards = byKey(ExclusiveShopView.cards("Style", shopState(), Config))
		for _, def in cat.trails do
			local card = cards[`trail:{def.id}`]
			expect(card.icon).toBe(`Trail_{def.id}`)
			expect(card.title).toBe(def.name)
			expect(card.tag).toBe(Format.robux(def.robux))
			expect(card.state).toBe("offsale")
		end
		for _, def in cat.batSkins do
			expect(cards[`batSkin:{def.id}`].icon).toBe(`BatSkin_{def.id}`)
		end
		expect(cards["plotSkin:fairground"].index < cards["lockStyle:candy"].index).toBe(true)
		expect(cards["lockStyle:candy"].index < cards["trail:sparkle"].index).toBe(true)
		expect(cards["fanfare:confetti"].index < cards["hat:party"].index).toBe(true)
		expect(cards["hat:party"].index < cards["batSkin:fish"].index).toBe(true)
		expect(ExclusiveShopView.tabOf("hat:party")).toBe("Style")
		expect(ExclusiveShopView.tabOf("plotSkin:space")).toBe("Style")
		expect(ExclusiveShopView.tabOf("trail:hearts")).toBe("Style")
		expect(ExclusiveShopView.tabOf("batSkin:fish")).toBe("Style")
	end)
	it('owned trails Equip with EquipTrail; the worn one is Equipped with Unequip ("")', function()
		local state = shopState({ trails = { hearts = true, sparkle = true }, trail = "hearts" })
		local owned = ExclusiveShopView.detail("trail:sparkle", state, Config) :: ExclusiveShopView.Detail
		expect(owned.state).toBe("owned")
		expect(owned.action.kind).toBe("equip")
		expect((owned.action.equip :: any).request).toBe("EquipTrail")
		expect((owned.action.equip :: any).arg).toBe("sparkle")
		expect(owned.unequip).toBeNil()
		local worn = ExclusiveShopView.detail("trail:hearts", state, Config) :: ExclusiveShopView.Detail
		expect(worn.state).toBe("equipped")
		expect(worn.action.text).toBe("Equipped")
		expect((worn.unequip :: any).request).toBe("EquipTrail")
		expect((worn.unequip :: any).arg).toBe("")
		expect(worn.unequipText).toBe("Unequip")
	end)
	it("Bat skins: EquipBatSkin, and the worn one offers Use default Bat", function()
		local state = shopState({ batSkins = { golden = true }, batSkin = "golden" })
		local worn = ExclusiveShopView.detail("batSkin:golden", state, Config) :: ExclusiveShopView.Detail
		expect((worn.unequip :: any).request).toBe("EquipBatSkin")
		expect((worn.unequip :: any).arg).toBe("")
		expect(worn.unequipText).toBe("Use default Bat")
		local card = byKey(ExclusiveShopView.cards("Style", state, Config))["batSkin:golden"]
		expect(card.tag).toBe("Equipped")
	end)
	it("a Gift on every cosmetic, never on passes, boosts, the bundle or info cards", function()
		local config = sellingConfig()
		local state = shopState()
		for _, key in { "seat:ufo", "trail:rainbow", "batSkin:fish" } do
			local d = ExclusiveShopView.detail(key, state, config) :: ExclusiveShopView.Detail
			expect(`{key}: {d.gift ~= nil}`).toBe(`{key}: true`)
		end
		for _, key in { "pass:Income2x", "product:ServerLuckPotion", "product:StarterBundle", "info:HatchNow" } do
			local d = ExclusiveShopView.detail(key, state, config) :: ExclusiveShopView.Detail
			expect(`{key}: {d.gift == nil}`).toBe(`{key}: true`)
		end
	end)
	it("Gift buys Gift_<key> at the item's price; id 0 is a disabled Gift not on sale", function()
		local config = sellingConfig()
		local gift = (ExclusiveShopView.detail("trail:rainbow", shopState(), config) :: any).gift
		expect(gift.mode).toBe("buy")
		expect(gift.itemKey).toBe("Trail_rainbow")
		expect(gift.text).toBe(`Gift · {Format.robux(cat.products.Trail_rainbow.robux)}`)
		expect(gift.purchase.id).toBe(config.EXCLUSIVE_SHOP.products.Gift_Trail_rainbow.productId)
		local off = (ExclusiveShopView.detail("seat:ufo", shopState(), Config) :: any).gift
		expect(off.mode).toBe("offsale")
		expect(off.text).toBe("Gift not on sale")
	end)
	it("an unsent gift credit turns that item's Gift into Send gift", function()
		local state = shopState({ giftCredits = { "Seat_ufo" } })
		local gift = (ExclusiveShopView.detail("seat:ufo", state, Config) :: any).gift
		expect(gift.mode).toBe("send")
		expect(gift.text).toBe("Send gift")
		expect((ExclusiveShopView.detail("seat:leaf", state, Config) :: any).gift.mode).toBe("offsale")
	end)
	it("giftTargets: never yourself, friends first, then by name", function()
		local list = ExclusiveShopView.giftTargets({
			{ userId = 3, name = "zed", friend = false },
			{ userId = PLAYER.UserId, name = "Me", friend = false },
			{ userId = 4, name = "Bo", friend = true },
			{ userId = 5, name = "amy", friend = false },
		}, PLAYER.UserId)
		local ids = {}
		for _, t in list do
			table.insert(ids, t.userId)
		end
		expect(table.concat(ids, ",")).toBe("4,5,3")
	end)
end)

describe("Style tab and gifts (panel)", function()
	local function requests(): ({ any }, (string, any, ...any) -> ())
		local out = {}
		return out, function(action: string, _cb: any, ...: any)
			table.insert(out, { action, ... })
		end
	end
	local PLAYERS = {
		{ userId = PLAYER.UserId, name = "Me", friend = false },
		{ userId = 31, name = "Zoe", friend = false },
		{ userId = 32, name = "Ann", friend = true },
	}
	-- ctx with a fake market, a recorded ask (answering `answer`) and the server's players.
	local function giftCtx(config: any, answer: any?, extra: { [string]: any }?): (any, any, { any })
		local market = fakeMarket()
		local asks = {}
		local c = ctx(config, {
			purchase = PurchasePrompt.new(market, PLAYER),
			giftPlayers = function()
				return PLAYERS
			end,
			ask = function(action: string, done: (any) -> (), ...: any)
				table.insert(asks, { action, ... })
				done(answer or { ok = true })
			end,
		})
		for k, v in extra or {} do
			c[k] = v
		end
		return c, market, asks
	end

	it("the Style tab shows trail and Bat skin cards with their drawn icons", function()
		local panel = openShop(1920, 1080, shopState(), ctx(Config))
		panel.setTab("Style")
		local grid = UiHarness.find(panel.frame, "Grid")
		local trail = UiHarness.find(grid, "trail:sparkle")
		expect(trail ~= nil).toBe(true)
		expect(UiHarness.find(grid, "batSkin:golden") ~= nil).toBe(true)
		expect(UiHarness.find(trail, "CardIcon"):GetAttribute("ItemId")).toBe("Trail_sparkle")
		expect(panel.selected()).toBe("plotSkin:fairground") -- the first Style card
		expect(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Buy").Text).toBe("Not on sale yet")
	end)
	it("a base card prompts Base_<id>; once owned, Equip asks EquipPlotBase", function()
		local config = sellingConfig()
		local market = fakeMarket()
		local sent, request = requests()
		local c = ctx(config, { purchase = PurchasePrompt.new(market, PLAYER), request = request })
		local panel = openShop(1920, 1080, shopState(), c, "plotBase:carousel")
		expect(panel.tab()).toBe("Style")
		local grid = UiHarness.find(panel.frame, "Grid")
		local card = UiHarness.find(grid, "plotBase:carousel")
		expect(UiHarness.find(card, "CardIcon"):GetAttribute("ItemId")).toBe("PlotBase_carousel")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Buy").Text).toBe("Buy · R$599")
		UiHarness.fire(UiHarness.find(pane, "Buy"), "Activated")
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.products.Base_carousel.productId)
		panel.update(shopState({ styles = { plotBase = { carousel = true } } }))
		local equip = UiHarness.find(pane, "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		expect(sent[1][1]).toBe("EquipPlotBase")
		expect(sent[1][2]).toBe("carousel")
	end)
	it("Buy on a trail prompts Trail_<id>; once owned, Equip asks EquipTrail and the worn one Unequips", function()
		local config = sellingConfig()
		local market = fakeMarket()
		local sent, request = requests()
		local c = ctx(config, { purchase = PurchasePrompt.new(market, PLAYER), request = request })
		local panel = openShop(1920, 1080, shopState(), c, "trail:starfall")
		expect(panel.tab()).toBe("Style")
		local pane = UiHarness.find(panel.frame, "Pane")
		UiHarness.fire(UiHarness.find(pane, "Buy"), "Activated")
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.products.Trail_starfall.productId)
		panel.update(shopState({ trails = { starfall = true } }))
		expect(UiHarness.find(pane, "BoughtTitle").Visible).toBe(true)
		local equip = UiHarness.find(pane, "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		expect(sent[1][1]).toBe("EquipTrail")
		expect(sent[1][2]).toBe("starfall")
		panel.update(shopState({ trails = { starfall = true }, trail = "starfall" }))
		expect(equip.Visible).toBe(false)
		expect(UiHarness.find(pane, "Well").Text).toBe("Equipped")
		local unequip = UiHarness.find(pane, "Unequip")
		expect(unequip.Visible).toBe(true)
		expect(unequip.Text).toBe("Unequip")
		UiHarness.fire(unequip, "Activated")
		expect(sent[2][1]).toBe("EquipTrail")
		expect(sent[2][2]).toBe("")
	end)
	it('the worn Bat skin offers Use default Bat (EquipBatSkin "")', function()
		local sent, request = requests()
		local state = shopState({ batSkins = { fish = true }, batSkin = "fish" })
		local panel = openShop(1920, 1080, state, ctx(Config, { request = request }), "batSkin:fish")
		local unequip = UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Unequip")
		expect(unequip.Text).toBe("Use default Bat")
		UiHarness.fire(unequip, "Activated")
		expect(sent[1][1]).toBe("EquipBatSkin")
		expect(sent[1][2]).toBe("")
	end)
	it("without the server's EquipTrail an owned trail is an Owned well, never a dead button", function()
		local actions = table.clone(Remotes.ACTIONS) :: any
		actions.EquipTrail = nil
		local c = ctx(Config, { actions = actions })
		local panel = openShop(1920, 1080, shopState({ trails = { hearts = true } }), c, "trail:hearts")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Equip").Visible).toBe(false)
		expect(UiHarness.find(pane, "Well").Text).toBe("Owned")
	end)
	it("the Gift button shows on cosmetics only, never on a pass or a boost", function()
		local panel = openShop(1920, 1080, shopState(), ctx(sellingConfig()), "seat:ufo")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Gift").Visible).toBe(true)
		panel.setTab("Perks")
		panel.select("pass:Income2x")
		expect(UiHarness.find(pane, "Gift").Visible).toBe(false)
		panel.setTab("Boosts")
		panel.select("product:ServerLuckPotion")
		expect(UiHarness.find(pane, "Gift").Visible).toBe(false)
		panel.setTab("Style")
		panel.select("batSkin:lollipop")
		expect(UiHarness.find(pane, "Gift").Visible).toBe(true)
	end)
	it("Gift opens the player picker: friends first, never you; a pick aims then prompts Gift_<key>", function()
		local config = sellingConfig()
		local c, market, asks = giftCtx(config)
		local panel = openShop(1920, 1080, shopState(), c, "seat:ufo")
		local pane = UiHarness.find(panel.frame, "Pane")
		local gift = UiHarness.find(pane, "Gift")
		expect(gift.Text).toBe(`Gift · {Format.robux(Config.EXCLUSIVE_SHOP.products.Seat_ufo.robux)}`)
		UiHarness.fire(gift, "Activated")
		local picker = UiHarness.find(panel.frame, "GiftPicker")
		expect(picker.Visible).toBe(true)
		expect(pane.Visible).toBe(false)
		local list = UiHarness.find(picker, "GiftList")
		expect(UiHarness.find(list, `Player_{PLAYER.UserId}`)).toBeNil()
		local ann, zoe = UiHarness.find(list, "Player_32"), UiHarness.find(list, "Player_31")
		expect(ann.Position.Y.Offset < zoe.Position.Y.Offset).toBe(true)
		expect(UiHarness.find(ann, "FriendTag").Visible).toBe(true)
		expect(UiHarness.find(zoe, "FriendTag").Visible).toBe(false)
		UiHarness.fire(zoe, "Activated")
		expect(asks[1][1]).toBe("AimGift")
		expect(asks[1][2]).toBe("Seat_ufo")
		expect(asks[1][3]).toBe(31)
		expect(#market.calls).toBe(1)
		expect(market.calls[1][3]).toBe(config.EXCLUSIVE_SHOP.products.Gift_Seat_ufo.productId)
		-- back on the pane, waiting for Roblox, until the prompt closes
		expect(picker.Visible).toBe(false)
		expect(pane.Visible).toBe(true)
		expect(gift.Text).toBe("Waiting for Roblox")
		market.PromptProductPurchaseFinished.handlers[1](PLAYER.UserId, 1, false)
		expect(gift.Text).toBe(`Gift · {Format.robux(Config.EXCLUSIVE_SHOP.products.Seat_ufo.robux)}`)
	end)
	it("a refused pick opens no purchase: that player greys out and the server's reason shows", function()
		local c, market, asks = giftCtx(sellingConfig(), { ok = false, message = "Ann already has the UFO." })
		local panel = openShop(1920, 1080, shopState(), c, "seat:ufo")
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Gift"), "Activated")
		local picker = UiHarness.find(panel.frame, "GiftPicker")
		local ann = UiHarness.find(UiHarness.find(picker, "GiftList"), "Player_32")
		UiHarness.fire(ann, "Activated")
		expect(#asks).toBe(1)
		expect(#market.calls).toBe(0)
		expect(picker.Visible).toBe(true)
		expect(UiHarness.find(picker, "GiftMessage").Text).toBe("Ann already has the UFO.")
		expect(ann:GetAttribute("Refused")).toBe(true)
		UiHarness.fire(ann, "Activated") -- greyed: no second ask
		expect(#asks).toBe(1)
		UiHarness.fire(UiHarness.find(picker, "GiftBack"), "Activated")
		expect(picker.Visible).toBe(false)
	end)
	it("an unsent gift credit: Send gift picks a player and sends SendGift, no purchase", function()
		local c, market, asks = giftCtx(Config)
		local panel = openShop(1920, 1080, shopState({ giftCredits = { "Trail_hearts" } }), c, "trail:hearts")
		local gift = UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Gift")
		expect(gift.Text).toBe("Send gift")
		UiHarness.fire(gift, "Activated")
		local picker = UiHarness.find(panel.frame, "GiftPicker")
		expect(UiHarness.find(picker, "GiftTitle").Text).toBe("Send gift: Hearts")
		UiHarness.fire(UiHarness.find(UiHarness.find(picker, "GiftList"), "Player_32"), "Activated")
		expect(asks[1][1]).toBe("SendGift")
		expect(asks[1][2]).toBe("Trail_hearts")
		expect(asks[1][3]).toBe(32)
		expect(#market.calls).toBe(0)
		expect(picker.Visible).toBe(false)
	end)
	it("id 0: a disabled Gift not on sale that opens nothing", function()
		local c, _, asks = giftCtx(Config)
		local panel = openShop(1920, 1080, shopState(), c, "seat:ufo")
		local gift = UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Gift")
		expect(gift.Text).toBe("Gift not on sale")
		UiHarness.fire(gift, "Activated")
		expect(UiHarness.find(panel.frame, "GiftPicker").Visible).toBe(false)
		expect(#asks).toBe(0)
	end)
	it("without the server's AimGift there is no Gift button", function()
		local actions = table.clone(Remotes.ACTIONS) :: any
		actions.AimGift = nil
		local panel = openShop(1920, 1080, shopState(), ctx(sellingConfig(), { actions = actions }), "seat:ufo")
		expect(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Gift").Visible).toBe(false)
	end)
	it("alone on the server the picker says so", function()
		local c = giftCtx(sellingConfig(), nil, {
			giftPlayers = function()
				return { { userId = PLAYER.UserId, name = "Me", friend = false } }
			end,
		})
		local panel = openShop(1920, 1080, shopState(), c, "seat:ufo")
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Gift"), "Activated")
		local empty = UiHarness.find(UiHarness.find(panel.frame, "GiftPicker"), "GiftEmpty")
		expect(empty.Visible).toBe(true)
		expect(empty.Text).toBe(ExclusiveShopView.GIFT_EMPTY)
	end)

	local viewports: { any } = {}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in viewports do
		it(`{vp.name}: the Style pane with Unequip and Gift, and the gift picker, fit and are touch-sized`, function()
			local check = LayoutAssert.fullWindow(vp.name, Layout.screen(vp.w, vp.h))
			local many = table.clone(PLAYERS)
			for i = 1, 8 do
				table.insert(many, { userId = 100 + i, name = `Player with a long name {i}`, friend = i % 3 == 0 })
			end
			local c = giftCtx(sellingConfig(), nil, {
				giftPlayers = function()
					return many
				end,
			})
			local state = shopState({ batSkins = { foam_finger = true }, batSkin = "foam_finger" })
			local panel = openShop(vp.w, vp.h, state, c, "batSkin:foam_finger")
			local function fits(frame: any, label: string)
				for _, child in UiHarness.descendants(frame) do
					if child:IsA("GuiObject") and child.Visible and child.Parent == frame then
						local w = child.Size.X.Scale * frame.Size.X.Offset + child.Size.X.Offset
						local x = child.Position.X.Scale * frame.Size.X.Offset + child.Position.X.Offset
						local left = x - child.AnchorPoint.X * w
						expect(`{label}.{child.Name} left {left >= 0}`).toBe(`{label}.{child.Name} left true`)
						expect(`{label}.{child.Name} right {left + w <= frame.Size.X.Offset + 1e-6}`).toBe(
							`{label}.{child.Name} right true`
						)
						if child:IsA("TextButton") then
							check.touch(`{label}.{child.Name}`, Layout.rect(0, 0, w, child.Size.Y.Offset))
							check.text({
								name = `{label}.{child.Name}`,
								text = child.Text,
								size = child.TextSize,
								bold = true,
								w = w - 16,
								h = child.Size.Y.Offset,
							})
						end
					end
				end
			end
			local pane = UiHarness.find(panel.frame, "Pane")
			expect(UiHarness.find(pane, "Unequip").Visible).toBe(true)
			expect(UiHarness.find(pane, "Gift").Visible).toBe(true)
			fits(pane, "pane")
			UiHarness.fire(UiHarness.find(pane, "Gift"), "Activated")
			local picker = UiHarness.find(panel.frame, "GiftPicker")
			expect(picker.Visible).toBe(true)
			fits(picker, "picker")
			local list = UiHarness.find(picker, "GiftList")
			for _, row in list:GetChildren() do
				expect(row.Size.Y.Offset >= Layout.MIN_TOUCH_DESIGN).toBe(true)
				expect(row.Position.X.Offset + row.Size.X.Offset <= list.Size.X.Offset + 1e-6).toBe(true)
			end
			local body = Layout.panelBody(Layout.rect(0, 0, panel.frame.Size.X.Offset, panel.frame.Size.Y.Offset))
			expect(picker.Position.Y.Offset + picker.Size.Y.Offset <= body.h + 1e-6).toBe(true)
			expect(check.report()).toBe("")
		end)
	end
end)

describe("Exclusive shop perks and boosts (ExclusiveShopView)", function()
	it("an owned VIP gives the server a potion once a day; used, restricted or not owned it is a well", function()
		local config = sellingConfig()
		local ready = shopState({ passes = { VIP = true }, vipPotion = true })
		local d = ExclusiveShopView.detail("pass:VIP", ready, config) :: any
		expect(d.action.kind).toBe("equip")
		expect(d.action.text).toBe(ExclusiveShopView.VIP_POTION)
		expect(d.action.equip.request).toBe("ClaimPerk")
		expect(d.action.equip.arg).toBe("vipPotion")
		local used = ExclusiveShopView.detail(
			"pass:VIP",
			shopState({ passes = { VIP = true }, vipPotion = false }),
			config
		) :: any
		expect(used.action.kind).toBe("well")
		expect(used.action.text).toBe(ExclusiveShopView.VIP_POTION_USED)
		local restricted = ExclusiveShopView.detail(
			"pass:VIP",
			shopState({ passes = { VIP = true }, vipPotion = true, paidRandomAllowed = false }),
			config
		) :: any
		expect(restricted.action.kind).toBe("well")
		local unowned = ExclusiveShopView.detail("pass:VIP", shopState(), config) :: any
		expect(unowned.action.kind).toBe("buy")
		expect(unowned.action.purchase.kind).toBe("pass")
	end)
	it("Lucky Charm+ shows this player's chance with and without it", function()
		local state = shopState({ luck = { base = 0.06, bonus = 0.05 } })
		local d = ExclusiveShopView.detail("pass:LuckyCharmPlus", state, sellingConfig()) :: any
		expect(d.odds[1].base).toBe("6%")
		expect(d.odds[1].boosted).toBe("11%")
		expect(d.effect[1]).toBe("Your chance now: 6%")
		expect(d.effect[2]).toBe("With Lucky Charm+: 11%")
	end)
	it("the Slime Club sells as a subscription with a monthly price; a member sees Member", function()
		local config = sellingConfig()
		local card = ExclusiveShopView.detail("sub:SlimeClub", shopState(), config) :: any
		expect(card.priceText).toBe(`{Format.robux(Config.EXCLUSIVE_SHOP.subscriptions.SlimeClub.robux)}/mo`)
		expect(card.action.kind).toBe("buy")
		expect(card.action.purchase.kind).toBe("subscription")
		expect(card.action.purchase.subscriptionId).toBe("EXP-SlimeClub")
		local off = ExclusiveShopView.detail("sub:SlimeClub", shopState(), Config) :: any
		expect(off.action.kind).toBe("offsale")
		local member = shopState({ subscriptions = { SlimeClub = true } })
		expect((ExclusiveShopView.detail("sub:SlimeClub", member, config) :: any).action.text).toBe(
			ExclusiveShopView.SUBSCRIBED
		)
		expect(ExclusiveShopView.tabOf("sub:SlimeClub")).toBe("Perks")
	end)
	it("a server boost kept as a credit is used instead of bought", function()
		local config = sellingConfig()
		local credits = { brew = 0, hatch = 0, rain = 1, boss = 0, totem = 0, snack = 0 }
		local d = ExclusiveShopView.detail("product:SlimeRain", shopState({ credits = credits }), config) :: any
		expect(d.action.kind).toBe("equip")
		expect(d.action.text).toBe(ExclusiveShopView.USE_CREDIT)
		expect(d.action.equip.request).toBe("UseCredit")
		expect(d.action.equip.arg).toBe("rain")
		local boss = ExclusiveShopView.detail("product:SummonBoss", shopState({ credits = credits }), config) :: any
		expect(boss.action.kind).toBe("buy")
	end)
	it("Keep my streak shows only while the streak broke", function()
		local config = sellingConfig()
		expect(ExclusiveShopView.streakQuickBuy(shopState(), config)).toBeNil()
		local q = ExclusiveShopView.streakQuickBuy(shopState({ streakKeepable = true }), config) :: any
		expect(q.mode).toBe("buy")
		expect(q.text).toBe(`Keep my streak · {Format.robux(Config.EXCLUSIVE_SHOP.products.KeepStreak.robux)}`)
	end)
	it("a Growth snack is offered on a growing slime, never on an egg or a grown one", function()
		local config = sellingConfig()
		local state = shopState()
		state.slimes = {
			{ slime = { id = "a", growth = 0.2 } },
			{ slime = { id = "b", growth = 1 } },
			{ slime = { id = "c", egg = { kind = "speckled" } } },
		}
		expect((ExclusiveShopView.snackQuickBuy(state, "a", config) :: any).mode).toBe("buy")
		expect(ExclusiveShopView.snackQuickBuy(state, "b", config)).toBeNil()
		expect(ExclusiveShopView.snackQuickBuy(state, "c", config)).toBeNil()
		state.exclusiveShop.credits = { brew = 0, hatch = 0, rain = 0, boss = 0, totem = 0, snack = 2 }
		expect((ExclusiveShopView.snackQuickBuy(state, "a", config, true) :: any).mode).toBe("credit")
	end)
	it("no Growth snack is offered on a server where slimes don't grow", function()
		local config = sellingConfig()
		config.FEATURES = table.clone(Config.FEATURES)
		config.FEATURES.GrowingSlimes = false
		local state = shopState()
		state.slimes = { { slime = { id = "a", growth = 0.2 } } }
		expect(ExclusiveShopView.snackQuickBuy(state, "a", config)).toBeNil()
	end)
end)

describe("PurchasePrompt subscriptions", function()
	it("prompts a subscription by its EXP id and never one without an id", function()
		local calls = {}
		local market: any = {
			PromptProductPurchaseFinished = { Connect = function() end },
			PromptGamePassPurchaseFinished = { Connect = function() end },
			PromptSubscriptionPurchase = function(_self: any, _player: any, id: string)
				table.insert(calls, id)
			end,
		}
		local adapter = PurchasePrompt.new(market, { UserId = 1 })
		expect(adapter.prompt({ kind = "subscription", id = 0, subscriptionId = "" })).toBe(false)
		expect(adapter.prompt({ kind = "subscription", id = 0, subscriptionId = "EXP-1" })).toBe(true)
		expect(table.concat(calls, ",")).toBe("EXP-1")
	end)
end)

describe("Exclusive styles, seasons and bundles (ExclusiveShopView)", function()
	it("seasonal items show only in their season; owned ones always", function()
		local out = keysOf(ExclusiveShopView.cards("Style", shopState(), Config))
		expect(table.find(out, "hat:witch")).toBeNil()
		expect(table.find(out, "plotSkin:haunted")).toBeNil()
		local open = keysOf(ExclusiveShopView.cards("Style", shopState({ seasons = { halloween = true } }), Config))
		expect(table.find(open, "hat:witch") ~= nil).toBe(true)
		expect(table.find(open, "plotSkin:haunted") ~= nil).toBe(true)
		local owner = shopState({ styles = { hat = { witch = true } } })
		expect(table.find(keysOf(ExclusiveShopView.cards("Style", owner, Config)), "hat:witch") ~= nil).toBe(true)
	end)
	it('an owned hat equips with EquipStyle(kind, id) and the worn one takes off with ""', function()
		local state = shopState({ styles = { hat = { party = true, bow = true } }, worn = { hat = "party" } })
		local owned = ExclusiveShopView.detail("hat:bow", state, Config) :: any
		expect(owned.action.equip.request).toBe("EquipStyle")
		expect(table.concat(owned.action.equip.args, ",")).toBe("hat,bow")
		local worn = ExclusiveShopView.detail("hat:party", state, Config) :: any
		expect(worn.state).toBe("equipped")
		expect(table.concat(worn.unequip.args, ",")).toBe("hat,")
		expect(worn.gift ~= nil).toBe(true)
	end)
	it("an owned base skin equips with EquipPlotSkin and shows Equipped from State.plotSkins", function()
		local state = shopState({ styles = { plotSkin = { space = true } } })
		local owned = ExclusiveShopView.detail("plotSkin:space", state, Config) :: any
		expect(owned.action.equip.request).toBe("EquipPlotSkin")
		expect(owned.action.equip.arg).toBe("space")
		state.plotSkins = { { id = "space", equipped = true } }
		expect((ExclusiveShopView.detail("plotSkin:space", state, Config) :: any).state).toBe("equipped")
	end)
	it("the Exclusive bases are Style cards after the base skins: name, price, Buy and Gift", function()
		local cards = ExclusiveShopView.cards("Style", shopState(), Config)
		local index: { [string]: number } = {}
		for i, card in cards do
			index[card.key] = i
		end
		for _, base in Config.PLOT_BASES do
			local key = `plotBase:{base.id}`
			if base.exclusive then
				local card = cards[index[key]]
				expect(card.title).toBe(base.name)
				expect(card.icon).toBe(`PlotBase_{base.id}`)
				expect(card.tag).toBe(Format.robux(base.robux :: number))
				expect(card.state).toBe("offsale")
				expect(index[key] > index["plotSkin:fairground"]).toBe(true)
				expect(index[key] < index["lockStyle:candy"]).toBe(true)
				expect(ExclusiveShopView.tabOf(key)).toBe("Style")
				expect(ExclusiveShopView.itemKeyOf(key)).toBe(`Base_{base.id}`)
			else
				expect(index[key]).toBeNil()
			end
		end
		local selling = sellingConfig()
		local detail = ExclusiveShopView.detail("plotBase:rocket", shopState(), selling) :: any
		expect(detail.text).toBe(ExclusiveShopView.BASE_TEXT)
		expect(detail.action.kind).toBe("buy")
		expect(detail.action.text).toBe("Buy · R$499")
		expect(detail.action.purchase.id).toBe(selling.EXCLUSIVE_SHOP.products.Base_rocket.productId)
		expect(detail.gift.mode).toBe("buy")
		expect(detail.gift.text).toBe("Gift · R$499")
		expect(detail.gift.purchase.id).toBe(selling.EXCLUSIVE_SHOP.products.Gift_Base_rocket.productId)
	end)
	it("an owned base equips with EquipPlotBase and shows Equipped from State.plotBases", function()
		local state = shopState({ styles = { plotBase = { rocket = true } } })
		local owned = ExclusiveShopView.detail("plotBase:rocket", state, Config) :: any
		expect(owned.state).toBe("owned")
		expect(owned.action.equip.request).toBe("EquipPlotBase")
		expect(owned.action.equip.arg).toBe("rocket")
		state.plotBases = { { id = "rocket", equipped = true } }
		local worn = ExclusiveShopView.detail("plotBase:rocket", state, Config) :: any
		expect(worn.state).toBe("equipped")
		expect(worn.unequip).toBeNil() -- a base is swapped in Skins, never taken off
	end)
	it("a bundle shows Owned once everything in it is owned", function()
		local all = shopState({
			owned = { magic_carpet = true },
			styles = { plotSkin = { fairground = true }, fanfare = { confetti = true } },
		})
		expect(ExclusiveShopView.packOwned(all.exclusiveShop, Config, "BoutiqueBundle")).toBe(true)
		local some = shopState({ owned = { magic_carpet = true } })
		expect(ExclusiveShopView.packOwned(some.exclusiveShop, Config, "BoutiqueBundle")).toBe(false)
	end)
end)

describe("Slime Club price from Roblox", function()
	it("the card shows Roblox's own price for this player when the client knows it", function()
		local state = shopState({ displayPrices = { SlimeClub = "R$ 79" } })
		local card = ExclusiveShopView.detail("sub:SlimeClub", state, Config) :: any
		expect(card.priceText).toBe("R$ 79/mo")
		local plain = ExclusiveShopView.detail("sub:SlimeClub", shopState(), Config) :: any
		expect(plain.priceText).toBe(`{Format.robux(Config.EXCLUSIVE_SHOP.subscriptions.SlimeClub.robux)}/mo`)
	end)
	it("PurchasePrompt asks Roblox once per subscription and remembers the answer", function()
		local asked = 0
		local market: any = {
			PromptProductPurchaseFinished = { Connect = function() end },
			PromptGamePassPurchaseFinished = { Connect = function() end },
			GetSubscriptionProductInfoAsync = function(_self: any, id: string): any
				asked += 1
				return { DisplayPrice = `R$ 99 {id}` }
			end,
		}
		local adapter = PurchasePrompt.new(market, { UserId = 1 })
		local got = {}
		adapter.subscriptionPrice("EXP-1", function(text)
			table.insert(got, text)
		end)
		adapter.subscriptionPrice("EXP-1", function(text)
			table.insert(got, text)
		end)
		adapter.subscriptionPrice("", function(text)
			table.insert(got, text or "none")
		end)
		expect(asked).toBe(1)
		expect(got[1]).toBe("R$ 99 EXP-1")
		expect(got[2]).toBe("R$ 99 EXP-1")
		expect(got[3]).toBe("none")
	end)
end)
