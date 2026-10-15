--!strict
-- v13 rarity curve (CONTRACT.md §8.7): weights, pity floors, Legendary+ announcements.
-- Logs the spawn distribution of a long simulated volcano run.
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local DROPS = 100000

-- Runs DROPS volcano drops (no rain) and returns counts, longest droughts and announcements.
local function simulate(seed: number)
	local world = ServerFixtures.world()
	world.rng = (require("../src/shared/Rng") :: any).new(seed)
	local counts, droughtEpic, droughtLegendary, sinceEpic, sinceLegendary = {}, 0, 0, 0, 0
	local announced, rareEvents, rareModels = 0, 0, 0
	for i = 1, DROPS do
		local id = Spawner.spawnOne(world, T0 + i)
		local wild = world.wild[id]
		local tier = wild.slime.tier
		counts[tier] = (counts[tier] or 0) + 1
		sinceEpic = if tier >= 4 then 0 else sinceEpic + 1
		sinceLegendary = if tier >= 5 then 0 else sinceLegendary + 1
		droughtEpic = math.max(droughtEpic, sinceEpic)
		droughtLegendary = math.max(droughtLegendary, sinceLegendary)
		if wild.rare then
			rareModels += 1
		end
		for _, event in world.outbox do
			if event.type == "Notify" and event.sound == "Rare" and event.userId == nil then
				announced += 1
			elseif event.type == "Rare" then
				rareEvents += 1
			end
		end
		world.outbox = {}
		world.wild[id] = nil
	end
	return counts, droughtEpic, droughtLegendary, announced, rareEvents, rareModels
end

describe("Rarity curve", function()
	local counts, droughtEpic, droughtLegendary, announced, rareEvents, rareModels = simulate(2026)
	local totalWeight = 0
	for _, r in Config.RARITIES do
		totalWeight += r.weight
	end
	print(`    spawn distribution over {DROPS} volcano drops (seed 2026, pity on):`)
	for tier, r in Config.RARITIES do
		local n = counts[tier] or 0
		print(
			string.format(
				"      %-10s %6d  %6.2f %%  (weight %5.2f %%, ~%.1f per hour at one drop / %d s)",
				r.name,
				n,
				n / DROPS * 100,
				r.weight / totalWeight * 100,
				n / DROPS * 3600 / Config.SPAWN_INTERVAL,
				Config.SPAWN_INTERVAL
			)
		)
	end
	print(`      longest drought: {droughtEpic} drops without Epic+, {droughtLegendary} without Legendary+`)
	print(`      announced: {announced} Rare toasts, {rareEvents} Rare events, {rareModels} RareSpawn slimes`)

	it("is monotone: every tier is rarer than the one below", function()
		for tier = 2, Config.MAX_TIER do
			expect((counts[tier] or 0) < (counts[tier - 1] or 0)).toBe(true)
		end
	end)
	it("never goes PITY_EPIC / PITY_LEGENDARY drops without an Epic+ / Legendary+", function()
		expect(droughtEpic < Config.PITY_EPIC).toBe(true)
		expect(droughtLegendary < Config.PITY_LEGENDARY).toBe(true)
	end)
	it("keeps Mythic rare but reachable (0.2 % .. 1 %) and Legendary+ under 4 %", function()
		local mythic = (counts[6] or 0) / DROPS
		expect(mythic > 0.002 and mythic < 0.01).toBe(true)
		expect(((counts[5] or 0) + (counts[6] or 0)) / DROPS < 0.04).toBe(true)
	end)
	it("announces every Legendary+ drop to everyone, once, with a Rare event and attribute", function()
		local rare = (counts[5] or 0) + (counts[6] or 0)
		expect(announced).toBe(rare)
		expect(rareEvents).toBe(rare)
		expect(rareModels).toBe(rare)
	end)
end)

describe("Spawner.rareText / pityTier", function()
	it("names the rarity in capitals, Mythic gets two bangs", function()
		local slime = Genome.generate((require("../src/shared/Rng") :: any).new(1), { id = "x", tier = 5 })
		slime.mutation = "Gold"
		slime.name = "Globble"
		expect(Spawner.rareText(slime)).toBe("A LEGENDARY Gold Globble erupted from the volcano!")
		slime.tier = 6
		slime.mutation = "None"
		expect(Spawner.rareText(slime)).toBe("A MYTHIC Globble erupted from the volcano!!")
	end)
	it("displays Lava as Syrup in the toast (save id kept)", function()
		local slime = Genome.generate((require("../src/shared/Rng") :: any).new(1), { id = "x", tier = 5 })
		slime.mutation = "Lava"
		slime.name = "Globble"
		expect(Spawner.rareText(slime)).toBe("A LEGENDARY Syrup Globble erupted from the volcano!")
	end)
	it("floors at Epic after PITY_EPIC - 1 misses and Legendary after PITY_LEGENDARY - 1", function()
		expect(Spawner.pityTier({ sinceEpic = 0, sinceLegendary = 0 })).toBeNil()
		expect(Spawner.pityTier({ sinceEpic = Config.PITY_EPIC - 1, sinceLegendary = 0 })).toBe(4)
		expect(Spawner.pityTier({ sinceEpic = 0, sinceLegendary = Config.PITY_LEGENDARY - 1 })).toBe(5)
	end)
end)
