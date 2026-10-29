--!strict
-- Save v3 -> v4 (slime.mutation -> slime.mutations list), then stripped again by the later migrations:
-- a loaded slime never carries a mutation. Fixtures are tables in the exact shape SaveData.serialize
-- wrote at SAVE_VERSION 3 / 2 / 1 (no `mutations`).
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local LEGACY_IDS = { "Glow", "Lava", "Galaxy", "Rainbow", "Gold", "Crystal", "Eclipse" }

local function v3Slime(id: string, mutation: any, pad: number): { [string]: any }
	return {
		id = id,
		name = "Globble",
		tier = 4,
		color = { 200, 60, 120 },
		size = 1.25,
		pattern = "Spots",
		eyes = "Happy",
		mouth = "Fang",
		mutation = mutation,
		pad = pad,
	}
end

local function v3Save(slimes: { any }): { [string]: any }
	return {
		version = 3,
		cash = 5000,
		rebirths = 2,
		padsUnlocked = 8,
		slimes = slimes,
		favoriteId = "s1",
		lastOnline = 1000,
		daily = { lastDay = 19000, streak = 3 },
		dex = { "4:Glow:Spots:Happy" },
		totalEarned = 9000,
		totalStolen = 1,
		lockLevel = 1,
		speedCoil = false,
		tutorialStep = 0,
		upgrades = {},
		stats = { caught = 5, merges = 1, locks = 0, sold = 0 },
		goals = {},
		dexRewards = 0,
	}
end

describe("SaveData.migrateV3", function()
	it("turns the single mutation of every existing mutation into a one-entry list", function()
		for _, id in LEGACY_IDS do
			local raw = v3Save({ v3Slime("s1", id, 1) })
			local out = SaveData.migrateV3(raw)
			local slimes = out.slimes :: { any }
			expect(#slimes[1].mutations).toBe(1)
			expect(slimes[1].mutations[1]).toBe(id)
			expect(slimes[1].mutation).toBe(id)
			expect(out.version).toBe(4)
		end
	end)
	it("gives an empty list for None, missing and junk mutation", function()
		local raw = v3Save({ v3Slime("a", "None", 1), v3Slime("b", nil, 2), v3Slime("c", 7, 3) })
		local slimes = SaveData.migrateV3(raw).slimes :: { any }
		for i = 1, 3 do
			expect(#slimes[i].mutations).toBe(0)
		end
	end)
	it("does not mutate its input", function()
		local raw = v3Save({ v3Slime("s1", "Gold", 1) })
		SaveData.migrateV3(raw)
		expect(raw.version).toBe(3)
		expect(((raw.slimes :: any)[1]).mutations).toBe(nil)
	end)
	it("is idempotent", function()
		local raw = v3Save({ v3Slime("s1", "Lava", 1), v3Slime("s2", "None", 2) })
		local once = SaveData.migrateV3(raw)
		local twice = SaveData.migrateV3(once)
		expect(twice.version).toBe(4)
		expect(twice.migratedFrom).toBe(3)
		expect(((twice.slimes :: any)[1]).mutations[1]).toBe("Lava")
		expect(#((twice.slimes :: any)[2]).mutations).toBe(0)
	end)
	it("keeps an existing list untouched (already migrated slimes)", function()
		local slime = v3Slime("s1", "Glow", 1)
		slime.mutations = { "Glow", "Lava" }
		local out = SaveData.migrateV3(v3Save({ slime }))
		expect(#((out.slimes :: any)[1]).mutations).toBe(2)
	end)
	it("handles saves with no slimes and with missing fields", function()
		expect(SaveData.migrateV3({ version = 3 }).version).toBe(4)
		local out = SaveData.migrateV3({ version = 3, slimes = {} })
		expect(#(out.slimes :: any)).toBe(0)
	end)
end)

describe("SaveData.migrate / deserialize of old saves", function()
	it("loads every v3 mutation as a plain slime of the same rarity and size", function()
		for _, id in LEGACY_IDS do
			local d = SaveData.deserialize(v3Save({ v3Slime("s1", id, 1) }))
			local slime = d.slimes[1] :: any
			expect(slime.mutation).toBeNil()
			expect(slime.mutations).toBeNil()
			expect(Genome.baseIncome(slime)).toBe(Config.RARITIES[4].income * 1.25)
			expect(Genome.displayName(slime)).toBe("Epic Globble")
		end
	end)
	it("loads None / missing / unknown mutation as a plain slime", function()
		local d =
			SaveData.deserialize(v3Save({ v3Slime("a", "None", 1), v3Slime("b", nil, 2), v3Slime("c", "Bogus", 3) }))
		for _, slime in d.slimes do
			expect((slime :: any).mutation).toBeNil()
			expect((slime :: any).mutations).toBeNil()
			expect(Genome.baseIncome(slime)).toBe(Config.RARITIES[4].income * 1.25)
		end
	end)
	it("keeps every other v3 field", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("s1", "Gold", 1) }))
		expect(d.cash).toBe(5000)
		expect(d.rebirths).toBe(2)
		expect(d.favoriteId).toBe("s1")
		expect(d.stats.caught).toBe(5)
		expect(d.tutorialStep).toBe(0)
		expect(d.version).toBe(Config.SAVE_VERSION)
	end)
	it("migrates a v2 save through v3 and v4 (the old Steal step ends the tutorial)", function()
		local d = SaveData.deserialize({
			version = 2,
			cash = 10,
			padsUnlocked = 8,
			slimes = { v3Slime("s1", "Eclipse", 1) },
			tutorialStep = 5,
		})
		expect((d.slimes[1] :: any).mutations).toBeNil()
		expect(d.tutorialStep).toBe(0)
		expect(d.stats.caught >= 1).toBe(true)
	end)
	it("migrates a v1 prototype save", function()
		local d = SaveData.deserialize({
			Cash = 99,
			Slimes = { { Id = "x", Rarity = "Epic", Size = 1.5, Color = { 1, 2, 3 } } },
		})
		expect(d.slimes[1].id).toBe("x")
		expect((d.slimes[1] :: any).mutation).toBeNil()
	end)
	it("migrating twice (migrate of a migrate) changes nothing", function()
		local first = SaveData.migrate(v3Save({ v3Slime("s1", "Crystal", 1) })) :: any
		local second = SaveData.migrate(first) :: any
		expect(second.version).toBe(Config.SAVE_VERSION)
		expect(second.migratedFrom).toBe(3)
		expect(second.slimes[1].mutations).toBeNil()
		expect(second.slimes[1].mutation).toBeNil()
	end)
	it("does not corrupt a newer-version save: mutation fields are ignored", function()
		local future = v3Save({ v3Slime("s1", "Glow", 1) })
		future.version = Config.SAVE_VERSION + 3
		((future.slimes :: any)[1]).mutations = { "Glow", "Lava" }
		future.newThing = { 1, 2 }
		local d = SaveData.deserialize(future)
		expect((d.slimes[1] :: any).mutations).toBeNil()
		expect(d.slimes[1].id).toBe("s1")
		expect(d.cash).toBe(5000)
	end)
	it("ignores a hostile mutations list", function()
		local slime = v3Slime("s1", "None", 1)
		slime.mutations = { "Glow", "Glow", "Nope", 5, "Lava", "Galaxy", "Gold" }
		local d = SaveData.deserialize(v3Save({ slime }))
		expect((d.slimes[1] :: any).mutations).toBeNil()
	end)
end)

describe("SaveData round trip", function()
	it("serialize writes the current version and no mutation fields", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("s1", "Lava", 1) }))
		local out = SaveData.serialize(d, 2000)
		expect(out.version).toBe(Config.SAVE_VERSION)
		local s = (out.slimes :: any)[1]
		expect(s.mutation).toBeNil()
		expect(s.mutations).toBeNil()
		expect(out.migratedFrom).toBe(nil)
	end)
	it("a re-serialized save equals itself and never carries migration scratch fields", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("s1", "Galaxy", 1), v3Slime("s2", "None", 2) }))
		local a = SaveData.serialize(d, 3000)
		local b = SaveData.serialize(SaveData.deserialize(a), 3000)
		expect(b).toEqual(a)
	end)
end)
