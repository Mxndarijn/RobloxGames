--!strict
-- Save v8 -> v9 (SaveData.migrateV8): the boss trophy list becomes the boss record. Fixtures are tables in the exact
-- shape SaveData.serialize wrote at SAVE_VERSION 8.
local Config = require("../src/shared/Config")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function trophy(id: string, species: string, tier: number): { [string]: any }
	return {
		id = id,
		name = species,
		tier = tier,
		color = { 120, 200, 90 },
		size = Config.MAX_SIZE,
		pattern = "Plain",
		eyes = "Happy",
		mouth = "Smile",
		species = species,
	}
end

local function v8Save(trophies: any): { [string]: any }
	return {
		version = 8,
		cash = 5000,
		rebirths = 2,
		padsUnlocked = 8,
		slimes = {},
		lastOnline = 1700000000,
		daily = { lastDay = 19000, streak = 3 },
		found = { "moo" },
		totalEarned = 9000,
		totalStolen = 1,
		speedCoil = false,
		tutorialStep = 0,
		upgrades = {},
		stats = { caught = 5, merges = 1, locks = 0, sold = 0 },
		goals = {},
		speciesRewards = 0,
		quests = { day = 0, slots = {} },
		plotSkin = "classic",
		stealLog = {},
		settings = { musicVolume = 0.5, sfxVolume = 0.5, muted = false },
		redeemed = {},
		boost = { mult = 1, untilAt = 0 },
		consumables = { slot = 0, bought = {}, held = {} },
		pvp = { tiers = {}, traps = {}, fun = {} },
		trophies = trophies,
		eggLuck = {},
	}
end

describe("SaveData.migrateV8", function()
	it("stamps a v8 save as version 9, migrated from 8", function()
		local out = SaveData.migrateV8(v8Save({}))
		expect(out.version).toBe(9)
		expect(out.migratedFrom).toBe(8)
	end)
	it("turns each boss trophy into one win of its species and drops the list", function()
		local out = SaveData.migrateV8(v8Save({
			trophy("t1", "goozilla", 6),
			trophy("t2", "mecha_goo", Config.SECRET_TIER),
			trophy("t3", "gummy", 1),
			"junk",
			{ species = 7 },
		}))
		expect(out.trophies).toBeNil()
		expect(out.boss).toEqual({ hits = 0, wins = { goozilla = 1, mecha_goo = 1 }, hauls = 0, mvps = 0, badges = {} })
	end)
	it("handles a save without trophies or with junk", function()
		expect(SaveData.migrateV8(v8Save(nil)).boss.wins).toEqual({})
		expect(SaveData.migrateV8(v8Save("junk")).boss.wins).toEqual({})
	end)
	it("does not mutate its input and is idempotent", function()
		local raw = v8Save({ trophy("t1", "queen_jelly", 6) })
		local once = SaveData.migrateV8(raw)
		expect(#raw.trophies).toBe(1)
		expect(raw.boss).toBeNil()
		local twice = SaveData.migrateV8(once)
		expect(twice.boss).toEqual(once.boss)
	end)
	it("loads with the win badges granted, the species found, and no trophy income", function()
		local d = SaveData.deserialize(v8Save({ trophy("t1", "goozilla", 6), trophy("t2", "queen_jelly", 6) }))
		expect(d.boss.wins).toEqual({ goozilla = 1, queen_jelly = 1 })
		expect(d.boss.badges).toEqual({ BossGoozilla = 1700000000, BossQueenJelly = 1700000000 })
		expect(d.found.goozilla).toBe(true)
		expect(d.found.queen_jelly).toBe(true)
		expect(d.found.moo).toBe(true)
		expect((d :: any).trophies).toBeNil()
		expect(d.slimes).toEqual({})
		local again = SaveData.serialize(d, 1700000500)
		expect(again.version).toBe(Config.SAVE_VERSION)
		expect(again.trophies).toBeNil()
		expect(again.boss.badges).toEqual(d.boss.badges)
	end)
end)
