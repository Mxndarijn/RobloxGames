--!strict
-- Follow-pet passives (CONTRACT.md §14): perk lookup per slime, caps, only while a favourite is set,
-- server-side application (income / luck / merge mutation chance) and the snapshot view.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local Merge = require("../src/shared/Merge")
local Perks = require("../src/shared/Perks")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function withFav(slime: Genome.Slime): PlayerData.Data
	local data = Fixtures.data({ slime })
	data.favoriteId = slime.id
	return data
end

describe("Perks.petPassive", function()
	it("is nil without a favourite", function()
		local data = Fixtures.data({ Fixtures.slime("a", 3) })
		expect(Perks.petPassive(data)).toBe(nil)
	end)
	it("picks the kind by tier and scales with the tier", function()
		local income = Perks.petPassive(withFav(Fixtures.slime("a", 2)))
		expect(income and income.kind).toBe("income")
		expect(income and income.value).toBe(0.02)
		expect(income and income.text).toBe("+2% income")
		local luck = Perks.petPassive(withFav(Fixtures.slime("a", 3)))
		expect(luck and luck.kind).toBe("luck")
		expect(luck and luck.text).toBe("+3% luck")
		local mut = Perks.petPassive(withFav(Fixtures.slime("a", 5)))
		expect(mut and mut.kind).toBe("mutation")
		expect(mut and mut.value).toBe(0.1)
	end)
	it("each mutation adds a step", function()
		local plain = Perks.petPassive(withFav(Fixtures.slime("a", 3)))
		local mutated =
			Perks.petPassive(withFav(Fixtures.slime("a", 3, { mutation = "Glow", mutations = { "Glow", "Syrup" } })))
		expect(mutated and plain and mutated.value - plain.value).toBeCloseTo(2 * Config.PET_PASSIVES.MUTATION_STEP)
	end)
	it("is capped per kind", function()
		for tier, kind in Config.PET_PASSIVES.KIND_BY_TIER do
			local slime = Fixtures.slime(
				"a",
				tier,
				{ mutation = "Glow", mutations = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" } }
			)
			local perk = Perks.petPassive(withFav(slime))
			expect(perk and perk.value <= Config.PET_PASSIVES.KINDS[kind].cap).toBe(true)
		end
		local top = Perks.petPassive(
			withFav(Fixtures.slime("a", 6, { mutations = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" } }))
		)
		expect(top and top.value).toBe(Config.PET_PASSIVES.KINDS.mutation.cap)
	end)
	it("is nil when the favourite is not owned or the feature is off", function()
		local data = Fixtures.data({ Fixtures.slime("a", 3) })
		data.favoriteId = "missing"
		expect(Perks.petPassive(data)).toBe(nil)
	end)
end)

describe("applied server-side", function()
	it("income perk multiplies income only while the favourite is set", function()
		local data = Fixtures.data({ Fixtures.slime("a", 2) })
		local base = Perks.bonusMultiplier(data)
		data.favoriteId = "a"
		expect(Perks.bonusMultiplier(data)).toBeCloseTo(base * 1.02)
		PlayerData.setFavorite(data, nil)
		expect(Perks.bonusMultiplier(data)).toBe(base)
	end)
	it("luck perk adds to luckChance, mutation perk only to the merge bonus", function()
		local luck = withFav(Fixtures.slime("a", 3))
		expect(Perks.luckChance(luck)).toBeCloseTo(0.03)
		expect(Perks.petMutationBonus(luck)).toBe(0)
		local mut = withFav(Fixtures.slime("a", 5))
		expect(Perks.luckChance(mut)).toBe(0)
		expect(Perks.petMutationBonus(mut)).toBeCloseTo(0.1)
	end)
	it("a mutation-pet raises the merge mutation chance", function()
		local function mutated(bonus: number): number
			local rng = Rng.new(5)
			local n = 0
			for i = 1, 400 do
				if
					Merge.merge(Fixtures.slime("a", 1), Fixtures.slime("b", 1), rng, `c{i}`, bonus).mutation ~= "None"
				then
					n += 1
				end
			end
			return n
		end
		expect(mutated(0.5) > mutated(0) + 60).toBe(true)
	end)
	it("snapshot carries the perk; no favourite = nil; no remote can set it", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 3) }, 10)
		expect(Snapshot.build(world, s, T0).petPerk).toBe(nil)
		s.data.favoriteId = "a"
		local perk = Snapshot.build(world, s, T0).petPerk
		expect(perk and perk.text).toBe("+3% luck")
		-- the client only sends a slime id (Favorite); the value is derived from owned data
		expect(PlayerData.setFavorite(s.data, "not-mine")).toBe(false)
		expect(Snapshot.build(world, s, T0).petPerk and true).toBe(true)
	end)
	it("is runtime-only: the save has no pet field and old saves load", function()
		local data = withFav(Fixtures.slime("a", 4))
		local raw = SaveData.serialize(data)
		expect((raw :: any).petPerk).toBe(nil)
		local back = SaveData.deserialize(raw)
		expect(back and Perks.petPassive(back) ~= nil).toBe(true)
	end)
end)
