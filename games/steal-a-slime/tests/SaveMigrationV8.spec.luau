--!strict
-- Save v7 -> v8 (SaveData.migrateV7): Goo Traps became charges. An owned trap tier (pvp.tiers.Trap) turns into a
-- full stack of charges of that tier. Fixtures are tables in the exact shape SaveData.serialize wrote at SAVE_VERSION 7.
local Config = require("../src/shared/Config")
local PvpRules = require("../src/shared/PvpRules")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function v7Save(pvp: any): { [string]: any }
	return {
		version = 7,
		cash = 5000,
		rebirths = 12,
		padsUnlocked = 8,
		slimes = {},
		lastOnline = 1000,
		daily = { lastDay = 19000, streak = 3 },
		found = {},
		totalEarned = 9000,
		totalStolen = 1,
		lockLevel = 1,
		speedCoil = false,
		tutorialStep = 0,
		upgrades = { Income = 2 },
		stats = { caught = 5, merges = 1, locks = 0, sold = 0 },
		goals = {},
		speciesRewards = 1,
		plotSkin = "classic",
		stealLog = {},
		settings = { musicVolume = 0.5, sfxVolume = 0.5, muted = false },
		consumables = { slot = 77, bought = {}, held = {} },
		pvp = pvp,
		trophies = {},
	}
end

describe("SaveData.migrateV7", function()
	it("stamps a v7 save as version 8, migrated from 7", function()
		local out = SaveData.migrateV7(v7Save({ tiers = { Knockback = 4, Trap = 2 }, fun = {}, played = 600 }))
		expect(out.version).toBe(8)
		expect(out.migratedFrom).toBe(7)
	end)
	it("turns an owned trap tier into a full stack of that tier and keeps the other lines", function()
		local out = SaveData.migrateV7(
			v7Save({ tiers = { Knockback = 4, Trap = 2, Blaster = 1 }, fun = { "FunConfetti" }, played = 600 })
		)
		expect(out.pvp.tiers).toEqual({ Knockback = 4, Blaster = 1 })
		expect(out.pvp.traps).toEqual({ GooTrap2 = Config.PVP.TRAP_MAX_HELD })
		expect(out.pvp.fun).toEqual({ "FunConfetti" })
	end)
	it("loads into PlayerData with the charges owned", function()
		local d = SaveData.deserialize(v7Save({ tiers = { Trap = 3 }, fun = {}, played = 900 }))
		expect(PvpRules.charges(d, "GooTrap3")).toBe(Config.PVP.TRAP_MAX_HELD)
		expect(PvpRules.owns(d, "GooTrap3")).toBe(true)
		expect(PvpRules.owns(d, "GooTrap1")).toBe(false)
		expect(d.pvp.tiers.Trap).toBeNil()
		local again = SaveData.serialize(d, 2000)
		expect(again.version).toBe(Config.SAVE_VERSION)
		expect(again.pvp.traps).toEqual({ GooTrap3 = Config.PVP.TRAP_MAX_HELD })
		expect(again.pvp.tiers).toEqual({})
	end)
	it("does not mutate its input and is idempotent", function()
		local raw = v7Save({ tiers = { Trap = 1 }, fun = {}, played = 0 })
		local once = SaveData.migrateV7(raw)
		expect(raw.pvp.tiers.Trap).toBe(1)
		expect(raw.pvp.traps).toBeNil()
		local twice = SaveData.migrateV7(once)
		expect(twice.pvp.traps).toEqual({ GooTrap1 = Config.PVP.TRAP_MAX_HELD })
		expect(twice.pvp.tiers).toEqual({})
	end)
	it("handles saves without pvp, without a trap tier, or with junk", function()
		expect(SaveData.migrateV7(v7Save(nil)).pvp).toBeNil()
		expect(SaveData.migrateV7(v7Save({ tiers = { Knockback = 1 }, fun = {}, played = 0 })).pvp.traps).toBeNil()
		expect(SaveData.migrateV7(v7Save("junk")).pvp).toBe("junk")
		local out = SaveData.migrateV7(v7Save({ tiers = { Trap = "x" }, fun = {}, played = 0 }))
		expect(out.pvp.traps).toBeNil()
		expect(SaveData.deserialize(v7Save({ tiers = { Trap = 0 / 0 } })).pvp.traps).toEqual({})
	end)
end)
