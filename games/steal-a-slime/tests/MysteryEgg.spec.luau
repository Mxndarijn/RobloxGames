--!strict
-- Mystery Egg (the free boss helper egg): drop table, event hatches, State.egg, save compatibility. Never sold.
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
local Shops = require("../src/shared/Shops")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- Chance of each tier from the drop table weights.
local function probabilities(): { [number]: number }
	local total = 0
	for _, drop in Config.MYSTERY_EGG_DROPS do
		total += drop.weight
	end
	local out = {}
	for _, drop in Config.MYSTERY_EGG_DROPS do
		out[drop.tier] = drop.weight / total
	end
	return out
end

describe("MysteryEgg drop table", function()
	it("has valid tiers and positive weights", function()
		local seen = {}
		for _, drop in Config.MYSTERY_EGG_DROPS do
			expect(drop.tier >= 1 and drop.tier <= Config.MAX_TIER).toBe(true)
			expect(drop.weight > 0).toBe(true)
			expect(seen[drop.tier]).toBeNil()
			seen[drop.tier] = true
		end
	end)
	it("follows its weights under seeded sampling", function()
		local rng = Rng.new(12345)
		local n = 20000
		local counts: { [number]: number } = {}
		for _ = 1, n do
			local tier = MysteryEgg.rollTier(rng:float())
			counts[tier] = (counts[tier] or 0) + 1
		end
		local p = probabilities()
		for tier, chance in p do
			expect(math.abs((counts[tier] or 0) / n - chance) < 0.02).toBe(true)
		end
		for tier in counts do
			expect(p[tier] ~= nil).toBe(true)
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

describe("MysteryEgg is not for sale", function()
	it("has no buy action and no shop row", function()
		expect(Remotes.ACTIONS.BuyEgg).toBeNil()
		expect(Validate.ACTIONS.BuyEgg).toBeNil()
		expect(Shops.shopOfAction("BuyEgg")).toBeNil()
		expect(Shops.shopOf("MysteryEgg")).toBeNil()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 1e9)
		local ctx: Actions.Context = {
			distanceBetween = function()
				return 2
			end,
			positionOf = function()
				return nil
			end,
		}
		expect(Actions.handle(world, 1, "BuyEgg", {}, T0 + 100, ctx).ok).toBe(false)
		expect(session.data.cash).toBe(1e9)
		expect(#session.data.slimes).toBe(0)
		local state = Snapshot.build(world, session, T0 + 101)
		expect((state.shop :: any).MysteryEgg).toBeNil()
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
		local filled = 0
		for _ = 1, math.ceil(Config.PADS_MAX / ServerEgg.MAX_EVENT_EGGS) do
			filled += #ServerEgg.spawnForEvent(world, 1, 50, T0)
		end
		expect(filled).toBe(session.data.padsUnlocked - 3)
		expect(#ServerEgg.spawnForEvent(world, 1, 1, T0)).toBe(0)
		expect(#ServerEgg.spawnForEvent(world, 99, 1, T0)).toBe(0)
	end)
	it("hatches a valid slime with its own id onto a free pad and reveals it", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 0)
		local hatched = ServerEgg.spawnForEvent(world, 1, 2, T0 + 100)
		expect(#hatched).toBe(2)
		local slime = session.data.slimes[1]
		expect(Genome.sanitize(slime)).toBeTruthy()
		expect(slime.pad).toBe(1)
		expect(probabilities()[slime.tier] ~= nil).toBe(true)
		expect(slime.species ~= nil and session.data.found[slime.species :: string]).toBe(true)
		expect(session.data.slimes[1].id ~= session.data.slimes[2].id).toBe(true)
		expect(session.egg and session.egg.slime.id).toBe(hatched[2].id)
		expect(#ServerFixtures.notifications(world, 1) >= 1).toBe(true)
		local state = Snapshot.build(world, session, T0 + 101)
		expect(state.egg.hatched and state.egg.hatched.at).toBe(T0 + 100)
	end)
end)

describe("MysteryEgg save format", function()
	it("round-trips hatched slimes through the save", function()
		local data = PlayerData.new()
		expect((MysteryEgg.hatchInto(data, Rng.new(4), "egg-1"))).toBe(true)
		local loaded = SaveData.deserialize(SaveData.serialize(data))
		expect(loaded and #loaded.slimes).toBe(1)
		expect(loaded and loaded.slimes[1].id).toBe("egg-1")
		expect(loaded and loaded.slimes[1]).toEqual(data.slimes[1])
	end)
end)
