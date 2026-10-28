--!strict
-- Save v9 -> v10 (SaveData.migrateV9): the Exclusive Shop purchase fields and the roll seeds. The fixture is a table
-- in the exact shape SaveData.serialize wrote at SAVE_VERSION 9.
local Config = require("../src/shared/Config")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")
local serde = require("@lune/serde")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local T = 1700000000

local function slime(id: string, pad: number, tier: number, egg: any?): { [string]: any }
	return {
		id = id,
		name = "Lop",
		tier = tier,
		color = { 120, 200, 90 },
		size = 1,
		pattern = "Plain",
		eyes = "Happy",
		mouth = "Smile",
		pad = pad,
		species = "lop",
		egg = egg,
	}
end

local function v9Save(): { [string]: any }
	return {
		version = 9,
		cash = 5000,
		rebirths = 2,
		padsUnlocked = 8,
		slimes = {
			slime("a", 1, 2),
			slime("b", 2, 2),
			slime("c", 3, 2),
			slime("e", 4, 5, { kind = "golden", hatchAt = T + 600 }),
		},
		lastOnline = T,
		daily = { lastDay = 19000, streak = 3 },
		found = { "lop" },
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
		plotBase = "jar",
		petSeat = "cloud",
		stealLog = {},
		settings = { musicVolume = 0.5, sfxVolume = 0.5, muted = false },
		redeemed = {},
		boost = { mult = 1, untilAt = 0 },
		consumables = { slot = 0, bought = {}, held = {} },
		pvp = { tiers = {}, traps = {}, fun = {} },
		boss = { hits = 0, wins = {}, hauls = 0, mvps = 0, badges = {} },
		eggLuck = {},
		weekly = { week = 0, base = 0 },
		vat = { ids = { "a", "b", "c" }, endsAt = T + 300 },
	}
end

describe("SaveData.migrateV9", function()
	it("stamps a v9 save as version 10 with empty purchase fields", function()
		local out = SaveData.migrateV9(v9Save())
		expect(out.version).toBe(10)
		expect(out.migratedFrom).toBe(9)
		expect(Config.SAVE_VERSION).toBe(10)
		expect(out.ownedSeats).toEqual({})
		expect(out.receipts).toEqual({})
		expect(out.starterBundle).toBe(false)
		expect(out.credits).toEqual({ brew = 0, hatch = 0 })
		expect(out.offlineDouble).toBeNil()
	end)
	it("does not mutate its input and is idempotent", function()
		local raw = v9Save()
		local once = SaveData.migrateV9(raw)
		expect(raw.ownedSeats).toBeNil()
		once.ownedSeats = { "ufo" }
		expect(SaveData.migrateV9(once).ownedSeats).toEqual({ "ufo" })
	end)
	it("loads an old vat and egg without a seed, so they roll as before", function()
		local d = SaveData.deserialize(v9Save())
		expect(d.vat and d.vat.endsAt).toBe(T + 300)
		expect(d.vat and d.vat.seed).toBeNil()
		local egg = d.slimes[4].egg
		expect(egg and egg.kind).toBe("golden")
		expect(egg and egg.seed).toBeNil()
		expect(d.ownedSeats).toEqual({})
		expect(d.credits).toEqual({ brew = 0, hatch = 0 })
		expect(d.starterBundle).toBe(false)
	end)
end)

describe("SaveData v10 purchase fields", function()
	it("cleans junk: unknown and free seats, repeats, bad receipts, credits out of range, bad seeds", function()
		local raw = SaveData.migrateV9(v9Save())
		raw.version = 10
		raw.ownedSeats = { "ufo", "cloud", "nope", "ufo", 7, "leaf" }
		raw.receipts = { "r1", "", "r1", 5, "r2" }
		raw.starterBundle = "yes"
		raw.credits = { brew = 500, hatch = -3 }
		raw.offlineDouble = { cash = "lots", at = T }
		raw.vat.seed = 1.5
		raw.slimes[4].egg.seed = -1
		local d = SaveData.deserialize(raw)
		expect(d.ownedSeats).toEqual({ "ufo", "leaf" })
		expect(d.receipts).toEqual({ "r1", "r2" })
		expect(d.starterBundle).toBe(false)
		expect(d.credits).toEqual({ brew = Config.EXCLUSIVE_SHOP.creditMax, hatch = 0 })
		expect(d.offlineDouble).toBeNil()
		expect(d.vat and d.vat.seed).toBeNil()
		expect(d.slimes[4].egg and d.slimes[4].egg.seed).toBeNil()
	end)
	it("keeps only the newest receipts", function()
		local raw = SaveData.migrateV9(v9Save())
		local list = {}
		for i = 1, Config.EXCLUSIVE_SHOP.receiptMemory + 5 do
			list[i] = `r{i}`
		end
		raw.receipts = list
		local d = SaveData.deserialize(raw)
		expect(#d.receipts).toBe(Config.EXCLUSIVE_SHOP.receiptMemory)
		expect(d.receipts[1]).toBe("r6")
	end)
	it("round-trips every field through JSON", function()
		local d = SaveData.deserialize(v9Save())
		d.ownedSeats = { "ufo", "magic_carpet" }
		d.receipts = { "p1", "p2" }
		d.starterBundle = true
		d.credits = { brew = 2, hatch = 1 }
		d.offlineDouble = { cash = 1234, at = T + 5, used = true }
		(d.vat :: any).seed = 424242
		(d.slimes[4].egg :: any).seed = 99
		d.petSeat = "ufo"
		local back = SaveData.deserialize(serde.decode("json", serde.encode("json", SaveData.serialize(d, T + 10))))
		expect(back.ownedSeats).toEqual({ "ufo", "magic_carpet" })
		expect(back.receipts).toEqual({ "p1", "p2" })
		expect(back.starterBundle).toBe(true)
		expect(back.credits).toEqual({ brew = 2, hatch = 1 })
		expect(back.offlineDouble).toEqual({ cash = 1234, at = T + 5, used = true })
		expect(back.vat and back.vat.seed).toBe(424242)
		expect(back.slimes[4].egg and back.slimes[4].egg.seed).toBe(99)
		expect(back.petSeat).toBe("ufo")
		expect((back :: any).passIncomeMult).toBeNil()
	end)
	it("never saves the runtime Game Pass factors", function()
		local d = SaveData.deserialize(v9Save())
		d.passIncomeMult, d.passOfflineRate = 2, 0.5
		local raw = SaveData.serialize(d, T)
		expect(raw.passIncomeMult).toBeNil()
		expect(raw.passOfflineRate).toBeNil()
	end)
end)
