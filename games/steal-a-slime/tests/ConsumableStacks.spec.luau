--!strict
-- S3 consumable stacks (contract/restocking-shop.md): buying adds to a held stack, the stack is saved with the
-- consumables field (old saves load with nothing held), UseConsumable runs the existing effect code and takes one
-- off the stack, and the Speed Coil is an Item Shop item (decision A).
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Consumables = require("../src/shared/Consumables")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Shops = require("../src/shared/Shops")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local STEP = Config.CONSUMABLES_RESTOCK_SECONDS

local function slotWith(id: string, n: number): number
	local slot = Consumables.slotAt(T0)
	while (Consumables.stock(slot) :: any)[id] < n do
		slot += 1
	end
	return slot
end

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
local function call(world: any, userId: number, action: string, now: number, ...: any)
	tick += 1 -- both actions are rate-limited per player
	return Actions.handle(
		world,
		userId,
		action,
		table.pack(...),
		now + tick * 2,
		ctx(function()
			return true
		end)
	)
end

describe("Consumable stacks", function()
	it("buying adds one to the held stack and applies nothing", function()
		local slot = slotWith("LuckPotion", 2)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		expect(call(world, 1, "BuyConsumable", now, "LuckPotion").ok).toBe(true)
		expect(call(world, 1, "BuyConsumable", now, "LuckPotion").ok).toBe(true)
		expect(session.data.consumables.held.LuckPotion).toBe(2)
		expect(session.data.consumables.bought.LuckPotion).toBe(2)
		expect(world.potionUntil).toBe(0)
		-- the snapshot carries the stack (State.consumables.held and each item's `held`)
		local view = Snapshot.build(world, session, now).consumables :: any
		expect(view.held.LuckPotion).toBe(2)
		for _, item in view.items do
			expect(item.held).toBe(session.data.consumables.held[item.id] or 0)
		end
	end)

	it("the stack outlives the restock: a new slot resets what may be bought, not what is held", function()
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		expect(call(world, 1, "BuyConsumable", now, "LuckPotion").ok).toBe(true)
		local later = slot + 1
		while (Consumables.stock(later) :: any).LuckPotion < 1 do
			later += 1
		end
		expect(call(world, 1, "BuyConsumable", later * STEP + 1, "LuckPotion").ok).toBe(true)
		expect(session.data.consumables.slot).toBe(later)
		expect(session.data.consumables.bought.LuckPotion).toBe(1)
		expect(session.data.consumables.held.LuckPotion).toBe(2)
	end)

	it("refuses a purchase past the held cap, and charges nothing", function()
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		session.data.consumables.held.LuckPotion = Config.CONSUMABLE_HELD_MAX
		local res = call(world, 1, "BuyConsumable", now, "LuckPotion")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("you can't hold more of these")
		expect(session.data.cash).toBe(1e9)
	end)
end)

describe("Consumable stack saves", function()
	it("round-trips the stack with the consumables field", function()
		local d = Fixtures.data()
		d.consumables.held = { LuckPotion = 4, MutationSpray = 1 }
		Consumables.record(d, 12, "LuckPotion")
		local back = SaveData.deserialize(SaveData.serialize(d, T0))
		expect(back.consumables.held.LuckPotion).toBe(4)
		expect(back.consumables.held.MutationSpray).toBeNil() -- a removed item id is dropped
		expect(back.consumables.bought.LuckPotion).toBe(1)
		expect(back.consumables.slot).toBe(12)
	end)

	it("migrates an old save (bought counts, no `held`) without losing any count", function()
		local stored = SaveData.serialize(PlayerData.new(), T0)
		stored.consumables = { slot = 77, bought = { LuckPotion = 2, MutationSpray = 1 } }
		local data = SaveData.deserialize(stored)
		expect(data.consumables.slot).toBe(77)
		expect(data.consumables.bought.LuckPotion).toBe(2)
		expect(data.consumables.bought.MutationSpray).toBeNil()
		expect(next(data.consumables.held)).toBeNil() -- those were applied when bought: nothing to hold
		-- and it saves again in the new shape
		local again = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(again.consumables.bought.LuckPotion).toBe(2)
		expect(again.consumables.held).toEqual({})
	end)

	it("an old save with no consumables field at all loads empty; junk stacks are clamped and dropped", function()
		local stored = SaveData.serialize(PlayerData.new(), T0)
		stored.consumables = nil
		expect(next(SaveData.deserialize(stored).consumables.held)).toBeNil()
		stored.consumables = {
			slot = 3,
			bought = "x",
			held = { LuckPotion = 1e9, MutationSpray = -4, WeatherTotem = 0 / 0, Nope = 5 },
		}
		local data = SaveData.deserialize(stored)
		expect(data.consumables.held.LuckPotion).toBe(Config.CONSUMABLE_HELD_MAX)
		expect(data.consumables.held.MutationSpray).toBeNil()
		expect(data.consumables.held.WeatherTotem).toBeNil()
		expect(data.consumables.held.Nope).toBeNil()
		expect(data.consumables.slot).toBe(3)
		stored.consumables = { held = "many" }
		expect(next(SaveData.deserialize(stored).consumables.held)).toBeNil()
	end)

	it("a stack survives a save and load", function()
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		Consumables.addHeld(session.data, "LuckPotion")
		local back = SaveData.deserialize(SaveData.serialize(session.data, now + 1))
		expect(back.consumables.held.LuckPotion).toBe(1)
	end)
end)

describe("UseConsumable", function()
	it("runs the potion effect and takes exactly one off the stack", function()
		local now = slotWith("LuckPotion", 1) * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		session.data.consumables.held.LuckPotion = 2
		local cash = session.data.cash
		expect(call(world, 1, "UseConsumable", now, "LuckPotion").ok).toBe(true)
		expect(world.potionUntil >= now + Config.LUCK_POTION_SECONDS).toBe(true)
		expect(session.data.consumables.held.LuckPotion).toBe(1)
		expect(session.data.cash).toBe(cash) -- using costs nothing
		expect(call(world, 1, "UseConsumable", now, "LuckPotion").ok).toBe(true)
		expect(session.data.consumables.held.LuckPotion).toBeNil() -- the last one removes the entry
	end)

	it("validates ownership: nothing held, unknown or malformed ids change nothing", function()
		local now = slotWith("LuckPotion", 1) * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		local res = call(world, 1, "UseConsumable", now, "LuckPotion")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("you don't have any")
		expect(world.potionUntil).toBe(0)
		expect(call(world, 1, "UseConsumable", now, "Nope").message).toBe("unknown item")
		expect(call(world, 1, "UseConsumable", now, 5).ok).toBe(false)
		expect(call(world, 1, "UseConsumable", now).ok).toBe(false)
		-- another player's stack is no use to this one
		local other = ServerFixtures.join(world, 2, { Fixtures.slime("b", 2) }, 1e9, now)
		other.data.consumables.held.LuckPotion = 3
		expect(call(world, 1, "UseConsumable", now, "LuckPotion").ok).toBe(false)
		expect(other.data.consumables.held.LuckPotion).toBe(3)
		expect(session.data.consumables.held.LuckPotion).toBeNil()
	end)

	it("a refused effect keeps the stack, a repeat inside the rate window is refused", function()
		local now = slotWith("LuckPotion", 1) * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		session.data.consumables.held.LuckPotion = 2
		local c = ctx(nil)
		local later = now + 1000
		local first = Actions.handle(world, 1, "UseConsumable", { "LuckPotion" }, later, c)
		local second = Actions.handle(world, 1, "UseConsumable", { "LuckPotion" }, later + 0.1, c)
		expect(first.ok).toBe(true)
		expect(second.message).toBe("too fast")
		expect(session.data.consumables.held.LuckPotion).toBe(1)
	end)

	it("the weather totem asks for the weather and only then spends the stack", function()
		local slot = slotWith("WeatherTotem", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		session.data.consumables.held.WeatherTotem = 1
		local asked: string? = nil
		tick += 1
		local refused = Actions.handle(
			world,
			1,
			"UseConsumable",
			{ "WeatherTotem" },
			now + tick * 2,
			ctx(function()
				return false
			end)
		)
		expect(refused.ok).toBe(false)
		expect(session.data.consumables.held.WeatherTotem).toBe(1)
		tick += 1
		local done = Actions.handle(
			world,
			1,
			"UseConsumable",
			{ "WeatherTotem" },
			now + tick * 2,
			ctx(function(id)
				asked = id
				return true
			end)
		)
		expect(done.ok).toBe(true)
		expect(asked).toBe((select(2, Consumables.stock(slot))))
		expect(session.data.consumables.held.WeatherTotem).toBeNil()
	end)
end)

describe("Speed Coil is an Item (decision A)", function()
	it("sits in the Item Shop", function()
		expect(Shops.shopOf("SpeedCoil")).toBe("ItemShop")
		expect(Shops.shopOfAction("BuySpeedCoil")).toBe("ItemShop")
	end)
end)
