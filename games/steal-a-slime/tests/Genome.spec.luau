--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Rng", function()
	it("is deterministic per seed", function()
		local a, b = Rng.new(42), Rng.new(42)
		for _ = 1, 20 do
			expect(a:float()).toBe(b:float())
		end
	end)
	it("stays in [0, 1) and ints stay in range", function()
		local r = Rng.new(7)
		for _ = 1, 500 do
			local f = r:float()
			expect(f >= 0 and f < 1).toBeTruthy()
			local n = r:int(3, 5)
			expect(n >= 3 and n <= 5 and n == math.floor(n)).toBeTruthy()
		end
	end)
	it("treats 0 / negative / nil seeds safely", function()
		expect(Rng.new(0):float() >= 0).toBeTruthy()
		expect(Rng.new(-5):float() >= 0).toBeTruthy()
		expect(Rng.new(nil):float() >= 0).toBeTruthy()
	end)
	it("weightedIndex respects weights and boundaries", function()
		expect(Rng.weightedIndex({ 1, 1 }, 0)).toBe(1)
		expect(Rng.weightedIndex({ 1, 1 }, 0.49)).toBe(1)
		expect(Rng.weightedIndex({ 1, 1 }, 0.5)).toBe(2)
		expect(Rng.weightedIndex({ 0, 5, 0 }, 0.99)).toBe(2)
		expect(Rng.weightedIndex({ 0, 0 }, 0.3)).toBe(1)
	end)
end)

describe("Genome.rollTier", function()
	it("low rolls give Common, the top roll gives Mythic", function()
		expect(Genome.rollTier(0)).toBe(1)
		expect(Genome.rollTier(0.9999999)).toBe(Config.MAX_TIER)
	end)
	it("matches the configured weights roughly over many rolls", function()
		local rng = Rng.new(123)
		local counts = {}
		for _ = 1, 20000 do
			local t = Genome.rollTier(rng:float())
			counts[t] = (counts[t] or 0) + 1
		end
		expect(counts[1] > counts[2] and counts[2] > counts[3] and counts[3] > counts[4]).toBeTruthy()
		local total = 0
		for _, r in Config.RARITIES do
			total += r.weight
		end
		expect(math.abs(counts[1] / 20000 - Config.RARITIES[1].weight / total) < 0.02).toBeTruthy()
	end)
	it("luck makes rare tiers more likely", function()
		local rng1, rng2 = Rng.new(5), Rng.new(5)
		local normal, lucky = 0, 0
		for _ = 1, 5000 do
			if Genome.rollTier(rng1:float()) >= 3 then
				normal += 1
			end
			if Genome.rollTier(rng2:float(), 3) >= 3 then
				lucky += 1
			end
		end
		expect(lucky > normal * 2).toBeTruthy()
	end)
end)

describe("Genome.generate", function()
	it("is deterministic and valid", function()
		local a = Genome.generate(Rng.new(99), { id = "a" })
		local b = Genome.generate(Rng.new(99), { id = "a" })
		expect(a).toEqual(b)
		expect(Genome.sanitize(a)).toEqual(a)
	end)
	it("honours a forced tier", function()
		local s = Genome.generate(Rng.new(1), { id = "x", tier = 5 })
		expect(s.tier).toBe(5)
	end)
	it("always produces sizes, colours and parts within range", function()
		local rng = Rng.new(2024)
		for i = 1, 300 do
			local s = Genome.generate(rng, { id = tostring(i) })
			expect(s.size >= Config.MIN_SIZE and s.size <= Config.MAX_SIZE).toBeTruthy()
			for c = 1, 3 do
				expect(s.color[c] >= 0 and s.color[c] <= 255).toBeTruthy()
			end
			expect(table.find(Config.EYES, s.eyes) ~= nil).toBeTruthy()
			expect(#s.name >= 3).toBeTruthy()
		end
	end)
end)

describe("Genome.baseIncome", function()
	it("is rarity income x size", function()
		expect(Genome.baseIncome(Fixtures.slime("a", 1))).toBe(1)
		expect(Genome.baseIncome(Fixtures.slime("a", 3, { size = 2 }))).toBe(18)
		expect(Genome.baseIncome(Fixtures.slime("a", 2))).toBe(3)
	end)
	it("a vat-made slime earns BREWED_INCOME_MULT more, a recipe hybrid RECIPE_INCOME_MULT", function()
		local base = Genome.baseIncome(Fixtures.slime("a", 3))
		expect(Genome.baseIncome(Fixtures.slime("a", 3, { brewed = 1 }))).toBe(base * Config.BREWED_INCOME_MULT)
		expect(Genome.baseIncome(Fixtures.slime("a", 3, { brewed = 2 }))).toBe(base * Config.RECIPE_INCOME_MULT)
	end)
end)

describe("Genome.sanitize", function()
	it("rejects non-tables and bad ids", function()
		expect(Genome.sanitize(nil)).toBeNil()
		expect(Genome.sanitize("slime")).toBeNil()
		expect(Genome.sanitize({ tier = 1 })).toBeNil()
		expect(Genome.sanitize({ id = "", tier = 1 })).toBeNil()
		expect(Genome.sanitize({ id = string.rep("x", 65), tier = 1 })).toBeNil()
		expect(Genome.sanitize({ id = "a", tier = 0 / 0 })).toBeNil()
	end)
	it("clamps and defaults every field", function()
		local s = Genome.sanitize({
			id = "a",
			tier = 99,
			size = 50,
			color = { -5, 300, "x" },
			eyes = "Laser",
			mutation = "Cursed",
			mutations = { "Glow" },
			pad = 99,
		})
		assert(s, "sanitize returned nil")
		expect(s.tier).toBe(Config.MAX_TIER)
		expect(s.size).toBe(Config.MAX_SIZE)
		expect(s.color).toEqual({ 0, 255, 200 })
		expect(s.eyes).toBe("Round")
		expect((s :: any).mutation).toBeNil()
		expect((s :: any).mutations).toBeNil()
		expect(s.pad).toBeNil()
	end)
	it("keeps brewed only as 1 (random merge) or 2 (recipe)", function()
		local function brewed(value: any): number?
			return (Genome.sanitize({ id = "a", tier = 2, brewed = value }) :: any).brewed
		end
		expect(brewed(1)).toBe(1)
		expect(brewed(2)).toBe(2)
		expect(brewed(nil)).toBeNil()
		expect(brewed(0)).toBeNil()
		expect(brewed(3)).toBeNil()
		expect(brewed(1.5)).toBeNil()
		expect(brewed("1")).toBeNil()
	end)
	it("display name is rarity and name", function()
		expect(Genome.displayName(Fixtures.slime("a", 4))).toBe("Epic Blorp")
		expect(Genome.displayName(Fixtures.slime("a", 1))).toBe("Common Blorp")
	end)
end)

describe("Genome roster wiring (v28)", function()
	local SlimeRoster = require("../src/shared/SlimeRoster")
	it("wild slimes get a roster species of their tier and its name", function()
		local rng = Rng.new(5)
		local seen = {}
		for i = 1, 400 do
			local s = Genome.generate(rng, { id = tostring(i) })
			local entry = SlimeRoster.get(s.species :: string)
			expect(entry ~= nil).toBe(true)
			assert(entry, "expected a value")
			expect(entry.tier).toBe(s.tier)
			expect(s.name).toBe(entry.name)
			seen[entry.id] = true
		end
	end)
	it("every Config tier has species and forced tiers map to them", function()
		for tier = 1, Config.MAX_TIER do
			expect(#SlimeRoster.forTier(tier) > 0).toBe(true)
			local s = Genome.generate(Rng.new(tier), { id = "t", tier = tier })
			expect((SlimeRoster.get(s.species :: string) :: any).tier).toBe(tier)
		end
		expect(Genome.rollSpecies(SlimeRoster.SECRET_TIER, 0.5) ~= nil).toBe(true)
	end)
	it("old saves without species still load and keep their name", function()
		local s = Genome.sanitize({
			id = "old",
			name = "Globble",
			tier = 3,
			color = { 1, 2, 3 },
			size = 1.2,
			pattern = "Spots",
			eyes = "Round",
			mouth = "Smile",
			mutation = "Lava",
		})
		assert(s, "expected a value")
		expect(s.name).toBe("Globble")
		expect(s.species).toBe(nil)
		expect((s :: any).mutation).toBeNil()
		local bad = Genome.sanitize({ id = "x", tier = 1, species = "nope" })
		assert(bad, "expected a value")
		expect(bad.species).toBe(nil)
		local good = Genome.sanitize({ id = "y", tier = 1, species = "gummy" })
		assert(good, "expected a value")
		expect(good.species).toBe("gummy")
	end)
end)
