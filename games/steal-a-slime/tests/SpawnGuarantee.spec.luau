--!strict
-- Time guarantees and jackpot odds (contract/slime-ladder.md §45.2, §45.6): a Legendary every GUARANTEE_SECONDS[5]
-- and a Mythic every GUARANTEE_SECONDS[6] without one, on top of the count pity; jackpots are about 1 in 10 of
-- their rarity.
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local LEGENDARY, MYTHIC = 5, 6

-- A fountain rng whose floats are all 0: every natural tier roll lands on Common.
local function lowRolls(): Rng.Rng
	local rng = Rng.new(1);
	(rng :: any).float = function(): number
		return 0
	end
	return rng
end

describe("Spawner.minTier", function()
	it("guarantees a Legendary after 300 s and a Mythic after 900 s", function()
		expect(Config.GUARANTEE_SECONDS[LEGENDARY]).toBe(300)
		expect(Config.GUARANTEE_SECONDS[MYTHIC]).toBe(900)
	end)
	it("starts the clocks on the server's first drop and raises the floor once a clock runs out", function()
		local world = ServerFixtures.world()
		expect(Spawner.guaranteeIn(world, LEGENDARY, T0)).toBeNil()
		expect(Spawner.minTier(world, T0)).toBeNil()
		expect(Spawner.guaranteeIn(world, LEGENDARY, T0)).toBe(Config.GUARANTEE_SECONDS[LEGENDARY])
		expect(Spawner.guaranteeIn(world, MYTHIC, T0 + 100)).toBe(Config.GUARANTEE_SECONDS[MYTHIC] - 100)
		expect(Spawner.minTier(world, T0 + Config.GUARANTEE_SECONDS[LEGENDARY] - 1)).toBeNil()
		expect(Spawner.minTier(world, T0 + Config.GUARANTEE_SECONDS[LEGENDARY])).toBe(LEGENDARY)
		expect(Spawner.guaranteeIn(world, LEGENDARY, T0 + 9999)).toBe(0)
		expect(Spawner.minTier(world, T0 + Config.GUARANTEE_SECONDS[MYTHIC])).toBe(MYTHIC)
	end)
	it("keeps the count pity when it is higher than any due guarantee", function()
		local world = ServerFixtures.world()
		Spawner.minTier(world, T0)
		world.pity.sinceEpic = Config.PITY_EPIC - 1
		expect(Spawner.minTier(world, T0 + 1)).toBe(4)
		world.pity.sinceLegendary = Config.PITY_LEGENDARY - 1
		expect(Spawner.minTier(world, T0 + 1)).toBe(LEGENDARY)
	end)
	it("noteTier restarts every clock the drop covers: a Legendary only its own, a Mythic both", function()
		local world = ServerFixtures.world()
		Spawner.minTier(world, T0)
		local late = T0 + Config.GUARANTEE_SECONDS[MYTHIC]
		Spawner.noteTier(world, LEGENDARY, late)
		expect(Spawner.guaranteeIn(world, LEGENDARY, late)).toBe(Config.GUARANTEE_SECONDS[LEGENDARY])
		expect(Spawner.minTier(world, late)).toBe(MYTHIC)
		Spawner.noteTier(world, Config.MAX_TIER, late)
		expect(Spawner.guaranteeIn(world, MYTHIC, late)).toBe(Config.GUARANTEE_SECONDS[MYTHIC])
		expect(Spawner.minTier(world, late)).toBeNil()
		Spawner.noteTier(world, 4, late + 500)
		expect(Spawner.minTier(world, late + Config.GUARANTEE_SECONDS[LEGENDARY])).toBe(LEGENDARY)
	end)
end)

describe("fountain drops with the time guarantee", function()
	it("a run of Commons turns into a Legendary at 300 s and a Mythic at 900 s, then the clocks reset", function()
		local world = ServerFixtures.world()
		world.rng = lowRolls()
		local step = 10
		local tiers: { [number]: number } = {}
		for t = 0, 1200, step do
			world.pity = { sinceEpic = 0, sinceLegendary = 0 } -- the count pity stays out of the way
			local id = Spawner.spawnSlime(world, T0 + t)
			tiers[t] = world.wild[id].slime.tier
			world.wild[id] = nil
		end
		local legendary, mythic = Config.GUARANTEE_SECONDS[LEGENDARY], Config.GUARANTEE_SECONDS[MYTHIC]
		expect(tiers[0]).toBe(1)
		expect(tiers[legendary - step]).toBe(1)
		expect(tiers[legendary]).toBe(LEGENDARY)
		expect(tiers[legendary + step]).toBe(1)
		expect(tiers[2 * legendary]).toBe(LEGENDARY)
		expect(tiers[mythic]).toBe(MYTHIC)
		-- the Mythic restarted the Legendary clock too: the next one is 300 s after it, not after the last Legendary
		expect(tiers[mythic + step]).toBe(1)
		expect(tiers[mythic + legendary - step]).toBe(1)
		expect(tiers[mythic + legendary]).toBe(LEGENDARY)
		expect(Spawner.guaranteeIn(world, MYTHIC, T0 + 1200)).toBe(mythic - (1200 - mythic))
	end)
	it("a natural Legendary restarts the Legendary clock", function()
		local world = ServerFixtures.world()
		world.rng = lowRolls()
		Spawner.spawnSlime(world, T0)
		Spawner.noteTier(world, LEGENDARY, T0 + 200)
		expect(Spawner.guaranteeIn(world, LEGENDARY, T0 + 300)).toBe(200)
		local id = Spawner.spawnSlime(world, T0 + 300)
		expect(world.wild[id].slime.tier).toBe(1)
	end)
end)

describe("jackpot odds", function()
	-- Share of weighted species rolls of `tier` (every family open) that land on a jackpot.
	local function jackpotShare(tier: number): number
		local pool = Genome.speciesPool(tier, Spawner.familyPool(true))
		local hits, n = 0, 20000
		for i = 1, n do
			local entry = Genome.pickWeighted(pool, (i - 0.5) / n) :: any
			hits += if entry.jackpot then 1 else 0
		end
		return hits / n
	end

	it("each top rarity's jackpot is about 1 in 10 of its drops", function()
		for _, id in { "jackpot", "star_emperor", "goo_god" } do
			local tier = (SlimeRoster.get(id) :: SlimeRoster.Entry).tier
			local share = jackpotShare(tier)
			expect(`{id} {share > 0.07 and share < 0.13}`).toBe(`{id} true`)
		end
	end)
	it("a jackpot drops from the fountain like any slime of its rarity", function()
		local rng = Rng.new(3)
		local seen = {}
		for i = 1, 400 do
			for tier = Config.SECRET_TIER, Config.MAX_TIER do
				local slime = Genome.generate(rng, { id = `j{i}`, tier = tier, families = Spawner.familyPool(true) })
				seen[slime.species :: string] = true
			end
		end
		expect(seen.jackpot and seen.star_emperor and seen.goo_god).toBe(true)
	end)
	it("a jackpot earns x5 its rarity's base income", function()
		local slime = { id = "j", name = "Goo God", tier = 9, species = "goo_god", size = 1 } :: any
		local plain = { id = "p", name = "Aurora", tier = 9, species = "aurora", size = 1 } :: any
		expect(Genome.baseIncome(slime) / Genome.baseIncome(plain)).toBeCloseTo(5, 1e-9)
	end)
end)
