--!strict
-- Mystery Egg: drop table, cash-only purchase, hatched slime, event spawns, save compatibility.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local MysteryEgg = require("../src/shared/MysteryEgg")
local PlayerData = require("../src/shared/PlayerData")
local Remotes = require("../src/shared/Remotes")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerEgg = require("../src/server/MysteryEgg")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
}

local function buy(world: any, userId: number, at: number?)
	world.sessions[userId].limiter = {}
	return Actions.handle(world, userId, "BuyEgg", {}, at or T0 + 100, ctx)
end

describe("MysteryEgg drop table", function()
	it("has valid tiers, positive weights and probabilities that sum to 1", function()
		local seen = {}
		for _, drop in Config.MYSTERY_EGG_DROPS do
			expect(drop.tier >= 1 and drop.tier <= Config.MAX_TIER).toBe(true)
			expect(drop.weight > 0).toBe(true)
			expect(seen[drop.tier]).toBeNil()
			seen[drop.tier] = true
		end
		local sum = 0
		for _, p in MysteryEgg.probabilities() do
			sum += p
		end
		expect(math.abs(sum - 1) < 1e-9).toBe(true)
		expect(math.abs(MysteryEgg.probabilities()[2] - 0.5) < 1e-9).toBe(true)
	end)
	it("is cash only and never pays for itself on resale", function()
		local ev = 0
		for _, drop in Config.MYSTERY_EGG_DROPS do
			local slime = Genome.generate(Rng.new(1), { id = "x", tier = drop.tier })
			slime.size = 1.4
			ev += MysteryEgg.probabilities()[drop.tier] * Genome.baseIncome(slime) * Config.SELL_SECONDS
		end
		expect(ev < Config.MYSTERY_EGG_PRICE).toBe(true)
	end)
	it("follows its probabilities under seeded sampling", function()
		local rng = Rng.new(12345)
		local n = 20000
		local counts: { [number]: number } = {}
		for _ = 1, n do
			local tier = MysteryEgg.rollTier(rng:float())
			counts[tier] = (counts[tier] or 0) + 1
		end
		for tier, p in MysteryEgg.probabilities() do
			expect(math.abs((counts[tier] or 0) / n - p) < 0.02).toBe(true)
		end
		for tier in counts do
			expect(MysteryEgg.probabilities()[tier] ~= nil).toBe(true)
		end
	end)
	it("is deterministic for a seed", function()
		local a = MysteryEgg.hatch(Rng.new(9), "a")
		local b = MysteryEgg.hatch(Rng.new(9), "a")
		expect(a.tier).toBe(b.tier)
		expect(a.name).toBe(b.name)
		expect(a.size).toBe(b.size)
	end)
end)

describe("BuyEgg", function()
	it("is a rate-limited action", function()
		expect(Remotes.ACTIONS.BuyEgg).toBeTruthy()
		expect(Validate.ACTIONS.BuyEgg).toBeTruthy()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, nil, 1e9)
		expect(Actions.handle(world, 1, "BuyEgg", {}, T0 + 100, ctx).ok).toBe(true)
		local again = Actions.handle(world, 1, "BuyEgg", {}, T0 + 100.1, ctx)
		expect(again.ok).toBe(false)
		expect(again.message).toBe("too fast")
	end)
	it("rejects insufficient cash and changes nothing", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 100)
		local price = MysteryEgg.price(session.data)
		session.data.cash = price - 1
		local res = buy(world, 1)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("not enough cash")
		expect(session.data.cash).toBe(price - 1)
		expect(#session.data.slimes).toBe(0)
		expect(session.egg).toBeNil()
	end)
	it("charges the price and hatches a valid slime onto a free pad", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 100)
		local price = MysteryEgg.price(session.data)
		session.data.cash = price + 7
		expect(buy(world, 1).ok).toBe(true)
		expect(session.data.cash).toBe(7)
		expect(#session.data.slimes).toBe(1)
		local slime = session.data.slimes[1]
		expect(Genome.sanitize(slime)).toBeTruthy()
		expect(slime.pad).toBe(1)
		expect(MysteryEgg.probabilities()[slime.tier] ~= nil).toBe(true)
		expect(slime.species ~= nil and session.data.found[slime.species :: string]).toBe(true)
		expect(session.egg and session.egg.slime.id).toBe(slime.id)
		expect(#ServerFixtures.notifications(world, 1) >= 1).toBe(true)
	end)
	it("gives each egg its own id", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 1e9)
		buy(world, 1)
		buy(world, 1, T0 + 200)
		expect(#session.data.slimes).toBe(2)
		expect(session.data.slimes[1].id ~= session.data.slimes[2].id).toBe(true)
	end)
	it("does not charge when the plot is full", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 1e9)
		for _ = 1, session.data.padsUnlocked do
			expect(buy(world, 1, T0 + 100 + #session.data.slimes * 2).ok).toBe(true)
		end
		local cash = session.data.cash
		local res = buy(world, 1, T0 + 500)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("plot full")
		expect(session.data.cash).toBe(cash)
	end)
	it("scales the price with rebirths", function()
		local data = PlayerData.new()
		local base = MysteryEgg.price(data)
		data.rebirths = 3
		expect(MysteryEgg.price(data) > base).toBe(true)
	end)
	it("shows in State.shop and State.egg", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 1e9)
		buy(world, 1)
		local state = Snapshot.build(world, session, T0 + 101)
		expect(state.shop.MysteryEgg and state.shop.MysteryEgg.price).toBe(MysteryEgg.price(session.data))
		expect(state.egg.hatched and state.egg.hatched.at).toBe(T0 + 100)
	end)
end)

describe("MysteryEgg.spawnForEvent", function()
	it("hatches free eggs onto the plot until it is full", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 0)
		local hatched = ServerEgg.spawnForEvent(world, 1, 3, T0)
		expect(#hatched).toBe(3)
		expect(#session.data.slimes).toBe(3)
		expect(session.data.cash).toBe(0)
		expect(#ServerEgg.spawnForEvent(world, 1, 50, T0)).toBe(session.data.padsUnlocked - 3)
		expect(#ServerEgg.spawnForEvent(world, 1, 1, T0)).toBe(0)
		expect(#ServerEgg.spawnForEvent(world, 99, 1, T0)).toBe(0)
	end)
end)

describe("MysteryEgg save format", function()
	it("round-trips hatched slimes through the save", function()
		local data = PlayerData.new()
		data.cash = 1e6
		expect((MysteryEgg.buy(data, Rng.new(4), "egg-1"))).toBe(true)
		local loaded = SaveData.deserialize(SaveData.serialize(data))
		expect(loaded and #loaded.slimes).toBe(1)
		expect(loaded and loaded.slimes[1].id).toBe("egg-1")
		expect(loaded and loaded.slimes[1]).toEqual(data.slimes[1])
	end)
end)
