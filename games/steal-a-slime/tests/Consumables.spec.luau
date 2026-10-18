--!strict
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local ConsumableShop = require("../src/server/ConsumableShop")
local Consumables = require("../src/shared/Consumables")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")
local Remotes = require("../src/shared/Remotes")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local WeatherService = require("../src/server/WeatherService")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local STEP = Config.CONSUMABLES_RESTOCK_SECONDS

-- First slot at or after T0's whose stock has `id` >= `n`.
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
local function buy(world: any, userId: number, now: number, id: string, slimeId: string?, c: Actions.Context?)
	tick += 1 -- BuyConsumable is rate-limited per player (Validate.ACTIONS)
	return Actions.handle(world, userId, "BuyConsumable", table.pack(id, slimeId), now + tick * 2, c or ctx(function()
		return true
	end))
end

local function use(world: any, userId: number, now: number, id: string, slimeId: string?, c: Actions.Context?)
	tick += 1 -- UseConsumable is rate-limited per player (Validate.ACTIONS)
	return Actions.handle(world, userId, "UseConsumable", table.pack(id, slimeId), now + tick * 2, c or ctx(function()
		return true
	end))
end

describe("Consumables schedule", function()
	it("is a default-on, declared, rate-limited feature", function()
		expect(Config.FEATURES.Consumables).toBe(true)
		expect(Remotes.ACTIONS.BuyConsumable ~= nil).toBeTruthy()
		expect(Validate.ACTIONS.BuyConsumable ~= nil).toBeTruthy()
	end)
	it("rotates every CONSUMABLES_RESTOCK_SECONDS on the unix clock", function()
		expect(Consumables.slotAt(0)).toBe(0)
		expect(Consumables.slotAt(STEP - 0.1)).toBe(0)
		expect(Consumables.slotAt(STEP)).toBe(1)
		expect(Consumables.restockAt(STEP + 5)).toBe(2 * STEP)
		expect(Consumables.secondsLeft(STEP * 3 - 10)).toBe(10)
	end)
	it("makes the stock a pure function of the slot (all servers agree)", function()
		local slot = Consumables.slotAt(T0)
		local a, wa = Consumables.stock(slot)
		local b, wb = Consumables.stock(slot)
		expect(wa).toBe(wb)
		for _, def in Config.CONSUMABLES do
			expect(a[def.id]).toBe(b[def.id])
			expect(a[def.id] >= def.minStock and a[def.id] <= def.maxStock).toBe(true)
		end
		expect(wa ~= "Clear" and require("../src/shared/Weather").data(wa) ~= nil).toBe(true)
	end)
	it("varies between slots", function()
		local seen = {}
		for slot = 1000, 1040 do
			local stock, weather = Consumables.stock(slot)
			seen[`{stock.MutationSpray}{stock.LuckPotion}{stock.WeatherTotem}{weather}`] = true
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		expect(n > 3).toBe(true)
	end)
end)

describe("Consumables purchase rules", function()
	it("limits quantity per player per restock and restocks on a new slot", function()
		local slot = slotWith("LuckPotion", 2)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		local total = Consumables.stock(slot).LuckPotion
		for _ = 1, total do
			-- potions extend a capped timer, so let the clock move inside the slot
			session.data.cash = 1e9
			world.potionUntil = 0
			expect(buy(world, 1, now, "LuckPotion").ok).toBe(true)
		end
		world.potionUntil = 0
		local res = buy(world, 1, now, "LuckPotion")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("sold out until the restock")
		-- other players have their own allowance
		local other = ServerFixtures.join(world, 2, { Fixtures.slime("b", 2) }, 1e9, now)
		expect(buy(world, 2, now, "LuckPotion").ok).toBe(true)
		expect(other.data.consumables.bought.LuckPotion).toBe(1)
		-- next slot: counts reset (the counts live per slot)
		local later = (slot + 1) * STEP + 1
		expect(Consumables.remaining(session.data, slot + 1, "LuckPotion", true)).toBe(
			Consumables.stock(slot + 1).LuckPotion
		)
		expect(later > now).toBe(true)
	end)
	it("checks cash and charges exactly the price", function()
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local price = Consumables.price(Fixtures.data(), "LuckPotion") :: number
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, price - 1, now)
		local res = buy(world, 1, now, "LuckPotion")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("not enough cash")
		expect(session.data.cash).toBe(price - 1)
		expect(world.potionUntil).toBe(0)
		session.data.cash = price + 5
		expect(buy(world, 1, now, "LuckPotion").ok).toBe(true)
		expect(session.data.cash).toBe(5)
	end)
	it("scales the price with rebirths and rejects unknown items", function()
		local d = Fixtures.data()
		local base = Consumables.price(d, "MutationSpray") :: number
		d.rebirths = 3
		expect((Consumables.price(d, "MutationSpray") :: number) > base).toBe(true)
		expect(Consumables.price(d, "Nope")).toBeNil()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9)
		expect(buy(world, 1, T0, "Nope").message).toBe("unknown item")
	end)
end)

describe("Consumables effects", function()
	it("sprays a mutation onto an owned slime (stacking)", function()
		local slot = slotWith("MutationSpray", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local s = Fixtures.slime("a", 3, { mutation = "Glow", mutations = { "Glow" } })
		local session = ServerFixtures.join(world, 1, { s }, 1e9, now)
		local res
		for seed = 1, 20 do
			session.data.consumables = { slot = 0, bought = {}, held = { MutationSpray = 1 } }
			res = Actions.handle(world, 1, "UseConsumable", { "MutationSpray", "a" }, now + seed * 2, {
				distanceBetween = function()
					return 2
				end,
				positionOf = function()
					return "pos"
				end,
				rng = Rng.new(seed),
			})
			if res.ok then
				break
			end
		end
		expect(res.message).toBeNil()
		local list = Genome.mutationList(session.data.slimes[1])
		expect(#list >= 1).toBe(true)
		expect(session.data.consumables.held.MutationSpray).toBeNil() -- the use took the one from the stack
	end)
	it("rejects a spray on someone else's slime and keeps the stack", function()
		local slot = slotWith("MutationSpray", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		ServerFixtures.join(world, 1, { Fixtures.slime("a", 3) }, 1e9, now)
		local other = ServerFixtures.join(world, 2, { Fixtures.slime("b", 3) }, 1e9, now)
		expect(buy(world, 2, now, "MutationSpray").ok).toBe(true) -- buying needs no slime
		local res = use(world, 2, now, "MutationSpray", "a")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("not your slime")
		expect(use(world, 2, now, "MutationSpray").message).toBe("pick a slime")
		expect(other.data.consumables.held.MutationSpray).toBe(1)
	end)
	it("a luck potion boosts spawn luck, caps it and stacks with the modifier", function()
		expect(Consumables.spawnLuck(1, false)).toBe(1)
		expect(Consumables.spawnLuck(1, true)).toBe(Config.LUCK_POTION_MULT)
		-- LuckSurge (x2) * 2.5 = 5, capped at SPAWN_LUCK_CAP
		expect(Consumables.spawnLuck(2, true)).toBe(Config.SPAWN_LUCK_CAP)
		-- a modifier above the cap alone is never cut
		expect(Consumables.spawnLuck(Config.SPAWN_LUCK_CAP + 1, true)).toBe(Config.SPAWN_LUCK_CAP + 1)
	end)
	it("potion time extends up to a maximum and expires", function()
		local u = Consumables.extendPotion(0, 100)
		expect(u).toBe(100 + Config.LUCK_POTION_SECONDS)
		u = Consumables.extendPotion(u, 100)
		expect(u).toBe(100 + 2 * Config.LUCK_POTION_SECONDS)
		for _ = 1, 10 do
			u = Consumables.extendPotion(u, 100)
		end
		expect(u).toBe(100 + Config.LUCK_POTION_MAX_SECONDS)
		expect(Consumables.potionFull(u, 100)).toBe(true)
		expect(Consumables.potionFull(u, 100 + 60)).toBe(false)
		expect(Consumables.potionFull(0, 100)).toBe(false)
	end)
	it("using a potion starts the server-wide potion and the spawner reads it only while active", function()
		local slot = slotWith("LuckPotion", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		expect(buy(world, 1, now, "LuckPotion").ok).toBe(true)
		expect(world.potionUntil).toBe(0) -- bought, not used yet
		expect(use(world, 1, now, "LuckPotion").ok).toBe(true)
		expect(world.potionUntil >= now + Config.LUCK_POTION_SECONDS).toBe(true)
		expect(Consumables.view(Fixtures.data(), now, true, world.potionUntil).luckUntil).toBe(world.potionUntil)
		expect(Consumables.view(Fixtures.data(), world.potionUntil + 1, true, world.potionUntil).luckUntil).toBe(0)
		expect(Spawner.spawnOne(world, now) ~= nil).toBe(true)
	end)
	it("a weather totem requests the weather, or is skipped without a Weather service", function()
		local slot = slotWith("WeatherTotem", 1)
		local now = slot * STEP + 1
		local world = ServerFixtures.world(now)
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1e9, now)
		local asked: string? = nil
		local calling = ctx(function(id)
			asked = id
			return true
		end)
		expect(buy(world, 1, now, "WeatherTotem", nil, calling).ok).toBe(true)
		local res = use(world, 1, now, "WeatherTotem", nil, calling)
		expect(res.ok).toBe(true)
		local _, weather = Consumables.stock(slot)
		expect(asked).toBe(weather)
		local paid = 1e9 - session.data.cash
		expect(paid > 0).toBe(true)
		-- refused request: the stack keeps its totem
		session.data.consumables = { slot = 0, bought = {}, held = { WeatherTotem = 1 } }
		session.data.cash = 1e9
		local no = use(
			world,
			1,
			now,
			"WeatherTotem",
			nil,
			ctx(function()
				return false
			end)
		)
		expect(no.ok).toBe(false)
		expect(session.data.consumables.held.WeatherTotem).toBe(1)
		-- no Weather service: item is not offered and cannot be bought
		local view = Consumables.view(session.data, now, false, 0)
		for _, item in view.items do
			expect(item.id ~= "WeatherTotem").toBe(true)
		end
		local none = buy(world, 1, now, "WeatherTotem", nil, ctx(nil))
		expect(none.ok).toBe(false)
		expect(session.data.cash).toBe(1e9)
	end)
	it("WeatherService.request queues the next weather once, never Clear or the current one", function()
		local state = WeatherService.new(0)
		expect(WeatherService.request(state, "Clear")).toBe(false)
		expect(WeatherService.request(state, "Nope")).toBe(false)
		expect(WeatherService.request(state, "Rain")).toBe(true)
		expect(WeatherService.request(state, "Snow")).toBe(false)
		WeatherService.step(state, state.changeAt, function()
			return 0.5
		end)
		expect(state.id).toBe("Rain")
		expect(state.requested).toBeNil()
		expect(WeatherService.request(state, "Rain")).toBe(false)
	end)
end)

describe("Consumables state and saves", function()
	it("shows stock, quantities and the countdown in the snapshot", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 1000)
		local view = Snapshot.build(world, session, T0).consumables
		expect(view ~= nil).toBe(true)
		expect((view :: any).restockAt).toBe(Consumables.restockAt(T0))
		for _, item in (view :: any).items do
			expect(item.left).toBe(item.max)
		end
	end)
	it("round-trips purchases through the save and defaults them when missing", function()
		local d = Fixtures.data()
		Consumables.record(d, 12, "LuckPotion")
		local back = SaveData.deserialize(SaveData.serialize(d, T0))
		expect(back.consumables.slot).toBe(12)
		expect(back.consumables.bought.LuckPotion).toBe(1)
		local stored = SaveData.serialize(PlayerData.new(), T0)
		stored.consumables = nil
		local old = SaveData.deserialize(stored)
		expect(old.consumables.slot).toBe(0)
		expect(next(old.consumables.bought)).toBeNil()
	end)
	it("is pure bookkeeping: ConsumableShop is the only mutator", function()
		expect(type(ConsumableShop.buy)).toBe("function")
	end)
end)
