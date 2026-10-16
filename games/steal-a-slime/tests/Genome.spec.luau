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

describe("Genome.rollMutation", function()
	it("is None when the chance roll misses", function()
		expect(Genome.rollMutation(0.5, 0, 0.1)).toBe("None")
	end)
	it("picks by weight when the chance roll hits", function()
		expect(Genome.rollMutation(0.01, 0, 0.1)).toBe("Glow")
		expect(Genome.rollMutation(0.01, 0.999, 0.1)).toBe("Eclipse")
	end)
	it("weights fall as multipliers rise", function()
		for i = 2, #Config.MUTATIONS do
			expect(Config.MUTATIONS[i].multiplier > Config.MUTATIONS[i - 1].multiplier).toBe(true)
			expect(Config.MUTATIONS[i].weight < Config.MUTATIONS[i - 1].weight).toBe(true)
		end
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
			local s = Genome.generate(rng, { id = tostring(i), mutationChance = 0.5 })
			expect(s.size >= Config.MIN_SIZE and s.size <= Config.MAX_SIZE).toBeTruthy()
			for c = 1, 3 do
				expect(s.color[c] >= 0 and s.color[c] <= 255).toBeTruthy()
			end
			expect(table.find(Config.EYES, s.eyes) ~= nil).toBeTruthy()
			expect(s.mutation == "None" or Genome.mutationInfo(s.mutation) ~= nil).toBeTruthy()
			expect(#s.name >= 3).toBeTruthy()
		end
	end)
end)

describe("Genome.baseIncome", function()
	it("is rarity income x size x mutation", function()
		expect(Genome.baseIncome(Fixtures.slime("a", 1))).toBe(1)
		expect(Genome.baseIncome(Fixtures.slime("a", 3, { size = 2 }))).toBe(18)
		expect(Genome.baseIncome(Fixtures.slime("a", 2, { mutation = "Gold" }))).toBe(15)
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
			pad = 99,
		})
		assert(s, "sanitize returned nil")
		expect(s.tier).toBe(Config.MAX_TIER)
		expect(s.size).toBe(Config.MAX_SIZE)
		expect(s.color).toEqual({ 0, 255, 200 })
		expect(s.eyes).toBe("Round")
		expect(s.mutation).toBe("None")
		expect(s.pad).toBeNil()
	end)
	it("display name includes mutation and rarity", function()
		expect(Genome.displayName(Fixtures.slime("a", 4, { mutation = "Lava" }))).toBe("Syrup Epic Blorp") -- save id Lava, display Syrup
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
		expect(s.mutation).toBe("Lava")
		local bad = Genome.sanitize({ id = "x", tier = 1, species = "nope" })
		assert(bad, "expected a value")
		expect(bad.species).toBe(nil)
		local good = Genome.sanitize({ id = "y", tier = 1, species = "pudding" })
		assert(good, "expected a value")
		expect(good.species).toBe("pudding")
	end)
	it("new mutations load and Lava displays as Syrup", function()
		for _, m in { "Rainbow", "Crystal", "Eclipse" } do
			expect(Genome.mutationInfo(m) ~= nil).toBe(true)
		end
		expect(Genome.mutationMultiplier("Eclipse")).toBe(10)
		expect(Genome.mutationDisplay("Lava")).toBe("Syrup")
		expect(Genome.mutationDisplay("Gold")).toBe("Gold")
		local s = Genome.generate(Rng.new(1), { id = "x", tier = 1 })
		s.mutation = "Lava"
		expect(string.find(Genome.displayName(s), "Syrup", 1, true) ~= nil).toBe(true)
	end)
end)
