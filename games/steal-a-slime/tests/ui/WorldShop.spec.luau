--!strict
-- World shop client (FEATURES.WorldShops, CONTRACT.md §27): WorldShopLogic rows / deny texts / open-close
-- controller, the Panels/WorldShop card, the init.client wiring and the full-window layout at every gate size.
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local ItemIcons = require("../../src/ui/ItemIcons")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local MenuClose = require("../../src/ui/MenuClose")
local MenuState = require("../../src/ui/MenuState")
local Remotes = require("../../src/shared/Remotes")
local ShopGuard = require("../../src/server/ShopGuard")
local Shops = require("../../src/shared/Shops")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local WorldShopLogic = require("../../src/ui/WorldShopLogic")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ACTIONS = Remotes.ACTIONS

local function features(overrides: { [string]: boolean }?): any
	local out: any = table.clone(Config.FEATURES)
	for _, flag in { "MysteryEgg", "Consumables", "PvP", "RainMagnet" } do
		out[flag] = true
	end
	for flag, value in overrides or {} do
		out[flag] = value
	end
	return out
end

local function upgradeEntry(id: string, fields: { [string]: any }?): any
	local def: any
	for _, u in Config.UPGRADES do
		if u.id == id then
			def = u
		end
	end
	local entry: any = {
		id = id,
		name = def.name,
		text = def.text,
		level = 1,
		maxLevel = def.maxLevel,
		price = 100,
		requires = def.requires,
		unlocked = true,
	}
	for k, v in fields or {} do
		entry[k] = v
	end
	return entry
end

local function baseState(extra: { [string]: any }?): any
	local upgrades = {}
	for _, u in Config.UPGRADES do
		table.insert(upgrades, upgradeEntry(u.id))
	end
	local state: any = {
		cash = 1e6,
		serverTime = 1000,
		lockCost = 200,
		lockDuration = 70,
		shop = {
			LockUpgrade = { price = 750, level = 2, maxLevel = 5 },
			SpeedCoil = { price = 4000, owned = false },
			MysteryEgg = { price = 900 },
		},
		upgrades = upgrades,
		consumables = {
			slot = 1,
			restockAt = 1190,
			luckUntil = 0,
			luckMult = 1,
			totemWeather = "Rain",
			items = {
				{
					id = "MutationSpray",
					name = "Mutation Spray",
					icon = "🧪",
					text = "spray",
					price = 3000,
					left = 2,
					max = 3,
				},
				{
					id = "LuckPotion",
					name = "Luck Potion",
					icon = "🍀",
					text = "luck",
					price = 2000,
					left = 0,
					max = 4,
				},
			},
		},
		pvp = { rank = 3, owned = { KnockGlove1 = true }, best = {}, cooldowns = {} },
		slimes = {
			{ slime = { id = "s1", tier = 2 }, income = 1, sellPrice = 1, appraiseCost = 1 },
			{ slime = { id = "s2", tier = 5 }, income = 1, sellPrice = 1, appraiseCost = 1 },
		},
		favoriteId = nil,
	}
	for k, v in extra or {} do
		state[k] = v
	end
	return state
end

local function find(rows: { WorldShopLogic.Row }, id: string): WorldShopLogic.Row
	for _, r in rows do
		if r.id == id then
			return r
		end
	end
	error(`no row {id}`)
end

local function ids(rows: { WorldShopLogic.Row }): { string }
	local out = {}
	for _, r in rows do
		table.insert(out, r.id)
	end
	return out
end

describe("WorldShopLogic.rows", function()
	it("lists exactly Shops.items of each shop, in order, for a full State", function()
		for _, shopId in Shops.ORDER do
			local want = {}
			for _, item in Shops.items(shopId, features()) do
				table.insert(want, item.id)
			end
			local rows = WorldShopLogic.rows(shopId, baseState(), ACTIONS, features(), Config)
			expect(table.concat(ids(rows), ",")).toBe(table.concat(want, ","))
		end
	end)

	it("filters rows by feature flags", function()
		local off = features({ MysteryEgg = false, Consumables = false, PvP = false, RainMagnet = false })
		local itemRows = ids(WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, off, Config))
		expect(table.concat(itemRows, ",")).toBe("Lock")
		local upgradeRows = ids(WorldShopLogic.rows("UpgradeShop", baseState(), ACTIONS, off, Config))
		expect(table.find(upgradeRows, "RainMagnet")).toBeNil()
		expect(table.find(upgradeRows, "Income")).toBeTruthy()
		local noEgg =
			ids(WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features({ MysteryEgg = false }), Config))
		expect(table.find(noEgg, "MysteryEgg")).toBeNil()
		expect(table.find(noEgg, "MutationSpray")).toBeTruthy()
		expect(#WorldShopLogic.rows("Nope", baseState(), ACTIONS, features(), Config)).toBe(0)
	end)

	it("every row has a registered icon", function()
		local registry = ItemIcons.build(Config)
		for _, shopId in Shops.ORDER do
			for _, r in WorldShopLogic.rows(shopId, baseState(), ACTIONS, features(), Config) do
				expect(`{r.icon}: {registry.byId[r.icon] ~= nil}`).toBe(`{r.icon}: true`)
			end
		end
		for _, tool in Config.PVP_TOOLS do
			expect(`Pvp_{tool.id}: {registry.byId[`Pvp_{tool.id}`] ~= nil}`).toBe(`Pvp_{tool.id}: true`)
		end
	end)

	it("Lock and the Mystery Egg show their price and buy state", function()
		local rows = WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config)
		local lock = find(rows, "Lock")
		expect(lock.status).toBe("buy")
		expect(lock.buttonText).toBe("$200")
		expect(lock.enabled).toBe(true)
		local broke =
			find(WorldShopLogic.rows("ItemShop", baseState({ cash = 5 }), ACTIONS, features(), Config), "Lock")
		expect(broke.enabled).toBe(false)
		expect(broke.status).toBe("buy")
		expect(find(rows, "MysteryEgg").buttonText).toBe("$900")
	end)

	it("upgrades: level x/5, maxed, owned Speed Coil, rank-locked Rebirth N", function()
		local state = baseState()
		state.shop.LockUpgrade = { price = 750, level = 2, maxLevel = 5 }
		state.shop.SpeedCoil = { owned = true }
		state.upgrades[1] = upgradeEntry("Income", { level = 10, maxLevel = 10 })
		state.upgrades[2] = upgradeEntry("CarrySpeed", { unlocked = false, requires = 7, price = nil })
		local rows = WorldShopLogic.rows("UpgradeShop", state, ACTIONS, features(), Config)
		local lockUp = find(rows, "LockUpgrade")
		expect(lockUp.levelText).toBe("Lv 2/5")
		expect(lockUp.status).toBe("buy")
		expect(lockUp.enabled).toBe(true)
		local coil = find(rows, "SpeedCoil")
		expect(coil.status).toBe("owned")
		expect(coil.buttonText).toBe("Owned")
		expect(coil.enabled).toBe(false)
		local income = find(rows, "Income")
		expect(income.status).toBe("maxed")
		expect(income.buttonText).toBe("Max")
		expect(income.enabled).toBe(false)
		local carry = find(rows, "CarrySpeed")
		expect(carry.status).toBe("locked")
		expect(carry.buttonText).toBe("Rebirth 7")
		expect(carry.enabled).toBe(false)
		local luck = find(rows, "Luck")
		expect(luck.status).toBe("buy")
		expect(luck.enabled).toBe(true)
		expect(string.match(luck.levelText or "", "^Lv %d+/%d+$") ~= nil).toBe(true)
	end)

	it("an upgrade the player cannot afford stays listed but disabled", function()
		local rows = WorldShopLogic.rows("UpgradeShop", baseState({ cash = 1 }), ACTIONS, features(), Config)
		local income = find(rows, "Income")
		expect(income.status).toBe("buy")
		expect(income.enabled).toBe(false)
	end)

	it("consumables: sold out, stocked, missing from the restock, and the spray target", function()
		local state = baseState()
		local rows = WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config)
		expect(find(rows, "LuckPotion").status).toBe("soldOut")
		expect(find(rows, "LuckPotion").buttonText).toBe("Sold out")
		expect(find(rows, "LuckPotion").enabled).toBe(false)
		local totem = find(rows, "WeatherTotem") -- not stocked this restock
		expect(totem.status).toBe("soldOut")
		expect(totem.enabled).toBe(false)
		local spray = find(rows, "MutationSpray")
		expect(spray.status).toBe("buy")
		expect(spray.enabled).toBe(true)
		expect(spray.levelText).toBe("2/3 left")
		expect(spray.arg).toBe("s2") -- the highest tier slime
		state.favoriteId = "s1"
		expect(find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "MutationSpray").arg).toBe(
			"s1"
		)
		state.slimes = {}
		local none = find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "MutationSpray")
		expect(none.status).toBe("noSlime")
		expect(none.enabled).toBe(false)
		expect(none.arg).toBeNil()
		state.consumables = nil
		expect(find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "LuckPotion").status).toBe(
			"soldOut"
		)
	end)

	it("PvP tools: owned, rank-locked, buyable, too expensive", function()
		local state = baseState()
		local rows = WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config)
		expect(find(rows, "KnockGlove1").status).toBe("owned")
		expect(find(rows, "KnockGlove1").enabled).toBe(false)
		local locked = find(rows, "FunDanceBomb") -- rank 8, player has 3
		expect(locked.status).toBe("locked")
		expect(locked.buttonText).toBe("Rebirth 8")
		local open = find(rows, "KnockGlove2") -- rank 5 > 3
		expect(open.status).toBe("locked")
		local buy = find(rows, "FunConfetti") -- rank 0
		expect(buy.status).toBe("buy")
		expect(buy.enabled).toBe(true)
		state.cash = 0
		local poor = find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "FunConfetti")
		expect(poor.status).toBe("buy")
		expect(poor.enabled).toBe(false)
	end)

	it("the restock time is the Item Shop's only", function()
		local state = baseState()
		expect(WorldShopLogic.restockAt("ItemShop", state, features())).toBe(1190)
		expect(WorldShopLogic.restockAt("UpgradeShop", state, features())).toBeNil()
		expect(WorldShopLogic.restockAt("ItemShop", state, features({ Consumables = false }))).toBeNil()
	end)
end)

describe("WorldShopLogic.buyArgs", function()
	it("is shopId, itemId, arg - with the slime only for the Mutation Spray", function()
		local rows = WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config)
		local spray = WorldShopLogic.buyArgs(find(rows, "MutationSpray"))
		expect(spray[1]).toBe("ItemShop")
		expect(spray[2]).toBe("MutationSpray")
		expect(spray[3]).toBe("s2")
		local lock = WorldShopLogic.buyArgs(find(rows, "Lock"))
		expect(lock[1]).toBe("ItemShop")
		expect(lock[2]).toBe("Lock")
		expect(lock[3]).toBeNil()
		local up = WorldShopLogic.rows("UpgradeShop", baseState(), ACTIONS, features(), Config)
		expect(WorldShopLogic.buyArgs(find(up, "Income"))[1]).toBe("UpgradeShop")
		expect(Remotes.ACTIONS.ShopBuy).toBeTruthy()
		expect(Shops.find("ItemShop", spray[2])).toBeTruthy() -- the server accepts the pair
	end)
end)

-- Every deny code the server can produce (ShopGuard + Actions + CONTRACT.md §27.7) has a friendly toast.
local function serverCodes(): { [string]: string }
	local out: { [string]: string } = {}
	for code in ShopGuard.MESSAGES :: any do
		out[code] = "ShopGuard.MESSAGES"
	end
	local guard = fs.readFile("src/server/ShopGuard.luau")
	for code in string.gmatch(guard, 'return "(%u%l%w+)"') do
		out[code] = "ShopGuard return"
	end
	for code in string.gmatch(guard, '{ "[^"]+", "(%u%l%w+)" }') do
		out[code] = "ShopGuard.classify"
	end
	local actions = fs.readFile("src/server/Actions.luau")
	for call in string.gmatch(actions, "denied%b()") do
		for code in string.gmatch(call, '"(%u%l%w+)"') do
			out[code] = "Actions denied"
		end
	end
	local contract = fs.readFile("CONTRACT.md")
	local section = string.match(contract, "### 27%.7 Deny codes[^\n]*\n(.-)\n\n")
		or string.match(contract, "### 27%.7 Deny codes[^\n]*\n(.*)")
	for code in string.gmatch(section or "", "`(%u%l%w+)`") do
		out[code] = "CONTRACT 27.7"
	end
	return out
end

describe("deny codes", function()
	it("finds the codes in the server source and the contract", function()
		local codes = serverCodes()
		for _, code in
			{ "FlagOff", "BadShop", "NotInShop", "NotOpen", "OutOfRange", "Dead", "NoCash", "Maxed", "Locked" }
		do
			expect(`{code}: {codes[code] ~= nil}`).toBe(`{code}: true`)
		end
		for _, code in { "SoldOut", "Owned", "BadTarget", "Busy", "Unavailable" } do
			expect(`{code}: {codes[code] ~= nil}`).toBe(`{code}: true`)
		end
	end)

	it("every code the server can send has a short friendly message", function()
		for code, source in serverCodes() do
			local text = (WorldShopLogic.MESSAGES :: any)[code]
			expect(`{code} ({source}): {type(text)}`).toBe(`{code} ({source}): string`)
			expect(#text > 0 and #text <= 40).toBe(true)
			expect(WorldShopLogic.messageFor(code, nil)).toBe(text)
		end
		for code in WorldShopLogic.MESSAGES :: any do
			expect(`{code}: {serverCodes()[code] ~= nil}`).toBe(`{code}: true`) -- no stale client-only code
		end
	end)

	it("maps each code to the agreed text", function()
		local want = {
			FlagOff = "The shops are closed",
			BadShop = "That shop doesn't exist",
			NotInShop = "Not sold here",
			NotOpen = "Open the shop first",
			OutOfRange = "Walk closer to the shop",
			Dead = "You can't shop right now",
			NoCash = "Not enough cash",
			Maxed = "Already maxed",
			Locked = "Rebirth to unlock",
			SoldOut = "Sold out - restocks soon",
			Owned = "You already own this",
			BadTarget = "Pick one of your slimes",
			Busy = "Slow down a little",
			Unavailable = "Can't buy that right now",
		}
		for code, text in want do
			expect(WorldShopLogic.messageFor(code, "server text")).toBe(
				if code == "Unavailable" then "server text" else text
			)
		end
		expect(WorldShopLogic.messageFor("Unavailable", nil)).toBe("Can't buy that right now")
		expect(WorldShopLogic.messageFor("Unavailable", "")).toBe("Can't buy that right now")
		expect(WorldShopLogic.messageFor("Brand new", "from the server")).toBe("from the server")
		expect(WorldShopLogic.messageFor("Brand new", nil)).toBe("Can't buy that right now")
	end)

	it("a failed Request result with a code is mapped, one without keeps its message", function()
		expect(WorldShopLogic.failText({ ok = false, message = "too far", code = "OutOfRange" }, "x")).toBe(
			"Walk closer to the shop"
		)
		expect(WorldShopLogic.failText({ ok = false, message = "server error" }, "x")).toBe("server error")
		expect(WorldShopLogic.failText({ ok = false }, "ShopBuy failed")).toBe("ShopBuy failed")
	end)

	it("a denial that arrives as result and as ShopEvent toasts once", function()
		local gate = WorldShopLogic.toastGate()
		expect(gate("NoCash", 10)).toBe(true)
		expect(gate("NoCash", 10.2)).toBe(false)
		expect(gate("Maxed", 10.3)).toBe(true)
		expect(gate("Maxed", 12)).toBe(true)
	end)
end)

local function newController(): any
	local log: any = { opened = {}, closed = 0, toasts = {}, sent = {}, now = 0 }
	log.controller = WorldShopLogic.controller({
		open = function(shopId: string)
			table.insert(log.opened, shopId)
		end,
		close = function()
			log.closed += 1
		end,
		toast = function(text: string, kind: string, itemId: string?)
			table.insert(log.toasts, { text = text, kind = kind, itemId = itemId })
		end,
		send = function(action: string)
			table.insert(log.sent, action)
		end,
		clock = function()
			return log.now
		end,
	})
	return log
end

describe("WorldShopLogic.controller", function()
	it("opens on ShopEvent Open and on the OpenShop attribute, once", function()
		local log = newController()
		log.controller.onEvent({ kind = "Open", shopId = "ItemShop" })
		log.controller.onAttribute("ItemShop")
		expect(#log.opened).toBe(1)
		expect(log.controller.current()).toBe("ItemShop")
		log.controller.onEvent({ kind = "Open", shopId = "UpgradeShop" })
		expect(log.opened[2]).toBe("UpgradeShop")
		local b = newController()
		b.controller.onAttribute("UpgradeShop")
		expect(b.opened[1]).toBe("UpgradeShop")
		b.controller.onEvent({ kind = "Open", shopId = "NoSuchShop" })
		b.controller.onEvent({ kind = "Open" })
		b.controller.onEvent("junk")
		expect(#b.opened).toBe(1)
	end)

	it("closes on ShopEvent Close (every reason) and on the attribute going nil, without sending CloseShop", function()
		for _, reason in { "closed", "range", "dead", "flag" } do
			local log = newController()
			log.controller.onEvent({ kind = "Open", shopId = "ItemShop" })
			log.controller.onEvent({ kind = "Close", shopId = "ItemShop", reason = reason })
			expect(log.closed).toBe(1)
			expect(log.controller.current()).toBeNil()
			log.controller.onHidden() -- the card hides itself afterwards
			expect(#log.sent).toBe(0)
		end
		local log = newController()
		log.controller.onAttribute("UpgradeShop")
		log.controller.onAttribute(nil)
		expect(log.closed).toBe(1)
		log.controller.onAttribute(nil)
		expect(log.closed).toBe(1)
		-- a stale Close for another shop leaves the open one alone
		log.controller.onEvent({ kind = "Open", shopId = "ItemShop" })
		log.controller.onEvent({ kind = "Close", shopId = "UpgradeShop", reason = "range" })
		expect(log.controller.current()).toBe("ItemShop")
	end)

	it("a close from the client (X, Esc, backdrop, another menu) sends CloseShop once", function()
		local log = newController()
		log.controller.onEvent({ kind = "Open", shopId = "ItemShop" })
		log.controller.onHidden()
		expect(log.sent[1]).toBe("CloseShop")
		expect(#log.sent).toBe(1)
		log.controller.onHidden()
		log.controller.onEvent({ kind = "Close", shopId = "ItemShop", reason = "closed" }) -- the server's echo
		expect(#log.sent).toBe(1)
		expect(log.closed).toBe(0)
		expect(Remotes.ACTIONS.CloseShop).toBeTruthy()
	end)

	it("Purchased toasts '<name> bought!' (+ level for upgrades) with the item's icon", function()
		local log = newController()
		log.controller.onEvent({ kind = "Purchased", shopId = "ItemShop", itemId = "Lock", price = 200 })
		expect(log.toasts[1].text).toBe("Lock base bought!")
		expect(log.toasts[1].kind).toBe("good")
		expect(log.toasts[1].itemId).toBe("Lock")
		log.controller.onEvent({ kind = "Purchased", shopId = "UpgradeShop", itemId = "Income", price = 9, level = 3 })
		expect(log.toasts[2].text).toBe("Slime Snacks bought! Lv 3")
		expect(log.toasts[2].itemId).toBe("Upgrade_Income")
		log.controller.onEvent({ kind = "Purchased", shopId = "ItemShop", itemId = "MutationSpray", price = 1 })
		expect(log.toasts[3].text).toBe("Mutation Spray bought!")
		expect(log.toasts[3].itemId).toBe("Consumable_MutationSpray")
	end)

	it("Denied events and failed results toast the mapped text, once per burst", function()
		local log = newController()
		log.controller.onEvent({
			kind = "Denied",
			shopId = "ItemShop",
			itemId = "Lock",
			code = "NoCash",
			message = "not enough cash",
		})
		expect(log.controller.failed({ ok = false, message = "not enough cash", code = "NoCash" })).toBe(true)
		expect(#log.toasts).toBe(1)
		expect(log.toasts[1].text).toBe("Not enough cash")
		expect(log.toasts[1].kind).toBe("bad")
		expect(log.controller.failed({ ok = false, message = "server error" })).toBe(false)
		log.now = 5
		log.controller.onEvent({ kind = "Denied", code = "Unavailable", message = "not available right now" })
		expect(log.toasts[2].text).toBe("not available right now")
	end)
end)

local function ctx(sent: { any }?): any
	local config: any = table.clone(Config) -- the shops' flags on, whatever the flag matrix forces
	config.FEATURES = features()
	return {
		Config = config,
		Constants = Constants,
		actions = Remotes.ACTIONS,
		send = function(...: any)
			if sent then
				table.insert(sent, table.pack(...))
			end
		end,
		serverNow = function()
			return 1000
		end,
		toast = function() end,
	}
end

describe("Panels/WorldShop", function()
	it("shows the title, cash, restock and one row per item of the chosen shop", function()
		local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Item Shop")
		expect(panel.shop()).toBe("ItemShop")
		expect(UiHarness.find(panel.frame, "RestockTimer").Visible).toBe(true)
		expect(string.find(UiHarness.find(panel.frame, "Cash").Text, "1M", 1, true) ~= nil).toBe(true)
		local list = UiHarness.find(panel.frame, "List")
		local want = #WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config)
		expect(#list:GetChildren() >= want).toBe(true)
		expect(UiHarness.find(panel.frame, "Lock") ~= nil).toBe(true)
		panel.setShop("UpgradeShop")
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Upgrade Shop")
		expect(UiHarness.find(panel.frame, "RestockTimer").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Lock")).toBeNil()
		expect(UiHarness.find(panel.frame, "SpeedCoil") ~= nil).toBe(true)
	end)

	it("hiding the card tells the controller (CloseShop), showing it does not", function()
		local hidden = 0
		local c = ctx()
		c.worldShop = {
			onHidden = function()
				hidden += 1
			end,
		}
		local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), c)
		panel.setOpen(true)
		expect(hidden).toBe(0)
		panel.setOpen(false)
		expect(hidden).toBe(1)
		expect(panel.close.Text).toBe("X")
	end)

	it("every row's icon resolves in the registry", function()
		local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
		panel.update(baseState())
		local registry = ItemIcons.build(Config)
		local seen = 0
		for _, shopId in Shops.ORDER do
			panel.setShop(shopId)
			for _, inst in UiHarness.descendants(panel.frame) do
				if inst.Name == "Icon" and inst:GetAttribute("ItemId") then
					seen += 1
					expect(registry.byId[inst:GetAttribute("ItemId")] ~= nil).toBe(true)
				end
			end
		end
		expect(seen > 10).toBe(true)
	end)
end)

describe("init.client wiring", function()
	local init = fs.readFile("src/ui/init.client.luau")
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	it("builds the world shop card only with FEATURES.WorldShops and joins it to the menu system", function()
		expect(
			has(init, "WorldShop = if Config.FEATURES.WorldShops == true then WorldShopPanel.new(gui, ctx) else nil")
		).toBe(true)
		expect(has(init, '{ key = "WorldShop", nav = nil, panel = panelByKey.WorldShop }')).toBe(true)
		expect(has(init, "WorldShopLogic.controller({")).toBe(true)
		expect(has(init, "Constants.SHOP_EVENT")).toBe(true)
		expect(has(init, "Constants.OPEN_SHOP_ATTRIBUTE")).toBe(true)
		expect(has(init, "worldShop.failed(result)")).toBe(true)
		expect(has(init, 'setOpen("WorldShop")')).toBe(true)
	end)

	it("the shop prompt opens the old combined Shop only with the flag off", function()
		expect(
			MenuClose.promptMenus(Constants.SHOP_PROMPT_NAME, Constants.GUIDE_PROMPT_NAME, false)[Constants.SHOP_PROMPT_NAME]
		).toBe("Shop")
		expect(
			MenuClose.promptMenus(Constants.SHOP_PROMPT_NAME, Constants.GUIDE_PROMPT_NAME)[Constants.SHOP_PROMPT_NAME]
		).toBe("Shop")
		local on = MenuClose.promptMenus(Constants.SHOP_PROMPT_NAME, Constants.GUIDE_PROMPT_NAME, true)
		expect(on[Constants.SHOP_PROMPT_NAME]).toBeNil()
		expect(on[Constants.GUIDE_PROMPT_NAME]).toBe("Guide")
		expect(has(init, "Constants.GUIDE_PROMPT_NAME, Config.FEATURES.WorldShops == true)")).toBe(true)
		expect(fs.isFile("src/ui/Panels/Shop.luau")).toBe(true) -- kept for the flag-off HUD
	end)

	it("buys through ShopBuy from a hold button, never a direct buy action", function()
		local panel = fs.readFile("src/ui/Panels/WorldShop.luau")
		expect(has(panel, 'ctx.send("ShopBuy"')).toBe(true)
		expect(has(panel, "Widgets.holdButton(")).toBe(true)
		expect(has(panel, "ItemIconView.new")).toBe(true)
		expect(has(panel, "Instance.new(")).toBe(false)
	end)

	it("the world shop card follows the one-open-menu state", function()
		local keys = { "Plot", "WorldShop", "Shop" }
		local view = MenuState.view("WorldShop", keys)
		expect(view.backdrop).toBe(true)
		expect(view.cards.WorldShop).toBe(true)
		expect(view.cards.Shop).toBe(false)
		expect(view.cards.Plot).toBe(false)
		expect(MenuState.view(nil, keys).cards.WorldShop).toBe(false)
	end)
end)

describe("world shop layout (full-window card at every gate and landscape size)", function()
	local viewports: { any } = {}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
		table.insert(viewports, vp)
	end
	for _, vp in viewports do
		it(`{vp.name}: the card sits in the full-window backdrop, its X is tappable and its row text fits`, function()
			for _, collapsed in { true, false } do
				local screen = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed })
				local check = LayoutAssert.fullWindow(`{vp.name} {collapsed}`, screen)
				local card = Layout.panelFor(screen, "WorldShop")
				check.inside("WorldShop", card, "backdrop", screen.panel)
				check.onScreen("WorldShop", card)
				check.touch("WorldShop.Close", Layout.panelClose(card))
				local panelScreen = if screen.compact and not screen.navCollapsed
					then Layout.screen(vp.w, vp.h, { navCollapsed = true })
					else screen
				for _, desc in LayoutAssert.worldShopTexts(Layout.panelFor(panelScreen, "WorldShop")) do
					check.text(desc)
				end
				expect(check.report()).toBe("")
			end
		end)
	end
end)

describe("world shop icons", function()
	it("every consumable and PvP tool has a UI-drawn recipe", function()
		local ItemIconArt = UiHarness.ui("ItemIconArt")
		local registry = ItemIcons.build(Config)
		for _, c in Config.CONSUMABLES do
			expect(`Consumable_{c.id}: {ItemIconArt.has(`Consumable_{c.id}`)}`).toBe(`Consumable_{c.id}: true`)
			expect(registry.byId[`Consumable_{c.id}`].source).toBe("drawn")
		end
		for _, tool in Config.PVP_TOOLS do
			expect(`Pvp_{tool.id}: {ItemIconArt.has(`Pvp_{tool.id}`)}`).toBe(`Pvp_{tool.id}: true`)
		end
	end)
end)
