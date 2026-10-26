--!strict
-- World shops (CONTRACT.md §27): the Shops catalogue, ShopGuard (pure validation, range, deny codes) and the
-- OpenShop / CloseShop / ShopBuy actions delegating to the existing buy handlers.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Remotes = require("../src/shared/Remotes")
local ServerFixtures = require("./ServerFixtures")
local ShopGuard = require("../src/server/ShopGuard")
local Shops = require("../src/shared/Shops")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local RANGE = Config.SHOP_RANGE

describe("Shops catalogue", function()
	it("splits the items as the contract does", function()
		local ids = function(shopId: string): { string }
			local out = {}
			for _, row in (Shops.shop(shopId) :: any).items do
				table.insert(out, row.id)
			end
			return out
		end
		local item = ids("ItemShop")
		for _, id in { "SpeedCoil", "LuckPotion", "WeatherTotem" } do
			expect(table.find(item, id) ~= nil).toBe(true)
		end
		for _, tool in Config.PVP_TOOLS do
			expect(table.find(item, tool.id) ~= nil).toBe(true)
		end
		local upgrade = ids("UpgradeShop")
		for _, def in Config.UPGRADES do
			expect(table.find(upgrade, def.id) ~= nil).toBe(true)
		end
		expect(#upgrade).toBe(#Config.UPGRADES)
		expect(item[1]).toBe("SpeedCoil")
		-- Locks are bought on the plot, never in a shop; there is no lock-length upgrade.
		for _, id in { "Lock", "LockUpgrade" } do
			expect(table.find(item, id)).toBeNil()
			expect(table.find(upgrade, id)).toBeNil()
		end
		expect(table.find(upgrade, "SpeedCoil")).toBeNil() -- an item (held in the hand), not an upgrade
		for _, id in item do
			expect(table.find(upgrade, id)).toBeNil()
		end
	end)
	it("finds the shop of an item and of an action", function()
		expect(Shops.shopOf("Lock")).toBeNil()
		expect(Shops.find("ItemShop", "Lock")).toBeNil()
		expect(Shops.shopOfAction("Lock")).toBeNil()
		expect(Shops.shopOfAction("BuyUpgrade")).toBe("UpgradeShop")
		expect(Shops.shopOf("Luck")).toBe("UpgradeShop")
		expect(Shops.shopOf("Nope")).toBeNil()
		expect(Shops.shopOfAction("BuySpeedCoil")).toBe("ItemShop")
		expect(Shops.shopOf("SpeedCoil")).toBe("ItemShop")
		expect(Shops.shopOfAction("Sell")).toBeNil()
	end)
	it("filters items by feature flags", function()
		local function has(list: { Shops.Item }, id: string): boolean
			for _, row in list do
				if row.id == id then
					return true
				end
			end
			return false
		end
		local on = Shops.items("ItemShop", { Consumables = false, PvP = true })
		expect(has(on, "SpeedCoil")).toBe(true)
		expect(has(on, "LuckPotion")).toBe(false)
		expect(has(on, Config.PVP_TOOLS[1].id)).toBe(true)
		local off = Shops.items("ItemShop", {})
		expect(has(off, "Lock")).toBe(false)
		expect(has(off, "SpeedCoil")).toBe(true)
		expect(has(Shops.items("ItemShop", { Consumables = true }), "LuckPotion")).toBe(true)
		expect(#Shops.items("Nope", {})).toBe(0)
	end)
	it("every item names a real Request action", function()
		for _, shopId in Shops.ORDER do
			for _, row in (Shops.shop(shopId) :: any).items do
				expect(Remotes.ACTIONS[row.action] ~= nil).toBe(true)
			end
		end
	end)
end)

describe("ShopGuard range", function()
	it("is in range at exactly SHOP_RANGE and out just beyond", function()
		expect(RANGE).toBe(14)
		expect(ShopGuard.inRange(RANGE)).toBe(true)
		expect(ShopGuard.inRange(RANGE + 0.001)).toBe(false)
		expect(ShopGuard.inRange(0)).toBe(true)
	end)
	it("a missing character, a missing stand or a NaN distance is out of range", function()
		expect(ShopGuard.inRange(nil)).toBe(false)
		expect(ShopGuard.inRange(0 / 0)).toBe(false)
		expect(ShopGuard.inRange(math.huge)).toBe(false)
		expect(ShopGuard.access(nil)).toBe("OutOfRange")
		expect(ShopGuard.access({ distance = nil, alive = true })).toBe("OutOfRange")
	end)
	it("a dead character is Dead before range", function()
		expect(ShopGuard.access({ distance = 1, alive = false })).toBe("Dead")
		expect(ShopGuard.access({ distance = 100, alive = false })).toBe("Dead")
		expect(ShopGuard.access({ distance = RANGE, alive = true })).toBeNil()
	end)
	it("closes an open shop for range or death, and stays open otherwise", function()
		local near = { distance = 3, alive = true }
		expect(ShopGuard.closeReason(nil, nil)).toBeNil()
		expect(ShopGuard.closeReason("ItemShop", near)).toBeNil()
		expect(ShopGuard.closeReason("ItemShop", { distance = RANGE, alive = true })).toBeNil()
		expect(ShopGuard.closeReason("ItemShop", { distance = RANGE + 1, alive = true })).toBe("range")
		expect(ShopGuard.closeReason("ItemShop", nil)).toBe("range")
		expect(ShopGuard.closeReason("ItemShop", { distance = 3, alive = false })).toBe("dead")
	end)
end)

describe("ShopGuard validation order", function()
	local near = { distance = 3, alive = true }
	local function check(over: { [string]: any }): string?
		local c = {
			shopId = "ItemShop",
			itemId = "SpeedCoil",
			openShop = "ItemShop",
			access = near,
		}
		for k, v in over do
			(c :: any)[k] = v
		end
		return ShopGuard.check(c :: any)
	end
	it("passes a valid purchase", function()
		expect(check({})).toBeNil()
	end)
	it("shop id, membership, open, alive, range in that order", function()
		local dead = { distance = 99, alive = false }
		expect(check({ shopId = "Nope", itemId = "Zzz" })).toBe("BadShop")
		expect(check({ shopId = 5 })).toBe("BadShop")
		expect(check({ itemId = "Lock", openShop = "UpgradeShop", access = dead })).toBe("NotInShop")
		expect(check({ itemId = "Income", openShop = "UpgradeShop", access = dead })).toBe("NotInShop")
		expect(ShopGuard.check({ shopId = "ItemShop", itemId = "SpeedCoil", access = dead })).toBe("NotOpen")
		expect(check({ openShop = "UpgradeShop", access = dead })).toBe("NotOpen")
		expect(check({ access = dead })).toBe("Dead")
		expect(check({ access = { distance = RANGE + 1, alive = true } })).toBe("OutOfRange")
		expect(check({})).toBeNil()
	end)
	it("OpenShop (no item) needs only the shop and range", function()
		local open: ShopGuard.Check = { shopId = "ItemShop", openShop = nil, access = near }
		expect(ShopGuard.check(open)).toBeNil()
		open.access = nil
		expect(ShopGuard.check(open)).toBe("OutOfRange")
	end)
	it("maps delegated refusals to deny codes", function()
		local cases = {
			["not enough cash"] = "NoCash",
			["lock is already at max"] = "Maxed",
			["already maxed"] = "Maxed",
			["you already own the Speed Coil"] = "Maxed",
			["locked: reach 5 rebirths"] = "Locked",
			["needs 3 rebirths"] = "Locked",
			["PvP is not open yet"] = "Locked",
			["sold out until the restock"] = "SoldOut",
			["already owned"] = "Owned",
			["pick a slime"] = "BadTarget",
			["not your slime"] = "BadTarget",
			["slime is busy"] = "BadTarget",
			["too fast"] = "Busy",
			["plot full"] = "Unavailable",
			["the shop is closed"] = "Unavailable",
		}
		for text, code in cases do
			expect(`{text} -> {ShopGuard.classify(text)}`).toBe(`{text} -> {code}`)
		end
		expect(ShopGuard.classify(nil)).toBe("Unavailable")
	end)
end)

-- A world with one player and a scripted stand: `access` is what the adapter would measure.
local function setup(cash: number?)
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, nil, cash or 10_000_000)
	local env = {
		world = world,
		session = session,
		access = { distance = 3, alive = true } :: ShopGuard.Access,
		events = {} :: { { [string]: any } },
		ctx = {} :: Actions.Context,
	}
	env.ctx = {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return nil
		end,
		shopAccess = function()
			return env.access
		end,
		shopEvent = function(_userId, payload)
			table.insert(env.events, payload)
		end,
	}
	return env
end

local function call(env: any, action: string, ...: any)
	env.session.limiter = {}
	return Actions.handle(env.world, 1, action, table.pack(...), T0 + 100, env.ctx)
end

-- ShopBuy with that shop open (ShopBuy needs the matching shop open, NotOpen otherwise).
local function buy(env: any, shopId: string, itemId: string, ...: any)
	env.session.openShop = shopId
	return call(env, "ShopBuy", shopId, itemId, ...)
end

local function lastEvent(env: any): { [string]: any }
	return env.events[#env.events]
end

describe("Request OpenShop / CloseShop", function()
	it("declares the actions, rate limits and the ShopEvent remote", function()
		for _, action in { "OpenShop", "CloseShop", "ShopBuy" } do
			expect(Remotes.ACTIONS[action] ~= nil).toBe(true)
			expect(Validate.ACTIONS[action]).toBe(0.5)
		end
		local def = Remotes.definition(Constants.SHOP_EVENT)
		expect(def and def.class).toBe("RemoteEvent")
		expect(def and def.direction).toBe("ServerToClient")
		expect(Constants.SHOP_EVENT).toBe("ShopEvent")
	end)
	it("opens in range, remembers the shop and fires Open", function()
		local env = setup()
		local res = call(env, "OpenShop", "ItemShop")
		expect(res.ok).toBe(true)
		expect(env.session.openShop).toBe("ItemShop")
		expect(lastEvent(env).kind).toBe("Open")
		expect(lastEvent(env).shopId).toBe("ItemShop")
	end)
	it("CloseShop clears it and fires Close(closed)", function()
		local env = setup()
		call(env, "OpenShop", "UpgradeShop")
		expect(call(env, "CloseShop").ok).toBe(true)
		expect(env.session.openShop).toBeNil()
		expect(lastEvent(env).kind).toBe("Close")
		expect(lastEvent(env).reason).toBe("closed")
	end)
	it("denies a bad shop, out of range, no character and a dead character", function()
		local env = setup()
		local res = call(env, "OpenShop", "NoSuchShop")
		expect(res.ok).toBe(false)
		expect(res.code).toBe("BadShop")
		expect(lastEvent(env).kind).toBe("Denied")
		expect(lastEvent(env).code).toBe("BadShop")
		env.access = { distance = RANGE + 0.5, alive = true }
		expect(call(env, "OpenShop", "ItemShop").code).toBe("OutOfRange")
		env.access = { distance = RANGE, alive = true }
		expect(call(env, "OpenShop", "ItemShop").ok).toBe(true)
		env.access = { distance = nil, alive = true }
		expect(call(env, "OpenShop", "ItemShop").code).toBe("OutOfRange")
		env.access = { distance = 2, alive = false }
		expect(call(env, "OpenShop", "ItemShop").code).toBe("Dead")
		expect(call(env, "OpenShop", "ItemShop").message).toBe(ShopGuard.MESSAGES.Dead)
	end)
	it("validates the shopId argument as a string", function()
		local env = setup()
		expect(call(env, "OpenShop", 5).ok).toBe(false)
		expect(call(env, "OpenShop").ok).toBe(false)
	end)
	it("shopTick closes on range and death with the contract reasons, and leaves a shop in range open", function()
		local env = setup()
		call(env, "OpenShop", "ItemShop")
		Actions.shopTick(env.session, env.ctx)
		expect(env.session.openShop).toBe("ItemShop")
		env.access = { distance = RANGE + 5, alive = true }
		Actions.shopTick(env.session, env.ctx)
		expect(env.session.openShop).toBeNil()
		expect(lastEvent(env)).toEqual({ kind = "Close", shopId = "ItemShop", reason = "range" })
		env.access = { distance = 1, alive = true }
		call(env, "OpenShop", "ItemShop")
		env.access = { distance = 1, alive = false }
		Actions.shopTick(env.session, env.ctx)
		expect(lastEvent(env).reason).toBe("dead")
	end)
	it("the prompt opens the shop on the server without the OpenShop rate limit", function()
		local env = setup()
		env.session.limiter = { OpenShop = T0 + 100 }
		local res = Actions.openFromPrompt(env.world, 1, "UpgradeShop", env.ctx)
		expect(res.ok).toBe(true)
		expect(env.session.openShop).toBe("UpgradeShop")
		env.access = { distance = RANGE + 1, alive = true }
		expect(Actions.openFromPrompt(env.world, 1, "ItemShop", env.ctx).code).toBe("OutOfRange")
		expect(Actions.openFromPrompt(env.world, 99, "ItemShop", env.ctx).ok).toBe(false)
	end)
end)

describe("Request ShopBuy", function()
	it("delegates to the existing handler and fires Purchased with price and level", function()
		local env = setup()
		local before = env.session.data.cash
		local res = buy(env, "UpgradeShop", "Income")
		expect(res.ok).toBe(true)
		expect(env.session.data.upgrades.Income).toBe(1)
		local event = lastEvent(env)
		expect(event.kind).toBe("Purchased")
		expect(event.shopId).toBe("UpgradeShop")
		expect(event.itemId).toBe("Income")
		expect(event.price).toBe(before - env.session.data.cash)
		expect(event.price > 0).toBe(true)
		expect(event.level).toBe(1)
		expect(buy(env, "UpgradeShop", "Income").ok).toBe(true)
		expect(env.session.data.upgrades.Income).toBe(2)
		expect(lastEvent(env).level).toBe(2)
	end)
	it("buys the Speed Coil once, then answers Maxed", function()
		local env = setup()
		expect(buy(env, "ItemShop", "SpeedCoil").ok).toBe(true)
		expect(env.session.data.speedCoil).toBe(true)
		expect(lastEvent(env).level).toBeNil()
		local res = buy(env, "ItemShop", "SpeedCoil")
		expect(res.ok).toBe(false)
		expect(res.code).toBe("Maxed")
		expect(res.message).toBe("you already own the Speed Coil")
		expect(lastEvent(env).kind).toBe("Denied")
		expect(lastEvent(env).message).toBe("you already own the Speed Coil")
	end)
	it("does not sell locks: ShopBuy Lock is NotInShop and charges nothing", function()
		local env = setup()
		env.session.lockUntil = 0
		local before = env.session.data.cash
		for _, shopId in { "ItemShop", "UpgradeShop" } do
			local res = buy(env, shopId, "Lock")
			expect(res.ok).toBe(false)
			expect(res.code).toBe("NotInShop")
		end
		expect(buy(env, "UpgradeShop", "LockUpgrade").code).toBe("NotInShop")
		expect(env.session.lockUntil).toBe(0)
		expect(env.session.data.cash).toBe(before)
	end)
	it("maps delegated failures: NoCash, Locked", function()
		local env = setup(0)
		expect(buy(env, "ItemShop", "SpeedCoil").code).toBe("NoCash")
		local poor = lastEvent(env)
		expect(poor.code).toBe("NoCash")
		expect(poor.itemId).toBe("SpeedCoil")
		expect(poor.message).toBe("not enough cash")
		env.session.data.cash = 10_000_000
		local res = buy(env, "UpgradeShop", "Luck")
		expect(res.ok).toBe(false)
		expect(res.code).toBe("Locked")
		expect(env.session.data.cash).toBe(10_000_000)
	end)
	it("maxed upgrades are refused with the Maxed code", function()
		local env = setup()
		expect(Config.UPGRADES[1].id).toBe("Income")
		env.session.data.rebirths = Config.MAX_REBIRTHS
		env.session.data.upgrades.Income = Config.UPGRADES[1].maxLevel
		expect(buy(env, "UpgradeShop", "Income").code).toBe("Maxed")
	end)
	it("rejects an item the shop does not sell and an unknown shop", function()
		local env = setup()
		local res = buy(env, "UpgradeShop", "SpeedCoil")
		expect(res.code).toBe("NotInShop") -- the Speed Coil is an Item Shop row now
		expect(env.session.data.speedCoil).toBe(false)
		expect(buy(env, "UpgradeShop", "Lock").code).toBe("NotInShop")
		expect(buy(env, "Nope", "Lock").code).toBe("BadShop")
		expect(buy(env, "ItemShop", "NoSuchItem").code).toBe("NotInShop")
	end)
	it("range is checked on every purchase: boundary, no character, dead", function()
		local env = setup()
		env.access = { distance = RANGE, alive = true }
		expect(buy(env, "UpgradeShop", "Income").ok).toBe(true)
		env.access = { distance = RANGE + 0.01, alive = true }
		local before = env.session.data.cash
		expect(buy(env, "UpgradeShop", "Income").code).toBe("OutOfRange")
		env.access = { distance = nil, alive = true }
		expect(buy(env, "UpgradeShop", "Income").code).toBe("OutOfRange")
		env.access = { distance = 1, alive = false }
		expect(buy(env, "UpgradeShop", "Income").code).toBe("Dead")
		expect(env.session.data.cash).toBe(before)
		expect(env.session.data.upgrades.Income).toBe(1)
	end)
	it("no shopAccess in the context means no stand: out of range", function()
		local env = setup()
		env.ctx.shopAccess = nil
		expect(buy(env, "UpgradeShop", "Income").code).toBe("OutOfRange")
	end)
	it("keeps the delegated action's own rate limit (Busy)", function()
		local env = setup()
		env.session.limiter = { BuyUpgrade = T0 + 100 }
		env.session.openShop = "UpgradeShop"
		local res = Actions.handle(env.world, 1, "ShopBuy", { "UpgradeShop", "Income" }, T0 + 100.1, env.ctx)
		expect(res.ok).toBe(false)
		expect(res.code).toBe("Busy")
		expect(env.session.data.upgrades.Income or 0).toBe(0)
	end)
	it("ShopBuy itself is rate limited", function()
		local env = setup()
		env.session.openShop = "UpgradeShop"
		expect(Actions.handle(env.world, 1, "ShopBuy", { "UpgradeShop", "Income" }, T0 + 100, env.ctx).ok).toBe(true)
		local again = Actions.handle(env.world, 1, "ShopBuy", { "UpgradeShop", "Income" }, T0 + 100.1, env.ctx)
		expect(again.ok).toBe(false)
		expect(again.message).toBe("too fast")
	end)
	it("a consumable is bought without a slime", function()
		local env = setup()
		local res = buy(env, "ItemShop", "LuckPotion")
		if Config.FEATURES.Consumables then
			expect(res.ok or res.code == "SoldOut").toBe(true)
			expect(res.code ~= "BadTarget").toBe(true)
		else
			expect(res.ok).toBe(false)
			expect(res.code).toBe("Unavailable")
		end
	end)
end)

describe("shop gate", function()
	it("ShopBuy needs the matching shop open (NotOpen), then works in range", function()
		local env = setup()
		local res = call(env, "ShopBuy", "UpgradeShop", "Income")
		expect(res.code).toBe("NotOpen")
		call(env, "OpenShop", "ItemShop")
		expect(call(env, "ShopBuy", "UpgradeShop", "Income").code).toBe("NotOpen")
		call(env, "OpenShop", "UpgradeShop")
		expect(call(env, "ShopBuy", "UpgradeShop", "Income").ok).toBe(true)
		env.access = { distance = RANGE + 1, alive = true }
		expect(call(env, "ShopBuy", "UpgradeShop", "Income").code).toBe("OutOfRange")
	end)
	it("the old buy actions answer 'open the <Item|Upgrade> Shop first' until the right shop is open", function()
		local env = setup()
		local res = call(env, "BuyUpgrade", "Income")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("open the Upgrade Shop first")
		expect(res.code).toBe("NotOpen")
		expect(call(env, "BuySpeedCoil").message).toBe("open the Item Shop first")
		expect(env.session.data.upgrades.Income or 0).toBe(0)
		call(env, "OpenShop", "UpgradeShop")
		expect(call(env, "BuyUpgrade", "Income").ok).toBe(true)
		expect(call(env, "BuySpeedCoil").code).toBe("NotOpen") -- the Speed Coil is an Item Shop thing
		call(env, "OpenShop", "ItemShop")
		env.access = { distance = RANGE + 1, alive = true }
		expect(call(env, "BuySpeedCoil").code).toBe("OutOfRange")
		expect(call(env, "Sell", "nope").code).toBeNil() -- other actions are never gated
	end)
	it("Lock never needs a shop (without a measured plot pad it is not gated)", function()
		local env = setup()
		env.access = { distance = 999, alive = true }
		env.session.lockUntil = 0
		local res = call(env, "Lock")
		expect(res.ok).toBe(true)
		expect(env.session.lockUntil > T0 + 100).toBe(true)
	end)
	it("does not gate the old buy actions where the adapter measures nothing (no shopAccess)", function()
		local env = setup()
		env.ctx.shopAccess = nil
		expect(call(env, "BuyUpgrade", "Income").ok).toBe(true)
	end)
end)
