--!strict
-- Save v11 -> v12 (SaveData.migrateV11): the tutorial's step list changed, so a saved `tutorialStep` moves onto the
-- new order. The fixture is a table in the shape SaveData.serialize wrote at SAVE_VERSION 11.
local Config = require("../src/shared/Config")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")
local TutorialProgress = require("../src/shared/TutorialProgress")
local serde = require("@lune/serde")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function v11Save(step: number): { [string]: any }
	return {
		version = 11,
		cash = 800,
		rebirths = 0,
		padsUnlocked = Config.PADS_START,
		slimes = {},
		lastOnline = 1700000000,
		totalEarned = 900,
		totalStolen = 0,
		speedCoil = false,
		tutorialStep = step,
		upgrades = {},
		stats = { caught = 1, merges = 0, locks = 1, sold = 0 },
		ownedTrails = {},
		ownedBatSkins = {},
		lockBreakCredits = 0,
		giftCredits = {},
	}
end

-- v11 order: Grab, Deposit, Lock, BuyPad, Merge, Steal, Rebirth.
local RESUMES_AT = {
	[0] = "done",
	[1] = "Grab",
	[2] = "Deposit",
	[3] = "Lock",
	[4] = "Leaderboard", -- was BuyPad: the new walking steps come first
	[5] = "Merge",
	[6] = "done", -- Steal is gone
	[7] = "done", -- Rebirth is gone
}

describe("SaveData.migrateV11", function()
	it("stamps version 12 and maps every old step onto the new list", function()
		expect(Config.SAVE_VERSION >= 12).toBe(true) -- later versions chain on (SaveData.migrate)
		for old, want in RESUMES_AT do
			local out = SaveData.migrateV11(v11Save(old))
			expect(out.version).toBe(12)
			local id = TutorialProgress.currentId({ tutorialStep = out.tutorialStep }) or "done"
			expect(id).toBe(want)
		end
	end)

	it("does not mutate its input, keeps a missing step missing and clamps junk", function()
		local raw = v11Save(5)
		SaveData.migrateV11(raw)
		expect(raw.tutorialStep).toBe(5)
		local none = v11Save(0)
		none.tutorialStep = nil
		expect(SaveData.migrateV11(none).tutorialStep).toBeNil()
		expect(SaveData.migrateV11(v11Save(99)).tutorialStep).toBe(0)
		expect(SaveData.migrateV11(v11Save(-3)).tutorialStep).toBe(0)
	end)

	it("loads through deserialize and round-trips without moving the step again", function()
		local d = SaveData.deserialize(v11Save(5))
		expect(TutorialProgress.currentId(d)).toBe("Merge")
		local back = SaveData.deserialize(serde.decode("json", serde.encode("json", SaveData.serialize(d, 1700000100))))
		expect(TutorialProgress.currentId(back)).toBe("Merge")
	end)
end)
