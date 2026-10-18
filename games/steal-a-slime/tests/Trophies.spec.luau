--!strict
-- Boss trophies (src/shared/Trophies.luau, data.trophies in SaveData; contract/boss-event.md).
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local SlimeLooks = require("../src/shared/SlimeLooks")
local TestRunner = require("./TestRunner")
local Trophies = require("../src/shared/Trophies")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Trophies.bossSlime", function()
	it("makes every boss species at MAX_SIZE with its name, tier and colour", function()
		for seed = 1, 30 do
			for _, species in { "goozilla", "queen_jelly", "mecha_goo" } do
				local slime = Trophies.bossSlime(Rng.new(seed), `b{seed}`, species) :: Genome.Slime
				expect(slime.species).toBe(species)
				expect(slime.size).toBe(Config.MAX_SIZE)
				expect(slime.tier).toBe(if species == "mecha_goo" then Config.SECRET_TIER else 6)
				local look = SlimeLooks.get(species)
				if look then
					expect(slime.color[1]).toBe(look.color[1])
				end
			end
		end
	end)
	it("refuses species that aren't bosses", function()
		expect(Trophies.bossSlime(Rng.new(1), "x", "gummy")).toBeNil()
		expect(Trophies.bossSlime(Rng.new(1), "x", "nope")).toBeNil()
	end)
end)

describe("Trophies.award", function()
	it("adds one trophy per species outside data.slimes, and a duplicate keeps the held one", function()
		local data = Fixtures.data()
		local rng = Rng.new(3)
		local first = Trophies.bossSlime(rng, "a", "goozilla") :: Genome.Slime
		local result = Trophies.award(data, first)
		expect(result).toBe("new")
		expect(#data.trophies).toBe(1)
		expect(#data.slimes).toBe(0)
		expect(PlayerData.freePad(data) ~= nil).toBe(true)
		for _ = 1, 5 do
			local again, held = Trophies.award(data, Trophies.bossSlime(rng, "b", "goozilla") :: Genome.Slime)
			expect(again).toBe("owned")
			expect(held).toBe(first)
		end
		expect(#data.trophies).toBe(1)
		Trophies.award(data, Trophies.bossSlime(rng, "c", "queen_jelly") :: Genome.Slime)
		expect(#data.trophies).toBe(2)
	end)
	it("trophies earn like pad slimes", function()
		local data = Fixtures.data()
		local rng = Rng.new(5)
		local before = PlayerData.incomePerSecond(data)
		local trophy = Trophies.bossSlime(rng, "t", "queen_jelly") :: Genome.Slime
		Trophies.award(data, trophy)
		expect(PlayerData.incomePerSecond(data) - before).toBeCloseTo(PlayerData.slimeIncome(data, trophy), 1e-6)
	end)
end)

describe("SaveData trophies", function()
	it("round-trip through serialize / deserialize", function()
		local data = Fixtures.data()
		local rng = Rng.new(9)
		Trophies.award(data, Trophies.bossSlime(rng, "t1", "goozilla") :: Genome.Slime)
		Trophies.award(data, Trophies.bossSlime(rng, "t2", "mecha_goo") :: Genome.Slime)
		local loaded = SaveData.deserialize(SaveData.serialize(data, 0))
		expect(#loaded.trophies).toBe(2)
		expect(loaded.trophies[1].species).toBe("goozilla")
		expect(loaded.trophies[2].species).toBe("mecha_goo")
		expect(loaded.trophies[1]).toEqual(data.trophies[1])
	end)
	it("a save without trophies has none; junk, non-boss species and duplicates are dropped", function()
		local raw = SaveData.serialize(Fixtures.data(), 0)
		raw.trophies = nil
		expect(#SaveData.deserialize(raw).trophies).toBe(0)
		local boss = Fixtures.slime("b1", 6, { species = "goozilla", pad = 3 })
		raw.trophies = {
			"junk",
			Fixtures.slime("s1", 1, { species = "gummy" }),
			boss,
			Fixtures.slime("b2", 6, { species = "goozilla" }),
		}
		local trophies = SaveData.deserialize(raw).trophies
		expect(#trophies).toBe(1)
		expect(trophies[1].id).toBe("b1")
		expect(trophies[1].pad).toBeNil()
	end)
end)
