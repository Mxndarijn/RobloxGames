--!strict
-- Save v10 -> v11 (SaveData.migrateV10): carry trails, Bat skins, lock break and gift credits. The fixture is a table in
-- the exact shape SaveData.serialize wrote at SAVE_VERSION 10.
local Config = require("../src/shared/Config")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")
local serde = require("@lune/serde")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local T = 1700000000

local function v10Save(): { [string]: any }
	return {
		version = 10,
		cash = 5000,
		rebirths = 2,
		padsUnlocked = 8,
		slimes = {
			{
				id = "a",
				name = "Lop",
				tier = 2,
				color = { 120, 200, 90 },
				size = 1,
				pattern = "Plain",
				eyes = "Happy",
				mouth = "Smile",
				pad = 1,
				species = "lop",
			},
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
		petSeat = "ufo",
		stealLog = {},
		settings = { musicVolume = 0.5, sfxVolume = 0.5, muted = false },
		redeemed = {},
		boost = { mult = 1, untilAt = 0 },
		consumables = { slot = 0, bought = {}, held = {} },
		pvp = { tiers = {}, traps = {}, fun = {} },
		boss = { hits = 0, wins = {}, hauls = 0, mvps = 0, badges = {} },
		eggLuck = {},
		weekly = { week = 0, base = 0 },
		ownedSeats = { "ufo" },
		receipts = { "p1" },
		starterBundle = true,
		credits = { brew = 1, hatch = 0 },
	}
end

describe("SaveData.migrateV10", function()
	it("stamps a v10 save as version 11 with empty trail, skin, lock break and gift fields", function()
		local out = SaveData.migrateV10(v10Save())
		expect(out.version).toBe(11)
		expect(out.migratedFrom).toBe(10)
		expect(out.ownedTrails).toEqual({})
		expect(out.trail).toBeNil()
		expect(out.ownedBatSkins).toEqual({})
		expect(out.batSkin).toBeNil()
		expect(out.lockBreakCredits).toBe(0)
		expect(out.giftCredits).toEqual({})
	end)

	it("does not mutate its input and is idempotent", function()
		local raw = v10Save()
		local once = SaveData.migrateV10(raw)
		expect(raw.ownedTrails).toBeNil()
		once.ownedTrails = { "hearts" }
		once.lockBreakCredits = 3
		local twice = SaveData.migrateV10(once)
		expect(twice.ownedTrails).toEqual({ "hearts" })
		expect(twice.lockBreakCredits).toBe(3)
	end)

	it("loads a v10 save with its v10 purchases kept and nothing new owned", function()
		local d = SaveData.deserialize(v10Save())
		expect(d.ownedSeats).toEqual({ "ufo" })
		expect(d.petSeat).toBe("ufo")
		expect(d.receipts).toEqual({ "p1" })
		expect(d.ownedTrails).toEqual({})
		expect(d.trail).toBeNil()
		expect(d.ownedBatSkins).toEqual({})
		expect(d.batSkin).toBeNil()
		expect(d.lockBreakCredits).toBe(0)
		expect(d.giftCredits).toEqual({})
	end)
end)

describe("SaveData v11 fields", function()
	it(
		"cleans junk: unknown and repeated ids, unowned equipped ids, bad credit counts, gift keys not giftable",
		function()
			local raw = SaveData.migrateV10(v10Save())
			raw.ownedTrails = { "rainbow", "nope", "rainbow", 4, "hearts" }
			raw.trail = "sparkle" -- not owned
			raw.ownedBatSkins = { "golden", "wood" }
			raw.batSkin = 7
			raw.lockBreakCredits = 1e9
			raw.giftCredits =
				{ "Seat_ufo", "LockBreak", "Gift_Seat_ufo", "Trail_hearts", 3, "Trail_hearts", "Income2x" }
			local d = SaveData.deserialize(raw)
			expect(d.ownedTrails).toEqual({ "rainbow", "hearts" })
			expect(d.trail).toBeNil()
			expect(d.ownedBatSkins).toEqual({ "golden" })
			expect(d.batSkin).toBeNil()
			expect(d.lockBreakCredits).toBe(Config.EXCLUSIVE_SHOP.creditMax)
			expect(d.giftCredits).toEqual({ "Seat_ufo", "Trail_hearts", "Trail_hearts" })
			raw.lockBreakCredits = -2
			expect(SaveData.deserialize(raw).lockBreakCredits).toBe(0)
		end
	)

	it("keeps at most gift.creditMax unsent gifts", function()
		local raw = SaveData.migrateV10(v10Save())
		local list = {}
		for i = 1, Config.EXCLUSIVE_SHOP.gift.creditMax + 5 do
			list[i] = "Seat_leaf"
		end
		raw.giftCredits = list
		expect(#SaveData.deserialize(raw).giftCredits).toBe(Config.EXCLUSIVE_SHOP.gift.creditMax)
	end)

	it("round-trips every field through JSON and never saves the runtime lock break", function()
		local d = SaveData.deserialize(v10Save())
		d.ownedTrails = { "starfall", "goo_drip" }
		d.trail = "goo_drip"
		d.ownedBatSkins = { "fish" }
		d.batSkin = "fish"
		d.lockBreakCredits = 2
		d.giftCredits = { "BatSkin_golden", "Seat_ufo" }
		local raw = SaveData.serialize(d, T + 10)
		expect(raw.version).toBe(Config.SAVE_VERSION)
		local back = SaveData.deserialize(serde.decode("json", serde.encode("json", raw)))
		expect(back.ownedTrails).toEqual({ "starfall", "goo_drip" })
		expect(back.trail).toBe("goo_drip")
		expect(back.ownedBatSkins).toEqual({ "fish" })
		expect(back.batSkin).toBe("fish")
		expect(back.lockBreakCredits).toBe(2)
		expect(back.giftCredits).toEqual({ "BatSkin_golden", "Seat_ufo" })
		expect(raw.lockBreak).toBeNil()
	end)

	it("writes an unowned equipped trail or skin as none", function()
		local d = SaveData.deserialize(v10Save())
		d.trail = "rainbow"
		d.batSkin = "golden"
		local raw = SaveData.serialize(d, T)
		expect(raw.trail).toBeNil()
		expect(raw.batSkin).toBeNil()
	end)
end)
