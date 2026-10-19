--!strict
-- World shop client (FEATURES.WorldShops, contract/world-shops.md §27): WorldShopLogic rows / deny texts / open-close
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
	for _, flag in { "Consumables", "PvP" } do
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
					id = "WeatherTotem",
					name = "Weather Totem",
					icon = "🗿",
					text = "totem",
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
		local off = features({ Consumables = false, PvP = false })
		local itemRows = ids(WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, off, Config))
		expect(table.concat(itemRows, ",")).toBe("Lock,SpeedCoil")
		local upgradeRows = ids(WorldShopLogic.rows("UpgradeShop", baseState(), ACTIONS, off, Config))
		expect(table.find(upgradeRows, "Income")).toBeTruthy()
		local all = ids(WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config))
		expect(table.find(all, "WeatherTotem")).toBeTruthy()
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

	it("Lock shows its price and buy state", function()
		local rows = WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config)
		local lock = find(rows, "Lock")
		expect(lock.status).toBe("buy")
		expect(lock.buttonText).toBe("$200")
		expect(lock.enabled).toBe(true)
		local broke =
			find(WorldShopLogic.rows("ItemShop", baseState({ cash = 5 }), ACTIONS, features(), Config), "Lock")
		expect(broke.enabled).toBe(false)
		expect(broke.status).toBe("buy")
	end)

	it("the Speed Coil is an Item Shop row: price, then Owned", function()
		local state = baseState()
		local coil = find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "SpeedCoil")
		expect(coil.status).toBe("buy")
		state.shop.SpeedCoil = { owned = true }
		coil = find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "SpeedCoil")
		expect(coil.status).toBe("owned")
		expect(coil.buttonText).toBe("Owned")
		expect(coil.enabled).toBe(false)
	end)

	it("upgrades: level x/5, maxed, rank-locked Rebirth N (the Speed Coil is not one)", function()
		local state = baseState()
		state.shop.LockUpgrade = { price = 750, level = 2, maxLevel = 5 }
		state.upgrades[1] = upgradeEntry("Income", { level = 10, maxLevel = 10 })
		state.upgrades[2] = upgradeEntry("CarrySpeed", { unlocked = false, requires = 7, price = nil })
		local rows = WorldShopLogic.rows("UpgradeShop", state, ACTIONS, features(), Config)
		local lockUp = find(rows, "LockUpgrade")
		expect(lockUp.levelText).toBe("Lv 2/5")
		expect(lockUp.status).toBe("buy")
		expect(lockUp.enabled).toBe(true)
		expect(table.find(ids(rows), "SpeedCoil")).toBeNil() -- an item now, listed in the Item Shop
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
		expect(lockUp.progress).toBeCloseTo(2 / 5, 4)
		expect(income.progress).toBe(1)
	end)

	it("an upgrade the player cannot afford stays listed but disabled", function()
		local rows = WorldShopLogic.rows("UpgradeShop", baseState({ cash = 1 }), ACTIONS, features(), Config)
		local income = find(rows, "Income")
		expect(income.status).toBe("buy")
		expect(income.enabled).toBe(false)
	end)

	it("consumables: sold out, stocked, and a row with no stock entry", function()
		local state = baseState()
		local rows = WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config)
		expect(find(rows, "LuckPotion").status).toBe("soldOut")
		expect(find(rows, "LuckPotion").buttonText).toBe("Sold out")
		expect(find(rows, "LuckPotion").enabled).toBe(false)
		local totem = find(rows, "WeatherTotem")
		expect(totem.status).toBe("buy")
		expect(totem.enabled).toBe(true)
		expect(totem.levelText).toBe("2/3 left")
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

describe("WorldShopLogic.slot", function()
	it("buy rows get the button; every other state a well or the MAX stamp", function()
		local function slot(status: string, text: string): any
			return WorldShopLogic.slot({ status = status :: any, buttonText = text })
		end
		expect(slot("buy", "$10K").kind).toBe("buy")
		expect(slot("buy", "$10K").text).toBe("$10K")
		expect(slot("maxed", "Max").kind).toBe("stamp")
		expect(slot("maxed", "Max").text).toBe("MAX")
		local owned = slot("owned", "Owned")
		expect(owned.kind).toBe("status")
		expect(owned.text).toBe("✅ Owned")
		expect(owned.good).toBe(true)
		local locked = slot("locked", "Rebirth 12")
		expect(locked.kind).toBe("status")
		expect(locked.text).toBe("🔒 Rebirth 12")
		expect(locked.sub).toBe("to unlock")
		expect(slot("soldOut", "Sold out").text).toBe("Sold out")
		expect(slot("unavailable", "Coming soon").text).toBe("Coming soon")
	end)

	it("rows carry the pip and stock fields", function()
		local state = baseState()
		state.upgrades[1] = upgradeEntry("Income", { level = 3, maxLevel = 10 })
		local up = WorldShopLogic.rows("UpgradeShop", state, ACTIONS, features(), Config)
		expect(find(up, "Income").level).toBe(3)
		expect(find(up, "Income").maxLevel).toBe(10)
		expect(find(up, "LockUpgrade").level).toBe(2)
		expect(find(up, "LockUpgrade").maxLevel).toBe(5)
		local items = WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config)
		expect(find(items, "WeatherTotem").stockText).toBe("2/3 left")
		expect(find(items, "WeatherTotem").maxLevel).toBeNil()
		expect(find(items, "Lock").maxLevel).toBeNil()
		expect(find(items, "Lock").stockText).toBeNil()
	end)
end)

describe("WorldShopLogic.buyArgs", function()
	it("is shopId, itemId", function()
		local rows = WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config)
		local totem = WorldShopLogic.buyArgs(find(rows, "WeatherTotem"))
		expect(totem[1]).toBe("ItemShop")
		expect(totem[2]).toBe("WeatherTotem")
		expect(totem[3]).toBeNil()
		local lock = WorldShopLogic.buyArgs(find(rows, "Lock"))
		expect(lock[1]).toBe("ItemShop")
		expect(lock[2]).toBe("Lock")
		expect(lock[3]).toBeNil()
		local up = WorldShopLogic.rows("UpgradeShop", baseState(), ACTIONS, features(), Config)
		expect(WorldShopLogic.buyArgs(find(up, "Income"))[1]).toBe("UpgradeShop")
		expect(Remotes.ACTIONS.ShopBuy).toBeTruthy()
		expect(Shops.find("ItemShop", totem[2])).toBeTruthy() -- the server accepts the pair
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
	local contract = fs.readFile("contract/world-shops.md")
	local section = string.match(contract, "## 27%.7 Deny codes[^\n]*\n(.-)\n\n")
		or string.match(contract, "## 27%.7 Deny codes[^\n]*\n(.*)")
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
		log.controller.onEvent({ kind = "Purchased", shopId = "ItemShop", itemId = "WeatherTotem", price = 1 })
		expect(log.toasts[3].text).toBe("Weather Totem bought!")
		expect(log.toasts[3].itemId).toBe("Consumable_WeatherTotem")
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
		expect(UiHarness.find(panel.frame, "SpeedCoil") ~= nil).toBe(true)
		panel.setShop("UpgradeShop")
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Upgrade Shop")
		expect(UiHarness.find(panel.frame, "RestockTimer").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Lock")).toBeNil()
		expect(UiHarness.find(panel.frame, "SpeedCoil")).toBeNil()
		expect(UiHarness.find(panel.frame, "Income") ~= nil).toBe(true)
	end)

	it("dresses both shops in the shared purple: own title, corner icon and tagline chip", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		expect(panel.frame.BackgroundColor3).toBe(Theme.Bg)
		expect(UiHarness.find(panel.frame, "IconTile"):FindFirstChild("Icon").Text).toBe(WorldShop.ICON.ItemShop)
		local cash = UiHarness.find(panel.frame, "Cash")
		expect(cash.Text).toBe("$1M")
		expect(cash.TextColor3).toBe(Theme.Gold)
		expect(cash.BackgroundColor3).toBe(Theme.Ink)
		local restock = UiHarness.find(panel.frame, "RestockTimer")
		expect(restock.Text).toBe("Restocks in 3:10")
		expect(restock.TextColor3).toBe(Theme.Muted)
		expect(UiHarness.find(panel.frame, "Tagline").Visible).toBe(false)
		local lock = UiHarness.find(panel.frame, "Lock")
		expect(lock.BackgroundColor3).toBe(Theme.Row)
		expect(lock:FindFirstChild("Levels")).toBeNil()
		expect(UiHarness.find(lock, "LevelBar")).toBeNil()
		panel.setShop("UpgradeShop")
		expect(panel.frame.BackgroundColor3).toBe(Theme.Bg)
		expect(UiHarness.find(panel.frame, "IconTile"):FindFirstChild("Icon").Text).toBe(WorldShop.ICON.UpgradeShop)
		local tagline = UiHarness.find(panel.frame, "Tagline")
		expect(tagline.Visible).toBe(true)
		expect(tagline.Text).toBe("Kept when you rebirth")
		expect(tagline.TextColor3).toBe(Theme.Muted)
	end)

	it("item rows: green hold Buy with ink price, gold stock tag, Owned and Rebirth status wells", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		local lock = UiHarness.find(panel.frame, "Lock")
		local buy = lock:FindFirstChild("Buy")
		expect(buy.Visible).toBe(true)
		expect(buy.Text).toBe("$200")
		expect(buy.BackgroundColor3).toBe(Theme.Good)
		expect(buy.TextColor3).toBe(Theme.Ink)
		expect(buy:GetAttribute("HoldConfirm") ~= nil).toBe(true)
		expect(lock:FindFirstChild("Stock").Visible).toBe(false)
		local totem = UiHarness.find(panel.frame, "WeatherTotem")
		local stock = totem:FindFirstChild("Stock")
		expect(stock.Visible).toBe(true)
		expect(stock.Text).toBe("2/3 left")
		expect(stock.BackgroundColor3).toBe(Theme.Gold)
		expect(stock.TextColor3).toBe(Theme.Ink)
		expect(stock.ZIndex > totem:FindFirstChild("Icon").ZIndex).toBe(true)
		local owned = UiHarness.find(panel.frame, "KnockGlove1")
		expect(owned:FindFirstChild("Buy").Visible).toBe(false)
		local well = owned:FindFirstChild("Status")
		expect(well.Visible).toBe(true)
		expect(well.Text).toBe("✅ Owned")
		expect(well.TextColor3).toBe(Theme.Good)
		expect(well.BackgroundColor3).toBe(Theme.Ink)
		local locked = UiHarness.find(panel.frame, "FunDanceBomb")
		expect(locked:FindFirstChild("Buy").Visible).toBe(false)
		local lockWell = locked:FindFirstChild("Status")
		expect(lockWell.Visible).toBe(true)
		expect(string.find(lockWell.Text, "🔒 Rebirth 8", 1, true) == 1).toBe(true)
		expect(string.find(lockWell.Text, "to unlock", 1, true) ~= nil).toBe(true)
		expect(lockWell.TextColor3).toBe(Theme.Muted)
	end)

	it("a locked well grows with its text and the name column gives way", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local slot = WorldShopLogic.slot({ status = "locked", buttonText = "Rebirth 120" })
		local w = WorldShop.statusWidth(slot)
		expect(w >= Layout.lineWidth(slot.text, WorldShop.SIZE.status, true) + WorldShop.SIZE.statusPad * 2).toBe(true)
		expect(w > WorldShop.BUY_W).toBe(true)
		expect(WorldShop.statusWidth(WorldShopLogic.slot({ status = "owned", buttonText = "Owned" }))).toBe(
			WorldShop.BUY_W
		)
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		local bomb = UiHarness.find(panel.frame, "FunDanceBomb")
		local want = WorldShop.statusWidth(WorldShopLogic.slot({ status = "locked", buttonText = "Rebirth 8" }))
		expect(bomb:FindFirstChild("Status").Size.X.Offset).toBe(want)
		local name = bomb:FindFirstChild("ItemName")
		local lockName = UiHarness.find(panel.frame, "Lock"):FindFirstChild("ItemName")
		expect(name.Size.X.Offset - lockName.Size.X.Offset).toBe(WorldShop.BUY_W - want)
	end)

	it("upgrade rows: one pip per level, gold MAX stamp when maxed, the buyable one highlighted", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local Theme = UiHarness.ui("Widgets").Theme
		local state = baseState()
		state.upgrades[1] = upgradeEntry("Income", { level = 3, maxLevel = 10 })
		state.upgrades[2] = upgradeEntry("CarrySpeed", { level = 4, maxLevel = 4 })
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(state)
		panel.setShop("UpgradeShop")
		local income = UiHarness.find(panel.frame, "Income")
		expect(income.Size.Y.Offset).toBe(WorldShop.ROW_LEVELS)
		expect(UiHarness.find(income, "LevelBar")).toBeNil()
		local pips = income:FindFirstChild("Levels")
		expect(#pips:GetChildren()).toBe(10)
		local on = 0
		for _, pip in pips:GetChildren() do
			if pip.BackgroundColor3 == Theme.Gold then
				on += 1
			else
				expect(pip.BackgroundColor3).toBe(Theme.Ink)
			end
		end
		expect(on).toBe(3)
		expect(income.BackgroundColor3).toBe(Theme.BgLight)
		expect(income:FindFirstChild("Buy").Visible).toBe(true)
		expect(income:FindFirstChild("Buy").BackgroundColor3).toBe(Theme.Good)
		expect(income:FindFirstChild("MaxStamp").Visible).toBe(false)
		local carry = UiHarness.find(panel.frame, "CarrySpeed")
		expect(carry.BackgroundColor3).toBe(Theme.Row)
		expect(carry:FindFirstChild("Buy").Visible).toBe(false)
		expect(carry:FindFirstChild("Status").Visible).toBe(false)
		local stamp = carry:FindFirstChild("MaxStamp")
		expect(stamp.Visible).toBe(true)
		expect(stamp.Text).toBe("MAX")
		expect(stamp.BackgroundColor3).toBe(Theme.Gold)
		expect(stamp.TextColor3).toBe(Theme.Ink)
		local all = 0
		for _, pip in carry:FindFirstChild("Levels"):GetChildren() do
			expect(pip.BackgroundColor3).toBe(Theme.Gold)
			all += 1
		end
		expect(all).toBe(4)
		-- can't afford it: no highlight, and the Buy button is a sunken well
		panel.update(baseState({ cash = 1 }))
		income = UiHarness.find(panel.frame, "Income")
		expect(income.BackgroundColor3).toBe(Theme.Row)
		expect(income:FindFirstChild("Buy").BackgroundColor3).toBe(Theme.Disabled)
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
			do
				local screen = Layout.screen(vp.w, vp.h)
				local check = LayoutAssert.fullWindow(vp.name, screen)
				local card = Layout.panelFor(screen, "WorldShop")
				check.inside("WorldShop", card, "backdrop", screen.panel)
				check.onScreen("WorldShop", card)
				check.touch("WorldShop.Close", Layout.panelClose(card))
				for _, desc in LayoutAssert.worldShopTexts(Layout.panelFor(screen, "WorldShop")) do
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
			-- drawn recipe stays as the fallback; an uploaded picture (ItemIcons.IMAGES) wins
			local source = registry.byId[`Consumable_{c.id}`].source
			expect(`Consumable_{c.id}: {source == "drawn" or source == "image"}`).toBe(`Consumable_{c.id}: true`)
		end
		for _, tool in Config.PVP_TOOLS do
			expect(`Pvp_{tool.id}: {ItemIconArt.has(`Pvp_{tool.id}`)}`).toBe(`Pvp_{tool.id}: true`)
		end
	end)
end)
