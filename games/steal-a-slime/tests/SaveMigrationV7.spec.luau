--!strict
-- Save v6 -> v7 (SaveData.migrateV6): everything mutation related is stripped from an old save. Fixtures are
-- tables in the exact shape SaveData.serialize wrote at SAVE_VERSION 6, with mutations (a combo and a weather
-- mutation included), Dex stamps, MutationSpray stock and a RainMagnet level.
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function v6Slime(id: string, mutation: string, mutations: { string }, pad: number): { [string]: any }
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
		mutations = mutations,
		pad = pad,
		species = "gummy",
	}
end

local function v6Save(): { [string]: any }
	return {
		version = 6,
		cash = 5000,
		rebirths = 2,
		padsUnlocked = 8,
		slimes = {
			v6Slime("s1", "Solar", { "Solar" }, 1), -- combo
			v6Slime("s2", "Wet", { "Wet" }, 2), -- weather mutation
			v6Slime("s3", "Royal", { "Royal", "Frozen", "Glow" }, 3), -- stacked
			v6Slime("s4", "None", {}, 4),
		},
		favoriteId = "s1",
		lastOnline = 1000,
		daily = { lastDay = 19000, streak = 3 },
		found = { "gummy" },
		stamps = { "gummy:None", "gummy:Glow", "gummy:Solar", "gummy:Wet" },
		totalEarned = 9000,
		totalStolen = 1,
		lockLevel = 1,
		speedCoil = false,
		tutorialStep = 0,
		upgrades = { Income = 2, RainMagnet = 3 },
		stats = { caught = 5, merges = 1, locks = 0, sold = 0 },
		goals = {},
		speciesRewards = 1,
		stampRewards = 2,
		plotSkin = "classic",
		stealLog = {},
		settings = { musicVolume = 0.5, sfxVolume = 0.5, muted = false },
		consumables = {
			slot = 77,
			bought = { MutationSpray = 1, LuckPotion = 2 },
			held = { MutationSpray = 4, LuckPotion = 1 },
		},
		trophies = { v6Slime("t1", "Glow", { "Glow" }, 1) },
	}
end

describe("SaveData.migrateV6", function()
	it("is one version above v6 and strips the mutation fields of every slime and trophy", function()
		expect(Config.SAVE_VERSION).toBe(7)
		local out = SaveData.migrateV6(v6Save())
		expect(out.version).toBe(7)
		expect(out.migratedFrom).toBe(6)
		for _, list in { out.slimes :: { any }, out.trophies :: { any } } do
			for _, slime in list do
				expect(slime.mutation).toBeNil()
				expect(slime.mutations).toBeNil()
			end
		end
		local first = (out.slimes :: { any })[1]
		expect(first.species).toBe("gummy")
		expect(first.size).toBe(1.25)
	end)
	it("drops Dex stamps, stamp rewards, MutationSpray stock and the RainMagnet level", function()
		local out = SaveData.migrateV6(v6Save())
		expect(out.stamps).toBeNil()
		expect(out.stampRewards).toBeNil()
		expect((out.upgrades :: any).RainMagnet).toBeNil()
		expect((out.upgrades :: any).Income).toBe(2)
		expect((out.consumables :: any).bought.MutationSpray).toBeNil()
		expect((out.consumables :: any).held.MutationSpray).toBeNil()
		expect((out.consumables :: any).bought.LuckPotion).toBe(2)
		expect((out.consumables :: any).held.LuckPotion).toBe(1)
		expect((out.found :: any)[1]).toBe("gummy")
	end)
	it("does not mutate its input and is idempotent", function()
		local raw = v6Save()
		local once = SaveData.migrateV6(raw)
		expect(raw.version).toBe(6)
		expect(((raw.slimes :: any)[1]).mutation).toBe("Solar")
		expect((raw.upgrades :: any).RainMagnet).toBe(3)
		expect((raw.consumables :: any).held.MutationSpray).toBe(4)
		local twice = SaveData.migrateV6(once)
		expect(twice).toEqual(once)
	end)
	it("handles saves with missing or junk fields", function()
		expect(SaveData.migrateV6({ version = 6 }).version).toBe(7)
		local out = SaveData.migrateV6({ version = 6, slimes = "junk", upgrades = 5, consumables = { bought = 3 } })
		expect(out.version).toBe(7)
		expect(out.slimes).toBe("junk")
	end)
end)

describe("SaveData.deserialize of a v6 save with mutations", function()
	it("loads every slime plain: same rarity and size, no mutation fields", function()
		local d = SaveData.deserialize(v6Save())
		expect(#d.slimes).toBe(4)
		for _, slime in d.slimes do
			expect((slime :: any).mutation).toBeNil()
			expect((slime :: any).mutations).toBeNil()
			expect(Genome.baseIncome(slime)).toBe(Config.RARITIES[4].income * 1.25)
			expect(Genome.displayName(slime)).toBe("Epic Globble")
		end
		expect(d.version).toBe(Config.SAVE_VERSION)
		expect(d.favoriteId).toBe("s1")
		expect(d.cash).toBe(5000)
	end)
	it("keeps species found, drops stamps and the removed upgrade and consumable", function()
		local d = SaveData.deserialize(v6Save())
		expect(d.found.gummy).toBe(true)
		expect((d :: any).stamps).toBeNil()
		expect((d :: any).stampRewards).toBeNil()
		expect(d.speciesRewards).toBe(1)
		expect(d.upgrades.Income).toBe(2)
		expect(d.upgrades.RainMagnet).toBeNil()
		expect(d.consumables.bought.MutationSpray).toBeNil()
		expect(d.consumables.held.MutationSpray).toBeNil()
		expect(d.consumables.held.LuckPotion).toBe(1)
		expect(#d.trophies).toBe(0) -- t1 is not a boss species
	end)
	it("serializes with no mutation, stamp or removed-item fields and re-serializes equal", function()
		local d = SaveData.deserialize(v6Save())
		local out = SaveData.serialize(d, 2000)
		expect(out.version).toBe(7)
		expect(out.stamps).toBeNil()
		expect(out.stampRewards).toBeNil()
		for _, slime in out.slimes :: { any } do
			expect(slime.mutation).toBeNil()
			expect(slime.mutations).toBeNil()
		end
		expect(SaveData.serialize(SaveData.deserialize(out), 2000)).toEqual(out)
	end)
	it("a newer save with mutation fields is read without errors", function()
		local future = v6Save()
		future.version = Config.SAVE_VERSION + 2
		local d = SaveData.deserialize(future)
		expect(#d.slimes).toBe(4)
		expect((d.slimes[1] :: any).mutations).toBeNil()
	end)
end)
