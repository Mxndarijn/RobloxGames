--!strict
-- World shop client (contract/world-shops.md §27): WorldShopLogic rows / deny texts / open-close
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
		requires = def.levelRequires[2] or def.levelRequires[1],
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
		lockDuration = 70,
		shop = {
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
			{ slime = { id = "s1", tier = 2 }, income = 1, sellPrice = 1 },
			{ slime = { id = "s2", tier = 5 }, income = 1, sellPrice = 1 },
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
		expect(table.concat(itemRows, ",")).toBe("SpeedCoil")
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

	it("has no Lock or lock-upgrade row: locks are bought on the plot", function()
		for _, shopId in Shops.ORDER do
			local rowIds = ids(WorldShopLogic.rows(shopId, baseState(), ACTIONS, features(), Config))
			expect(table.find(rowIds, "Lock")).toBeNil()
			expect(table.find(rowIds, "LockUpgrade")).toBeNil()
		end
	end)

	it("the Speed Coil shows its price, disabled when the player cannot afford it", function()
		local coil = find(WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config), "SpeedCoil")
		expect(coil.status).toBe("buy")
		expect(coil.buttonText).toBe("Buy $4K")
		expect(coil.enabled).toBe(true)
		local broke =
			find(WorldShopLogic.rows("ItemShop", baseState({ cash = 5 }), ACTIONS, features(), Config), "SpeedCoil")
		expect(broke.enabled).toBe(false)
		expect(broke.status).toBe("buy")
		expect(string.match(broke.buttonText, "^Need %$.+ more$") ~= nil).toBe(true) -- a disabled button says what is missing
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

	it("upgrades: level x/max, maxed, rank-locked Rebirth N (the Speed Coil is not one)", function()
		local state = baseState()
		state.upgrades[1] = upgradeEntry("Income", { level = 10, maxLevel = 10 })
		state.upgrades[2] = upgradeEntry("CarrySpeed", { unlocked = false, requires = 7, price = nil })
		local rows = WorldShopLogic.rows("UpgradeShop", state, ACTIONS, features(), Config)
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
		expect(luck.levelText).toBe(`Lv 1/{luck.maxLevel}`)
		expect(luck.progress).toBeCloseTo(1 / (luck.maxLevel :: number), 4)
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

	it("a Goo Trap row sells charges with a held tag until the stack is full", function()
		local state = baseState()
		state.pvp.charges = { GooTrap1 = 2 }
		state.pvp.owned.GooTrap1 = true
		local trap = find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "GooTrap1") -- rank 3
		expect(trap.status).toBe("buy")
		expect(trap.enabled).toBe(true)
		expect(trap.stockText).toBe(`2/{Config.PVP.TRAP_MAX_HELD} held`)
		state.pvp.charges.GooTrap1 = Config.PVP.TRAP_MAX_HELD
		local full = find(WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config), "GooTrap1")
		expect(full.status).toBe("maxed")
		expect(full.enabled).toBe(false)
	end)

	it("the restock time is the Item Shop's only", function()
		local state = baseState()
		expect(WorldShopLogic.restockAt("ItemShop", state, features())).toBe(1190)
		expect(WorldShopLogic.restockAt("UpgradeShop", state, features())).toBeNil()
		expect(WorldShopLogic.restockAt("ItemShop", state, features({ Consumables = false }))).toBeNil()
	end)
end)

local function shopView(shopId: string, state: any, opts: any?, feats: any?): WorldShopLogic.View
	return WorldShopLogic.view(shopId, state, ACTIONS, feats or features(), Config, opts)
end

local function entry(v: WorldShopLogic.View, key: string): WorldShopLogic.Entry
	for _, e in v.entries do
		if e.key == key then
			return e
		end
	end
	error(`no entry {key}`)
end

local function entryKeys(v: WorldShopLogic.View): { string }
	local out = {}
	for _, e in v.entries do
		table.insert(out, e.key)
	end
	return out
end

local function gloves(state: any, pick: number?): WorldShopLogic.Entry
	local v = shopView("ItemShop", state, { tab = "PvP", picks = { Knockback = pick } })
	for _, e in v.entries do
		if string.find(e.key, "ladder_Knockback", 1, true) then
			return e
		end
	end
	error("no gloves card")
end

describe("WorldShopLogic.view: Item Shop", function()
	it("has the Items, PvP and Fun tabs in order and opens on Items", function()
		local v = shopView("ItemShop", baseState())
		local tabIds = {}
		for _, t in v.tabs do
			table.insert(tabIds, t.id)
		end
		expect(table.concat(tabIds, ",")).toBe("Items,PvP,Fun")
		expect(v.tab).toBe("Items")
		expect(shopView("ItemShop", baseState(), { tab = "Nope" }).tab).toBe("Items")
		expect(shopView("ItemShop", baseState(), { tab = "Fun" }).tab).toBe("Fun")
	end)

	it("with PvP off only the Items tab is left", function()
		local v = shopView("ItemShop", baseState(), nil, features({ PvP = false }))
		expect(#v.tabs).toBe(1)
		expect(v.tabs[1].id).toBe("Items")
	end)

	it("a tab gets a dot only while something in it can be bought now", function()
		local rich = shopView("ItemShop", baseState())
		for _, t in rich.tabs do
			expect(t.dot).toBe(true)
		end
		local broke = shopView("ItemShop", baseState({ cash = 0 }))
		for _, t in broke.tabs do
			expect(t.dot).toBe(false)
		end
	end)

	it("Items: gear, then potions with the restock timer; an owned Speed Coil moves to a thin Owned row", function()
		local v = shopView("ItemShop", baseState())
		expect(table.concat(entryKeys(v), ",")).toBe(
			"label_gear,row_SpeedCoil,label_consumables,row_LuckPotion,row_WeatherTotem"
		)
		expect(entry(v, "label_consumables").aside).toBe("restock")
		local owned = baseState()
		owned.shop.SpeedCoil.owned = true
		local w = shopView("ItemShop", owned)
		expect(table.concat(entryKeys(w), ",")).toBe(
			"label_consumables,row_LuckPotion,row_WeatherTotem,label_owned,row_SpeedCoil_thin"
		)
		expect(entry(w, "row_SpeedCoil_thin").thin).toBe(true)
	end)

	it("PvP: one card per line, gloves then traps then blasters", function()
		local v = shopView("ItemShop", baseState({ pvp = { rank = 20, owned = {}, charges = {} } }), { tab = "PvP" })
		expect(table.concat(entryKeys(v), ",")).toBe("label_ladders,ladder_Knockback,ladder_Trap,ladder_Blaster")
	end)

	it("gloves show the best tier above yours that your rebirths reach", function()
		local e = gloves(baseState({ pvp = { rank = 8, owned = { KnockGlove1 = true, KnockGlove2 = true } } }))
		local ladder = e.ladder :: WorldShopLogic.Ladder
		expect(ladder.row.id).toBe("KnockGlove3")
		expect(ladder.row.status).toBe("buy")
		expect(string.find(ladder.row.description, "Yours: Bounce glove", 1, true) ~= nil).toBe(true)
		local states = {}
		for _, s in ladder.steps do
			table.insert(states, `{s.state}{if s.selected then "*" else ""}`)
		end
		expect(table.concat(states, ",")).toBe("owned,owned,open*,locked,locked")
	end)

	it("tiers can be skipped: a Rebirth 12 player with no glove sees the Thunder glove", function()
		local e = gloves(baseState({ pvp = { rank = 12, owned = {} } }))
		expect((e.ladder :: any).row.id).toBe("KnockGlove4")
		expect(string.find((e.ladder :: any).row.description, "none yet", 1, true) ~= nil).toBe(true)
	end)

	it("with no higher tier unlocked the card shows the next one, locked", function()
		local e = gloves(baseState({ pvp = { rank = 3, owned = { KnockGlove1 = true } } }))
		local row = (e.ladder :: any).row
		expect(row.id).toBe("KnockGlove2")
		expect(row.status).toBe("locked")
		expect(row.buttonText).toBe("Rebirth 5")
	end)

	it("a tapped tier wins, an owned one shows Owned", function()
		local state = baseState({ pvp = { rank = 8, owned = { KnockGlove1 = true, KnockGlove2 = true } } })
		expect((gloves(state, 1).ladder :: any).row.status).toBe("owned")
		expect((gloves(state, 5).ladder :: any).row.status).toBe("locked")
		expect((gloves(state, 9).ladder :: any).row.id).toBe("KnockGlove3")
	end)

	it("owning the top glove leaves one thin Max row", function()
		local owned = {}
		for i = 1, 5 do
			owned[`KnockGlove{i}`] = true
		end
		local e = gloves(baseState({ pvp = { rank = 30, owned = owned } }))
		expect(e.kind).toBe("row")
		expect(e.thin).toBe(true)
		local row = e.row :: WorldShopLogic.Row
		expect(row.id).toBe("KnockGlove5")
		expect(WorldShopLogic.slot(row).kind).toBe("stamp")
	end)

	it("traps show the best reachable tier with its held tag, and list the other traps you hold", function()
		local state = baseState({ pvp = { rank = 6, owned = { GooTrap1 = true }, charges = { GooTrap1 = 2 } } })
		local v = shopView("ItemShop", state, { tab = "PvP" })
		local ladder = entry(v, "ladder_Trap").ladder :: WorldShopLogic.Ladder
		expect(ladder.row.id).toBe("GooTrap2")
		expect(ladder.row.stockText).toBe(`0/{Config.PVP.TRAP_MAX_HELD} held`)
		expect(string.find(ladder.row.description, "Other traps held: 2", 1, true) ~= nil).toBe(true)
		expect(ladder.steps[1].state).toBe("owned")
	end)

	it("Fun: one grid of every fun item, buy tiles show the price only", function()
		local v = shopView("ItemShop", baseState({ pvp = { rank = 3, owned = {} } }), { tab = "Fun" })
		expect(table.concat(entryKeys(v), ",")).toBe("label_fun,grid_fun")
		local tiles = entry(v, "grid_fun").tiles :: { WorldShopLogic.Row }
		local fun = 0
		for _, t in Config.PVP_TOOLS do
			if t.kind == "fun" then
				fun += 1
			end
		end
		expect(#tiles).toBe(fun)
		for _, t in tiles do
			if t.status == "buy" then
				expect(string.find(t.buttonText, "Buy", 1, true)).toBe(nil)
			end
		end
	end)
end)

describe("WorldShopLogic.view: Upgrade Shop", function()
	it("groups the upgrades under labels; no tabs", function()
		local v = shopView("UpgradeShop", baseState())
		expect(#v.tabs).toBe(0)
		expect(table.concat(entryKeys(v), ",")).toBe(
			"label_group1,row_Income,row_OfflineCap,label_group2,row_CarrySpeed,row_QuickBrew,label_group3,row_Luck"
		)
		expect(entry(v, "label_group1").text).toBe("Earn more")
	end)

	it("maxed and not-yet-unlocked upgrades sink to thin rows at the end of their group", function()
		local state = baseState()
		state.upgrades = {
			upgradeEntry("Income", { level = 2 }),
			upgradeEntry("OfflineCap", { level = 0, unlocked = false, requires = 3 }),
			upgradeEntry("CarrySpeed", { level = 4 }),
			upgradeEntry("QuickBrew", { level = 1 }),
			upgradeEntry("Luck", { level = 1 }),
		}
		local v = shopView("UpgradeShop", state)
		expect(table.concat(entryKeys(v), ",")).toBe(
			"label_group1,row_Income,row_OfflineCap_thin,label_group2,row_QuickBrew,row_CarrySpeed_thin,label_group3,row_Luck"
		)
		expect((entry(v, "row_OfflineCap_thin").row :: any).description).toBe("Unlocks at Rebirth 3")
		expect((entry(v, "row_Income").row :: any).description).toBe("+20% → +30% income")
	end)

	it("upgradeEffect: now -> next, Next at level 0, the total when maxed, hours stay hours", function()
		expect(WorldShopLogic.upgradeEffect("Income", "+10% income", 0, 25)).toBe("Next: +10% income")
		expect(WorldShopLogic.upgradeEffect("Income", "+10% income", 25, 25)).toBe("+250% income")
		expect(WorldShopLogic.upgradeEffect("CarrySpeed", "-15% carry slowdown", 2, 4)).toBe(
			"-30% → -45% carry slowdown"
		)
		expect(WorldShopLogic.upgradeEffect("OfflineCap", "+1h offline income cap", 1, 4)).toBe(
			"+1h → +2h offline income cap"
		)
		expect(WorldShopLogic.upgradeEffect("Odd", "no number here", 1, 4)).toBe("no number here")
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
		expect(slot("maxed", "Max").text).toBe("Max")
		local owned = slot("owned", "Owned")
		expect(owned.kind).toBe("status")
		expect(owned.text).toBe("Owned")
		expect(owned.good).toBe(true)
		expect(owned.check).toBe(true)
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
		expect(find(up, "Luck").level).toBe(1)
		expect(find(up, "Luck").maxLevel).toBe(upgradeEntry("Luck").maxLevel)
		local items = WorldShopLogic.rows("ItemShop", state, ACTIONS, features(), Config)
		expect(find(items, "WeatherTotem").stockText).toBe("2/3 left")
		expect(find(items, "WeatherTotem").maxLevel).toBeNil()
		expect(find(items, "SpeedCoil").maxLevel).toBeNil()
		expect(find(items, "SpeedCoil").stockText).toBeNil()
	end)
end)

describe("WorldShopLogic.buyArgs", function()
	it("is shopId, itemId", function()
		local rows = WorldShopLogic.rows("ItemShop", baseState(), ACTIONS, features(), Config)
		local totem = WorldShopLogic.buyArgs(find(rows, "WeatherTotem"))
		expect(totem[1]).toBe("ItemShop")
		expect(totem[2]).toBe("WeatherTotem")
		expect(totem[3]).toBeNil()
		local coil = WorldShopLogic.buyArgs(find(rows, "SpeedCoil"))
		expect(coil[1]).toBe("ItemShop")
		expect(coil[2]).toBe("SpeedCoil")
		expect(coil[3]).toBeNil()
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
		for _, code in { "BadShop", "NotInShop", "NotOpen", "OutOfRange", "Dead", "NoCash", "Maxed", "Locked" } do
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
		for _, reason in { "closed", "range", "dead" } do
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

	it("Purchased toasts '<name> bought' (+ level for upgrades) with the item's icon", function()
		local log = newController()
		log.controller.onEvent({ kind = "Purchased", shopId = "ItemShop", itemId = "SpeedCoil", price = 200 })
		expect(log.toasts[1].text).toBe("Speed coil bought")
		expect(log.toasts[1].kind).toBe("good")
		expect(log.toasts[1].itemId).toBe("SpeedCoil")
		log.controller.onEvent({ kind = "Purchased", shopId = "UpgradeShop", itemId = "Income", price = 9, level = 3 })
		expect(log.toasts[2].text).toBe("Slime snacks bought, Lv 3")
		expect(log.toasts[2].itemId).toBe("Upgrade_Income")
		log.controller.onEvent({ kind = "Purchased", shopId = "ItemShop", itemId = "WeatherTotem", price = 1 })
		expect(log.toasts[3].text).toBe("Weather totem bought")
		expect(log.toasts[3].itemId).toBe("Consumable_WeatherTotem")
	end)

	it("Denied events and failed results toast the mapped text, once per burst", function()
		local log = newController()
		log.controller.onEvent({
			kind = "Denied",
			shopId = "ItemShop",
			itemId = "SpeedCoil",
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
	local function tap(panel: any, name: string)
		UiHarness.fire(UiHarness.find(panel.frame, name), "Activated")
	end

	it("shows the title, the tabs, the restock timer and the rows of the chosen shop; no cash chip", function()
		local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Item shop")
		expect(panel.shop()).toBe("ItemShop")
		expect(UiHarness.find(panel.frame, "Tabs").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "RestockTimer").Text).toBe("Restocks in 3:10")
		expect(UiHarness.find(panel.frame, "Cash")).toBeNil()
		expect(UiHarness.find(panel.frame, "SpeedCoil") ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "KnockGlove1")).toBeNil() -- PvP lives in its own tab
		expect(UiHarness.find(panel.frame, "Lock")).toBeNil()
		panel.setShop("UpgradeShop")
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Upgrade shop")
		expect(UiHarness.find(panel.frame, "Tabs").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "RestockTimer")).toBeNil()
		expect(UiHarness.find(panel.frame, "SpeedCoil")).toBeNil()
		expect(UiHarness.find(panel.frame, "Income") ~= nil).toBe(true)
	end)

	it("keeps the Item Shop card one height on every tab; the Upgrade Shop fits its rows", function()
		local Widgets = UiHarness.ui("Widgets")
		local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
		local body = UiHarness.find(panel.frame, "Body")
		panel.update(baseState())
		panel.setShop("ItemShop")
		local c = Layout.PANEL_CHROME
		local fullH = Layout.menuHeight("WorldShop") - c.header - c.pad
		local heights = {}
		for _, def in WorldShopLogic.TABS do
			panel.setTab(def.id)
			expect(panel.tab()).toBe(def.id)
			heights[def.id] = Widgets.contentHeight(body)
			expect(heights[def.id]).toBe(fullH)
		end
		panel.setShop("UpgradeShop")
		local list = UiHarness.find(panel.frame, "List")
		expect(Widgets.contentHeight(body)).toBe(list.CanvasSize.Y.Offset)
	end)

	it("dresses both shops in the shared panel colours: own title and corner icon", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		expect(panel.frame.BackgroundColor3).toBe(Theme.Bg)
		local tile = UiHarness.find(panel.frame, "IconTile")
		expect(tile:FindFirstChild("Icon").Text).toBe(WorldShop.ICON.ItemShop.text)
		expect(tile.BackgroundColor3).toBe(Theme.Text)
		expect(UiHarness.find(tile, "UpArrow").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "RestockTimer").TextColor3).toBe(Theme.Gold)
		local coil = UiHarness.find(panel.frame, "SpeedCoil")
		expect(coil.BackgroundColor3).toBe(Theme.Row)
		expect(coil:FindFirstChild("Levels")).toBeNil()
		panel.setShop("UpgradeShop")
		expect(panel.frame.BackgroundColor3).toBe(Theme.Bg)
		-- the Upgrade shop draws its arrow in Ink on a gold tile instead of an emoji
		expect(tile:FindFirstChild("Icon").Text).toBe("")
		expect(UiHarness.find(tile, "UpArrow").Visible).toBe(true)
		expect(tile.BackgroundColor3).toBe(Theme.Gold)
	end)

	it(
		"tabs: Items first, a tap switches, the one on show is Accent, others with something to buy get a dot",
		function()
			local Theme = UiHarness.ui("Widgets").Theme
			local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
			panel.update(baseState())
			panel.setShop("ItemShop")
			local items, fun = UiHarness.find(panel.frame, "Tab_Items"), UiHarness.find(panel.frame, "Tab_Fun")
			expect(items.BackgroundColor3).toBe(Theme.Accent)
			expect(fun.BackgroundColor3).toBe(Theme.Info)
			expect(fun:FindFirstChild("Dot").Visible).toBe(true)
			expect(items:FindFirstChild("Dot").Visible).toBe(false)
			tap(panel, "Tab_Fun")
			expect(UiHarness.find(panel.frame, "Tab_Fun").BackgroundColor3).toBe(Theme.Accent)
			expect(UiHarness.find(panel.frame, "SpeedCoil")).toBeNil()
			expect(UiHarness.find(panel.frame, "FunGrid") ~= nil).toBe(true)
			-- every open starts on Items again
			panel.setShop("ItemShop")
			expect(panel.tab()).toBe("Items")
			expect(UiHarness.find(panel.frame, "SpeedCoil") ~= nil).toBe(true)
			panel.setTab("PvP")
			expect(panel.tab()).toBe("PvP")
			expect(UiHarness.find(panel.frame, "Ladder_Knockback") ~= nil).toBe(true)
			panel.setTab("Nope")
			expect(panel.tab()).toBe("Items")
		end
	)

	it("item rows: green hold Buy with ink price, gold stock tag; an owned Speed Coil is a thin Owned row", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		local coil = UiHarness.find(panel.frame, "SpeedCoil")
		local buy = coil:FindFirstChild("Buy")
		expect(buy.Visible).toBe(true)
		expect(buy.Text).toBe("Buy $4K")
		expect(buy.BackgroundColor3).toBe(Theme.Good)
		expect(buy.TextColor3).toBe(Theme.Ink)
		expect(buy:GetAttribute("HoldConfirm") ~= nil).toBe(true)
		expect(coil:FindFirstChild("Stock").Visible).toBe(false)
		local totem = UiHarness.find(panel.frame, "WeatherTotem")
		local stock = totem:FindFirstChild("Stock")
		expect(stock.Visible).toBe(true)
		expect(stock.Text).toBe("2/3 left")
		expect(stock.BackgroundColor3).toBe(Theme.Gold)
		expect(stock.TextColor3).toBe(Theme.Ink)
		expect(stock.ZIndex > totem:FindFirstChild("Icon").ZIndex).toBe(true)
		local owned = baseState()
		owned.shop.SpeedCoil.owned = true
		panel.update(owned)
		coil = UiHarness.find(panel.frame, "SpeedCoil")
		expect(coil.Size.Y.Offset).toBe(WorldShop.ROW_THIN)
		local well = coil:FindFirstChild("Status")
		expect(well.Visible).toBe(true)
		expect(well.Text).toBe("Owned")
		expect(well:FindFirstChild("Check").Visible).toBe(true)
		expect(well.TextColor3).toBe(Theme.Good)
		expect(well.BackgroundColor3).toBe(Theme.Ink)
	end)

	it("PvP: one ladder card per line; tapping a tier shows that tier", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local Theme = UiHarness.ui("Widgets").Theme
		local sent = {}
		local panel = WorldShop.new(UiHarness.root(), ctx(sent))
		panel.update(baseState({ pvp = { rank = 8, owned = { KnockGlove1 = true, KnockGlove2 = true } } }))
		panel.setShop("ItemShop")
		tap(panel, "Tab_PvP")
		local card = UiHarness.find(panel.frame, "Ladder_Knockback")
		expect(card ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "Ladder_Trap") ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "Ladder_Blaster") ~= nil).toBe(true)
		expect(UiHarness.find(card, "LineTitle").Text).toBe("Gloves")
		expect(UiHarness.find(card, "KnockGlove3") ~= nil).toBe(true)
		local steps = UiHarness.find(card, "Steps")
		expect(steps:FindFirstChild("Step3").BackgroundColor3).toBe(Theme.Gold)
		expect(steps:FindFirstChild("Step1").BackgroundColor3).toBe(Theme.Good)
		expect(steps:FindFirstChild("Step5").BackgroundColor3).toBe(Theme.Disabled)
		expect(steps:FindFirstChild("Step5").Text).toBe("🔒5")
		UiHarness.fire(steps:FindFirstChild("Step5"), "Activated")
		card = UiHarness.find(panel.frame, "Ladder_Knockback")
		local royal = UiHarness.find(card, "KnockGlove5")
		expect(royal ~= nil).toBe(true)
		expect(string.find(royal:FindFirstChild("Status").Text, "🔒 Rebirth 20", 1, true) == 1).toBe(true)
		expect(#sent).toBe(0)
	end)

	it("Fun: a grid of tiles with a price-only Buy and rebirth-locked wells", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
		panel.update(baseState())
		panel.setShop("ItemShop")
		tap(panel, "Tab_Fun")
		local grid = UiHarness.find(panel.frame, "FunGrid")
		local confetti = grid:FindFirstChild("FunConfetti")
		expect(confetti:FindFirstChild("Buy").Visible).toBe(true)
		expect(string.find(confetti:FindFirstChild("Buy").Text, "Buy", 1, true)).toBeNil()
		local bomb = grid:FindFirstChild("FunDanceBomb")
		expect(bomb:FindFirstChild("Buy").Visible).toBe(false)
		local lockWell = bomb:FindFirstChild("Status")
		expect(lockWell.Visible).toBe(true)
		expect(string.find(lockWell.Text, "🔒 Rebirth 8", 1, true) == 1).toBe(true)
		expect(lockWell.TextColor3).toBe(Theme.Muted)
	end)

	it("a locked well grows with its text and the name column gives way", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local slot = WorldShopLogic.slot({ status = "locked", buttonText = "Rebirth 120, rank Legend" })
		local w = WorldShop.statusWidth(slot)
		expect(w >= Layout.lineWidth(slot.text, WorldShop.SIZE.status, true) + WorldShop.SIZE.statusPad * 2).toBe(true)
		expect(w > WorldShop.BUY_W).toBe(true)
		expect(WorldShop.statusWidth(WorldShopLogic.slot({ status = "owned", buttonText = "Owned" }))).toBe(
			WorldShop.BUY_W
		)
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(baseState({ pvp = { rank = 0, owned = {} } }))
		panel.setShop("ItemShop")
		local coilW = UiHarness.find(panel.frame, "SpeedCoil"):FindFirstChild("ItemName").Size.X.Offset
		tap(panel, "Tab_PvP")
		local blaster = UiHarness.find(UiHarness.find(panel.frame, "Ladder_Blaster"), "GooBlaster1")
		local want = WorldShop.statusWidth(WorldShopLogic.slot({ status = "locked", buttonText = "Rebirth 7" }))
		expect(blaster:FindFirstChild("Status").Size.X.Offset).toBe(want)
		expect(blaster:FindFirstChild("ItemName").Size.X.Offset - coilW).toBe(WorldShop.BUY_W - want)
	end)

	it("upgrade rows: grouped, now -> next text, pips up to PIP_MAX levels and a bar past it, maxed is thin", function()
		local WorldShop = UiHarness.ui("Panels/WorldShop")
		local Theme = UiHarness.ui("Widgets").Theme
		local state = baseState()
		state.upgrades[1] = upgradeEntry("Income", { level = 3, maxLevel = 25 })
		state.upgrades[2] = upgradeEntry("CarrySpeed", { level = 4, maxLevel = 4 })
		state.upgrades[5] = upgradeEntry("QuickBrew", { level = 1, maxLevel = 4 })
		local panel = WorldShop.new(UiHarness.root(), ctx())
		panel.update(state)
		panel.setShop("UpgradeShop")
		expect(UiHarness.find(panel.frame, "label_group1") ~= nil).toBe(true)
		local income = UiHarness.find(panel.frame, "Income")
		expect(income.Size.Y.Offset).toBe(WorldShop.ROW_LEVELS)
		expect(income:FindFirstChild("Description").Text).toBe("+30% → +40% income")
		expect(income:FindFirstChild("Levels")).toBeNil()
		local fill = income:FindFirstChild("LevelBar"):FindFirstChild("Fill")
		expect(math.abs(fill.Size.X.Scale - 3 / 25) < 1e-6).toBe(true)
		expect(income.BackgroundColor3).toBe(Theme.BgLight)
		expect(income:FindFirstChild("Buy").Visible).toBe(true)
		local brew = UiHarness.find(panel.frame, "QuickBrew")
		local pips = brew:FindFirstChild("Levels")
		expect(#pips:GetChildren()).toBe(4)
		local on = 0
		for _, pip in pips:GetChildren() do
			if pip.BackgroundColor3 == Theme.Gold then
				on += 1
			else
				expect(pip.BackgroundColor3).toBe(Theme.Ink)
			end
		end
		expect(on).toBe(1)
		local carry = UiHarness.find(panel.frame, "CarrySpeed")
		expect(carry.Size.Y.Offset).toBe(WorldShop.ROW_THIN)
		expect(carry:FindFirstChild("Buy").Visible).toBe(false)
		local stamp = carry:FindFirstChild("MaxStamp")
		expect(stamp.Visible).toBe(true)
		expect(stamp.Text).toBe("Max")
		expect(stamp.BackgroundColor3).toBe(Theme.Gold)
		expect(stamp.TextColor3).toBe(Theme.Ink)
		-- can't afford it: no highlight, and the Buy button is a sunken well
		local broke = table.clone(state)
		broke.cash = 1
		panel.update(broke)
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
		local function count()
			for _, inst in UiHarness.descendants(panel.frame) do
				if inst.Name == "Icon" and inst:GetAttribute("ItemId") then
					seen += 1
					expect(registry.byId[inst:GetAttribute("ItemId")] ~= nil).toBe(true)
				end
			end
		end
		for _, shopId in Shops.ORDER do
			panel.setShop(shopId)
			count()
		end
		panel.setShop("ItemShop")
		for _, t in WorldShopLogic.TABS do
			UiHarness.fire(UiHarness.find(panel.frame, `Tab_{t.id}`), "Activated")
			count()
		end
		expect(seen > 10).toBe(true)
	end)
end)

describe("init.client wiring", function()
	it("the shop prompt opens no menu from the client (the server opens the shop); Talk opens the Guide", function()
		local prompts = MenuClose.promptMenus(Constants.GUIDE_PROMPT_NAME)
		expect(prompts[Constants.SHOP_PROMPT_NAME]).toBeNil()
		expect(prompts[Constants.GUIDE_PROMPT_NAME]).toBe("Guide")
	end)

	it("the world shop card follows the one-open-menu state", function()
		local keys = { "Merge", "WorldShop", "Guide" }
		local view = MenuState.view("WorldShop", keys)
		expect(view.backdrop).toBe(true)
		expect(view.cards.WorldShop).toBe(true)
		expect(view.cards.Guide).toBe(false)
		expect(view.cards.Merge).toBe(false)
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
