--!strict
-- Save v3 -> v4 (slime.mutation -> slime.mutations list). Fixtures are tables in the
-- exact shape SaveData.serialize wrote at SAVE_VERSION 3 / 2 / 1 (no `mutations`).
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

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

-- income the way v3 computed it: one multiplier from the single field
local function legacyIncome(tier: number, size: number, mutation: string): number
	local mult = 1
	for _, m in Config.MUTATIONS do
		if m.name == mutation then
			mult = m.multiplier
		end
	end
	return Config.RARITIES[tier].income * size * mult
end

describe("SaveData.migrateV3", function()
	it("turns the single mutation of every existing mutation into a one-entry list", function()
		for i, m in Config.MUTATIONS do
			local raw = v3Save({ v3Slime("s1", m.name, 1) })
			local out = SaveData.migrateV3(raw)
			local slimes = out.slimes :: { any }
			expect(#slimes[1].mutations).toBe(1)
			expect(slimes[1].mutations[1]).toBe(m.name)
			expect(slimes[1].mutation).toBe(m.name)
			expect(out.version).toBe(4)
			expect(i > 0).toBe(true)
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
	it("loads every v3 mutation with identical value and behaviour", function()
		for _, m in Config.MUTATIONS do
			local d = SaveData.deserialize(v3Save({ v3Slime("s1", m.name, 1) }))
			local slime = d.slimes[1]
			expect(slime.mutation).toBe(m.name)
			expect(#(slime.mutations :: { string })).toBe(1)
			expect(Genome.baseIncome(slime)).toBe(legacyIncome(4, 1.25, m.name))
			expect(Genome.primaryMutation(Genome.mutationList(slime))).toBe(m.name)
			expect(Genome.displayName(slime)).toBe(`{m.displayName} Epic Globble`)
		end
	end)
	it("loads None / missing mutation as no mutations", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("a", "None", 1), v3Slime("b", nil, 2) }))
		for _, slime in d.slimes do
			expect(slime.mutation).toBe("None")
			expect(#(slime.mutations :: { string })).toBe(0)
			expect(Genome.baseIncome(slime)).toBe(legacyIncome(4, 1.25, "None"))
		end
	end)
	it("drops an unknown mutation id exactly like v3 did", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("a", "Bogus", 1) }))
		expect(d.slimes[1].mutation).toBe("None")
		expect(#(d.slimes[1].mutations :: { string })).toBe(0)
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
	it("migrates a v2 save through v3 and v4 (tutorial shift still applies)", function()
		local d = SaveData.deserialize({
			version = 2,
			cash = 10,
			padsUnlocked = 8,
			slimes = { v3Slime("s1", "Eclipse", 1) },
			tutorialStep = 5,
		})
		expect(d.slimes[1].mutations).toEqual({ "Eclipse" })
		expect(d.tutorialStep).toBe(6)
		expect(d.stats.caught >= 1).toBe(true)
	end)
	it("migrates a v1 prototype save", function()
		local d = SaveData.deserialize({
			Cash = 99,
			Slimes = { { Id = "x", Rarity = "Epic", Size = 1.5, Color = { 1, 2, 3 } } },
		})
		expect(d.slimes[1].mutation).toBe("None")
		expect(#(d.slimes[1].mutations :: { string })).toBe(0)
	end)
	it("migrating twice (migrate of a migrate) changes nothing", function()
		local first = SaveData.migrate(v3Save({ v3Slime("s1", "Crystal", 1) })) :: any
		local second = SaveData.migrate(first) :: any
		expect(second.version).toBe(6)
		expect(second.migratedFrom).toBe(3)
		expect(second.slimes[1].mutations[1]).toBe("Crystal")
	end)
	it("does not corrupt a newer-version save: lists and legacy field both read", function()
		local future = v3Save({ v3Slime("s1", "Glow", 1) })
		future.version = 9
		((future.slimes :: any)[1]).mutations = { "Glow", "Lava" }
		future.newThing = { 1, 2 }
		local d = SaveData.deserialize(future)
		expect(d.slimes[1].mutations).toEqual({ "Glow", "Lava" })
		expect(d.cash).toBe(5000)
		-- legacy-only future slime still loads
		future.slimes = { v3Slime("s1", "Gold", 1) }
		expect(SaveData.deserialize(future).slimes[1].mutations).toEqual({ "Gold" })
	end)
	it("sanitizes a hostile mutations list (dupes, unknown, over the cap)", function()
		local slime = v3Slime("s1", "None", 1)
		slime.mutations = { "Glow", "Glow", "Nope", 5, "Lava", "Galaxy", "Gold" }
		local d = SaveData.deserialize(v3Save({ slime }))
		expect(d.slimes[1].mutations).toEqual({ "Glow", "Lava", "Galaxy" })
	end)
end)

describe("SaveData round trip (v4)", function()
	it("serialize writes the current version, the list and the legacy field", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("s1", "Lava", 1) }))
		local out = SaveData.serialize(d, 2000)
		expect(out.version).toBe(Config.SAVE_VERSION)
		local s = (out.slimes :: any)[1]
		expect(s.mutation).toBe("Lava")
		expect(s.mutations).toEqual({ "Lava" })
		expect(out.migratedFrom).toBe(nil)
	end)
	it("save -> load -> save is stable for stacked slimes", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("s1", "None", 1) }))
		Genome.setMutations(d.slimes[1], { "Gold", "Glow", "Solar" })
		local saved = SaveData.serialize(d, 2000)
		local loaded = SaveData.deserialize(saved)
		expect(loaded.slimes[1].mutations).toEqual({ "Gold", "Glow", "Solar" })
		expect(loaded.slimes[1].mutation).toBe("Gold") -- 5 beats Solar 4
		local again = SaveData.serialize(loaded, 2000)
		expect(again.slimes).toEqual(saved.slimes)
	end)
	it("a v4 save re-serialized equals itself and never carries migration scratch fields", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("s1", "Galaxy", 1), v3Slime("s2", "None", 2) }))
		local a = SaveData.serialize(d, 3000)
		local b = SaveData.serialize(SaveData.deserialize(a), 3000)
		expect(b).toEqual(a)
	end)
	it("a v3 reader of the v4 output still sees the single mutation field", function()
		local d = SaveData.deserialize(v3Save({ v3Slime("s1", "Rainbow", 1) }))
		local s = (SaveData.serialize(d, 1).slimes :: any)[1]
		expect(s.mutation).toBe("Rainbow")
	end)
end)
