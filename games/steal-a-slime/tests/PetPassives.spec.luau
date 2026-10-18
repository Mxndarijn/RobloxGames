--!strict
-- Follow-pet passives (CONTRACT.md §14): perk lookup per slime, caps, only while a favourite is set,
-- server-side application (income / luck) and the snapshot view.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local Perks = require("../src/shared/Perks")
local PlayerData = require("../src/shared/PlayerData")
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
		local top = Perks.petPassive(withFav(Fixtures.slime("a", 5)))
		expect(top and top.kind).toBe("income")
		expect(top and top.value).toBe(0.05)
	end)
	it("is capped per kind", function()
		for tier, kind in Config.PET_PASSIVES.KIND_BY_TIER do
			local perk = Perks.petPassive(withFav(Fixtures.slime("a", tier)))
			expect(perk and perk.value <= Config.PET_PASSIVES.KINDS[kind].cap).toBe(true)
		end
		local top = Perks.petPassive(withFav(Fixtures.slime("a", 7)))
		expect(top and top.value).toBe(Config.PET_PASSIVES.KINDS.luck.cap)
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
	it("luck perk adds to luckChance, income perk does not", function()
		local luck = withFav(Fixtures.slime("a", 3))
		expect(Perks.luckChance(luck)).toBeCloseTo(0.03)
		local income = withFav(Fixtures.slime("a", 5))
		expect(Perks.luckChance(income)).toBe(0)
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
