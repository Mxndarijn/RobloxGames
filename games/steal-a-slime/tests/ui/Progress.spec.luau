--!strict
-- Rebirth ladder and SlimeDex completion (src/ui/Progress.luau).
local Config = require("../../src/shared/Config")
local Economy = require("../../src/shared/Economy")
local Progress = require("../../src/ui/Progress")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local function state(rebirths: number, cash: number): any
	return {
		rebirths = rebirths,
		rebirthMultiplier = Economy.rebirthMultiplier(rebirths),
		rebirthCost = Economy.rebirthCost(rebirths),
		canRebirth = cash >= Economy.rebirthCost(rebirths),
		lockDuration = 75,
		cash = cash,
	}
end

describe("Progress.rebirthTiers", function()
	it("lists the current tier and the next ones with server costs", function()
		local tiers = Progress.rebirthTiers(state(1, 0), Config, Economy.rebirthCost, 3)
		expect(#tiers).toBe(4)
		expect(tiers[1].current).toBe(true)
		expect(tiers[1].cost).toBeNil()
		expect(tiers[2].rebirth).toBe(2)
		expect(tiers[2].multiplier).toBeCloseTo(Economy.rebirthMultiplier(2))
		expect(tiers[2].cost).toBe(Economy.rebirthCost(1))
		expect(tiers[4].cost).toBe(Economy.rebirthCost(3))
		expect(tiers[3].lockSeconds).toBe(75 + 2 * Config.LOCK_SECONDS_PER_REBIRTH)
	end)
	it("stops at MAX_REBIRTHS", function()
		local tiers = Progress.rebirthTiers(state(Config.MAX_REBIRTHS - 1, 0), Config, Economy.rebirthCost, 3)
		expect(#tiers).toBe(2)
	end)
	it("formats a tier line", function()
		local tiers = Progress.rebirthTiers(state(0, 0), Config, Economy.rebirthCost, 1)
		expect(Progress.tierText(tiers[1])).toBe("Now · rebirth 0: x1 income · 75s lock")
		expect(Progress.tierText(tiers[2])).toBe(
			`Rebirth 1: x1.5 income · {75 + Config.LOCK_SECONDS_PER_REBIRTH}s lock · $5K`
		)
	end)
end)

describe("Progress.rebirthStatus", function()
	it("shows what's missing, READY, or maxed", function()
		local s = Progress.rebirthStatus(state(0, 1250), Config.MAX_REBIRTHS)
		expect(s.ready).toBe(false)
		expect(s.fraction).toBeCloseTo(0.25)
		expect(s.text).toBe("$3.75K more needed (25%)")
		expect(Progress.rebirthStatus(state(0, 6000), Config.MAX_REBIRTHS).text).toBe("READY! Rebirth now")
		local maxed = Progress.rebirthStatus(state(Config.MAX_REBIRTHS, 0), Config.MAX_REBIRTHS)
		expect(maxed.maxed).toBe(true)
	end)
end)

describe("Progress.dex", function()
	it("gives percent, fraction and per-rarity counts", function()
		local p = Progress.dex({ "1:None:Plain:Round", "1:Glow:Spots:Wide", "3:None:Belly:Happy" }, 720, TIERS)
		expect(p.count).toBe(3)
		expect(p.percent).toBe("0%")
		expect(p.fraction).toBeCloseTo(3 / 720)
		expect(p.byTier[1].count).toBe(2)
		expect(p.byTier[1].total).toBe(120)
		expect(p.byTier[3].count).toBe(1)
		expect(p.byTier[6].count).toBe(0)
	end)
	it("handles empty / missing data", function()
		local p = Progress.dex(nil, 0, TIERS)
		expect(p.count).toBe(0)
		expect(p.fraction).toBe(0)
		expect(p.byTier[1].total).toBe(0)
		local full = Progress.dex({ "1:a:b:c", "2:a:b:c" }, 2, { "A", "B" })
		expect(full.percent).toBe("100%")
		expect(Progress.dex({}, 7, TIERS).byTier[1].total).toBeNil()
	end)
end)

describe("Progress v13 rank / dex rewards", function()
	it("describes the rank and the next one", function()
		local r = Progress.rank({
			rebirthTitle = "Goo Getter",
			nextRebirthTier = { rebirths = 3, title = "Slime Wrangler", text = "unlocks the OfflineCap upgrade" },
		})
		expect(r.title).toBe("Rank: Goo Getter")
		expect(r.next).toBe("Next: Slime Wrangler at 3 rebirths - unlocks the OfflineCap upgrade")
		expect(Progress.rank({ rebirthTitle = "Slime Deity" }).next).toBe("Top rank reached!")
		expect(Progress.rank({}).title).toBeNil()
	end)
	it("shows the next unclaimed dex reward and the bonus", function()
		local d = Progress.dexRewards({
			dexRewards = {
				{ count = 10, reward = 500, bonus = 0.02, claimed = true },
				{ count = 25, reward = 2500, bonus = 0.03, claimed = false },
			},
			dexBonus = 0.02,
		})
		expect(d.next).toBe("Next reward at 25: +$2.5K and +3% income")
		expect(d.bonus).toBe("SlimeDex bonus: +2% income")
		local all = Progress.dexRewards({ dexRewards = { { count = 10, reward = 1, bonus = 0.02, claimed = true } } })
		expect(all.next).toBe("All SlimeDex rewards collected!")
		expect(all.bonus).toBeNil()
		expect(Progress.dexRewards({}).next).toBeNil()
	end)
end)
