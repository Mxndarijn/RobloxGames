--!strict
-- Consumables hardening (FEATURES.Consumables): restock boundaries, fresh / old / junk saves, sold out,
-- cash, bad arguments, repeats, leaving players. Asserts both modes of the frozen flag
-- (tests/FeatureFlags.spec re-runs this file flipped). Cloud-eligible: no Lune modules.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local ConsumableShop = require("../src/server/ConsumableShop")
local Consumables = require("../src/shared/Consumables")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local STEP = Config.CONSUMABLES_RESTOCK_SECONDS
local on = Config.FEATURES.Consumables == true

local function ctx(requestWeather: ((string) -> boolean)?): Actions.Context
	return {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return "pos"
		end,
		rng = Rng.new(3),
		requestWeather = requestWeather,
	}
end

local tick = 0
local function buy(world: any, userId: number, now: number, id: any, slimeId: any, c: Actions.Context?)
	tick += 1 -- BuyConsumable is rate-limited per player
	return Actions.handle(world, userId, "BuyConsumable", table.pack(id, slimeId), now + tick * 2, c or ctx(function()
		return true
	end))
end

-- Unthrottled purchase at exactly `now` (the Actions helper above shifts the clock to dodge the rate limit).
local function buyAt(world: any, userId: number, now: number, id: string): (boolean, string?)
	return ConsumableShop.buy(world, world.sessions[userId], id, nil, now, { rng = Rng.new(5), requestWeather = nil })
end

local function slotWith(id: string, n: number): number
	local slot = Consumables.slotAt(T0)
	while (Consumables.stock(slot) :: any)[id] < n do
		slot += 1
	end
	return slot
end

describe("Consumables flag", function()
	it("shows the section and sells only with the flag on; off refuses and charges nothing", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9)
		expect(Snapshot.build(world, session, T0).consumables ~= nil).toBe(on)
		local res = buy(world, 1, T0, "LuckPotion", nil)
		expect(res.ok).toBe(on)
		if not on then
			expect(res.message).toBe("the shop is closed")
			expect(session.data.cash).toBe(1e9)
			expect(session.data.consumables.slot).toBe(0)
			expect(world.potionUntil).toBe(0)
		end
	end)
	it("a potion never changes spawn luck with the flag off", function()
		expect(Consumables.spawnLuck(1, true)).toBe(
			if on then math.min(Config.SPAWN_LUCK_CAP, Config.LUCK_POTION_MULT) else 1
		)
	end)
end)

describe("Consumables restock boundaries", function()
	it("rolls the slot exactly on the restock second (float clocks too)", function()
		local k = Consumables.slotAt(T0) + 1
		local edge = k * STEP
		expect(Consumables.slotAt(edge - 0.001)).toBe(k - 1)
		expect(Consumables.slotAt(edge)).toBe(k)
		expect(Consumables.slotAt(edge + 0.999)).toBe(k)
		expect(Consumables.restockAt(edge - 0.001)).toBe(edge)
		expect(Consumables.restockAt(edge)).toBe(edge + STEP)
		expect(Consumables.secondsLeft(edge)).toBe(STEP)
		expect(Consumables.secondsLeft(edge - 1) > 0).toBe(true)
	end)
	it("tolerates a zero or fractional clock", function()
		if not on then
			expect(Consumables.view(PlayerData.new(), 0, true, 0)).toBeNil()
			return
		end
		expect(Consumables.slotAt(0)).toBe(0)
		expect(#Consumables.view(PlayerData.new(), 0, true, 0).items > 0).toBe(true)
		expect(Consumables.restockAt(0.5)).toBe(STEP)
	end)
	it("stock is the same on every call and every item is in its configured range", function()
		for slot = 0, 200 do
			local stock, weather = Consumables.stock(slot)
			local again = Consumables.stock(slot)
			expect(weather ~= "Clear").toBe(true)
			for _, def in Config.CONSUMABLES do
				expect(stock[def.id] >= def.minStock and stock[def.id] <= def.maxStock).toBe(true)
				expect(again[def.id]).toBe(stock[def.id])
			end
		end
	end)
	it("a purchase in the last second counts for that slot only; the next second is a fresh allowance", function()
		if not on then
			return
		end
		local slot = slotWith("LuckPotion", 1) + 1
		local last = (slot + 1) * STEP - 0.5
		local world = ServerFixtures.world(last)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, last)
		for _ = 1, Consumables.stock(slot).LuckPotion do
			world.potionUntil = 0
			expect((buyAt(world, 1, last, "LuckPotion"))).toBe(true)
		end
		world.potionUntil = 0
		local ok, reason = buyAt(world, 1, last, "LuckPotion")
		expect(ok).toBe(false)
		expect(reason).toBe("sold out until the restock")
		local boundary = (slot + 1) * STEP
		for _, item in Consumables.view(session.data, boundary, true, 0).items do
			expect(item.left).toBe(item.max)
		end
		session.data.cash = 1e9
		world.potionUntil = 0
		expect((buyAt(world, 1, boundary, "LuckPotion"))).toBe(true)
		expect(session.data.consumables.slot).toBe(slot + 1)
		expect(session.data.consumables.bought.LuckPotion).toBe(1)
	end)
end)

describe("Consumables saves", function()
	it("a fresh profile starts with nothing bought and a full allowance", function()
		if not on then
			return
		end
		local d = PlayerData.new()
		expect(d.consumables.slot).toBe(0)
		expect(next(d.consumables.bought)).toBeNil()
		for _, item in Consumables.view(d, T0, true, 0).items do
			expect(item.left).toBe(item.max)
		end
	end)
	it("an old save without the field, or with junk in it, loads to a usable allowance", function()
		local junk: { any } = {
			"x",
			7,
			true,
			{},
			{ bought = "x" },
			{ slot = "a", bought = { LuckPotion = "many" } },
			{ slot = -5, bought = { LuckPotion = -3, Nope = 4, MutationSpray = 1e12 } },
			{ slot = 0 / 0, bought = { LuckPotion = 0 / 0 } },
			{ slot = math.huge, bought = {} },
		}
		for i, value in junk do
			local stored = SaveData.serialize(PlayerData.new(), T0)
			stored.consumables = value
			local data = SaveData.deserialize(stored)
			expect(type(data.consumables.slot)).toBe("number")
			expect(data.consumables.slot == data.consumables.slot and data.consumables.slot >= 0).toBe(true)
			for _, def in Config.CONSUMABLES do
				local n = data.consumables.bought[def.id] or 0
				expect(n >= 0 and n <= def.maxStock).toBe(true)
			end
			expect(data.consumables.bought.Nope).toBeNil()
			-- and the loaded profile can be shown and bought from
			local world = ServerFixtures.world()
			local session = Sessions.join(world, 100 + i, "P", data, T0)
			assert(session, "join")
			Snapshot.build(world, session, T0 + 1)
			session.data.cash = 1e9
			session.lockUntil = 0
			local res = buy(world, 100 + i, T0, "LuckPotion", nil)
			expect(res.ok == on or res.message == "sold out until the restock").toBe(true)
		end
	end)
	it("a purchase survives leave and rejoin, so rejoining is no way round the allowance", function()
		if not on then
			return
		end
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		local total = Consumables.stock(slot).LuckPotion
		for _ = 1, total do
			world.potionUntil = 0
			expect(buy(world, 1, now, "LuckPotion", nil).ok).toBe(true)
		end
		local left = Sessions.leave(world, 1, now + 1)
		assert(left, "left")
		local back = SaveData.deserialize(SaveData.serialize(left.data, now + 1))
		local again = Sessions.join(world, 1, "P1", back, now + 2)
		assert(again, "rejoin")
		again.data.cash = 1e9
		world.potionUntil = 0
		local res = buy(world, 1, now + 2, "LuckPotion", nil)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("sold out until the restock")
		expect(session.data.consumables.bought.LuckPotion).toBe(total)
	end)
end)

describe("Consumables bad requests", function()
	it("rejects non-string, oversize and odd ids and charges nothing", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9)
		local bad: { any } = { 1, true, {}, "", string.rep("x", 200), "Luck Potion", "luckpotion", "Nope" }
		for _, id in bad do
			local res = buy(world, 1, T0, id, nil)
			expect(res.ok).toBe(false)
		end
		local nilId = Actions.handle(world, 1, "BuyConsumable", {}, T0 + 500, ctx(nil))
		expect(nilId.ok).toBe(false)
		expect(buy(world, 1, T0, "LuckPotion", { "x" }).ok).toBe(false) -- slimeId must be a string
		expect(session.data.cash).toBe(1e9)
		expect(next(session.data.consumables.bought)).toBeNil()
	end)
	it("refuses an unjoined or departed player", function()
		local world = ServerFixtures.world()
		expect(buy(world, 404, T0, "LuckPotion", nil).ok).toBe(false)
		ServerFixtures.join(world, 1, nil, 1e9)
		Sessions.leave(world, 1, T0 + 1)
		expect(buy(world, 1, T0 + 2, "LuckPotion", nil).ok).toBe(false)
		expect(world.potionUntil).toBe(0)
	end)
	it("a repeat inside the rate window is refused and charged once", function()
		if not on then
			return
		end
		local slot = slotWith("LuckPotion", 2)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		local c = ctx(nil)
		local first = Actions.handle(world, 1, "BuyConsumable", table.pack("LuckPotion", nil), now, c)
		local second = Actions.handle(world, 1, "BuyConsumable", table.pack("LuckPotion", nil), now + 0.1, c)
		expect(first.ok).toBe(true)
		expect(second.ok).toBe(false)
		expect(second.message).toBe("too fast")
		expect(session.data.consumables.bought.LuckPotion).toBe(1)
	end)
	it("insufficient cash and sold out are different, charge nothing and keep the allowance", function()
		if not on then
			return
		end
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 0, now)
		local price = Consumables.price(session.data, "LuckPotion") :: number
		session.data.cash = price - 1
		local res = buy(world, 1, now, "LuckPotion", nil)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("not enough cash")
		expect(session.data.cash).toBe(price - 1)
		expect(next(session.data.consumables.bought)).toBeNil()
		session.data.cash = price
		expect(buy(world, 1, now, "LuckPotion", nil).ok).toBe(true)
		expect(session.data.cash).toBe(0)
	end)
end)

describe("Consumables effects at the edges", function()
	it("a spray needs a slime, an owned slime, and not one in a thief's arms", function()
		if not on then
			return
		end
		local slot = slotWith("MutationSpray", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local owner = ServerFixtures.join(world, 1, { Fixtures.slime("mine", 3) }, 1e9, now)
		local thief = ServerFixtures.join(world, 2, nil, 1e9, now)
		ServerFixtures.unlock(owner)
		ServerFixtures.unlock(thief)
		local none = buy(world, 1, now, "MutationSpray", nil)
		expect(none.ok).toBe(false)
		expect(none.message).toBe("pick a slime")
		expect(buy(world, 1, now, "MutationSpray", "ghost").message).toBe("not your slime")
		expect((Carry.grab(world, 2, "mine", 1, now))).toBe(true)
		local busy = buy(world, 1, now, "MutationSpray", "mine")
		expect(busy.ok).toBe(false)
		expect(busy.message).toBe("slime is busy")
		expect(owner.data.cash).toBe(1e9)
		expect(next(owner.data.consumables.bought)).toBeNil()
		expect(thief.data.cash).toBe(1e9)
	end)
	it("a second potion in the cap window is refused for free", function()
		if not on then
			return
		end
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		world.potionUntil = now + Config.LUCK_POTION_MAX_SECONDS
		local ok = buyAt(world, 1, now, "LuckPotion")
		expect(ok).toBe(false)
		expect(session.data.cash).toBe(1e9)
		expect(world.potionUntil).toBe(now + Config.LUCK_POTION_MAX_SECONDS)
	end)
	it("an expired potion neither shows nor boosts", function()
		if not on then
			return
		end
		expect(Consumables.view(PlayerData.new(), T0, true, T0 - 1).luckUntil or 0).toBe(0)
		expect(Consumables.spawnLuck(1.5, false)).toBe(1.5)
		expect(Consumables.extendPotion(T0 - 99999, T0)).toBe(T0 + Config.LUCK_POTION_SECONDS)
		expect(Consumables.potionFull(T0 - 1, T0)).toBe(false)
	end)
end)
