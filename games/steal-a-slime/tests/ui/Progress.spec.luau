--!strict
-- Rebirth ladder and SlimeDex completion (src/ui/Progress.luau).
local Config = require("../../src/shared/Config")
local Economy = require("../../src/shared/Economy")
local Fixtures = require("../Fixtures")
local Format = require("../../src/ui/Format")
local Progress = require("../../src/ui/Progress")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local function state(rebirths: number, cash: number): any
	return {
		rebirths = rebirths,
		rebirthMultiplier = Economy.rebirthMultiplier(rebirths),
		nextRebirthMultiplier = Economy.rebirthMultiplier(math.min(rebirths + 1, Config.MAX_REBIRTHS)),
		rebirthCost = Economy.rebirthCost(rebirths),
		canRebirth = cash >= Economy.rebirthCost(rebirths),
		lockDuration = 75,
		cash = cash,
	}
end

describe("Progress.rebirthTiers", function()
	it("lists the current tier and the next ones with server costs", function()
		local tiers = Progress.rebirthTiers(state(1, 0), Config, Economy.rebirthCost, Economy.rebirthMultiplier, 3)
		expect(#tiers).toBe(4)
		expect(tiers[1].current).toBe(true)
		expect(tiers[1].cost).toBeNil()
		expect(tiers[2].rebirth).toBe(2)
		expect(tiers[2].multiplier).toBeCloseTo(Economy.rebirthMultiplier(2))
		expect(tiers[2].cost).toBe(Economy.rebirthCost(1))
		expect(tiers[4].cost).toBe(Economy.rebirthCost(3))
		expect(tiers[3].lockSeconds).toBe(75 + 2 * Config.LOCK_SECONDS_PER_REBIRTH)
	end)
	it("never shows a lock longer than LOCK_MAX_SECONDS", function()
		local s = state(1, 0)
		s.lockDuration = Config.LOCK_MAX_SECONDS - 5
		local tiers = Progress.rebirthTiers(s, Config, Economy.rebirthCost, Economy.rebirthMultiplier, 3)
		expect(tiers[2].lockSeconds).toBe(Config.LOCK_MAX_SECONDS)
		expect(tiers[4].lockSeconds).toBe(Config.LOCK_MAX_SECONDS)
	end)
	it("gives each future tier the stepped multiplier, across a band edge", function()
		local edge = Config.REBIRTH_MULTIPLIER_STEPS[2].from
		local tiers =
			Progress.rebirthTiers(state(edge - 2, 0), Config, Economy.rebirthCost, Economy.rebirthMultiplier, 2)
		expect(tiers[2].multiplier).toBe(Economy.rebirthMultiplier(edge - 1))
		expect(tiers[3].multiplier).toBe(Economy.rebirthMultiplier(edge))
		expect(tiers[3].multiplier - tiers[2].multiplier).toBe(Config.REBIRTH_MULTIPLIER_STEPS[2].step)
	end)
	it("nextRebirth shows the server's nextRebirthMultiplier", function()
		local edge = Config.REBIRTH_MULTIPLIER_STEPS[2].from
		local n = Progress.nextRebirth(state(edge - 1, 0), Config)
		expect(n.multiplier).toBe(Economy.rebirthMultiplier(edge))
	end)
	it("stops at MAX_REBIRTHS", function()
		local tiers = Progress.rebirthTiers(
			state(Config.MAX_REBIRTHS - 1, 0),
			Config,
			Economy.rebirthCost,
			Economy.rebirthMultiplier,
			3
		)
		expect(#tiers).toBe(2)
	end)
	it("formats a tier line", function()
		local tiers = Progress.rebirthTiers(state(0, 0), Config, Economy.rebirthCost, Economy.rebirthMultiplier, 1)
		expect(Progress.tierText(tiers[1])).toBe("Now · rebirth 0: x1 income · 75s lock")
		expect(Progress.tierText(tiers[2])).toBe(
			`Rebirth 1: x1.5 income · {75 + Config.LOCK_SECONDS_PER_REBIRTH}s lock · {Format.formatCash(
				Economy.rebirthCost(0)
			)}`
		)
	end)
end)

describe("Progress.rebirthStatus", function()
	it("shows what's missing, READY, or maxed", function()
		local cost = Economy.rebirthCost(0)
		local s = Progress.rebirthStatus(state(0, cost / 4), Config.MAX_REBIRTHS)
		expect(s.ready).toBe(false)
		expect(s.fraction).toBeCloseTo(0.25)
		expect(s.text).toBe(`{Format.formatCash(cost * 3 / 4)} more needed (25%)`)
		expect(Progress.rebirthStatus(state(0, cost + 1), Config.MAX_REBIRTHS).text).toBe("READY! Rebirth now")
		local maxed = Progress.rebirthStatus(state(Config.MAX_REBIRTHS, 0), Config.MAX_REBIRTHS)
		expect(maxed.maxed).toBe(true)
	end)
end)

describe("Progress.dex", function()
	it("gives percent, fraction and per-rarity counts of the species Dex (event Secrets count nowhere)", function()
		local p = Progress.dex(Fixtures.dex({ "gummy", "mochi", "whiskers", "glitch" }), TIERS)
		expect(p.count).toBe(3)
		expect(p.total).toBe(SpeciesDex.TOTAL)
		expect(p.percent).toBe(`{math.floor(3 / SpeciesDex.TOTAL * 100)}%`)
		expect(p.fraction).toBeCloseTo(3 / SpeciesDex.TOTAL)
		expect(p.byTier[1].count).toBe(2)
		expect(p.byTier[1].total).toBe(SpeciesDex.tierSize(1))
		expect(p.byTier[3].count).toBe(1)
		expect(p.byTier[6].count).toBe(0)
	end)
	it("handles empty / missing data", function()
		local p = Progress.dex(nil, TIERS)
		expect(p.count).toBe(0)
		expect(p.fraction).toBe(0)
		expect(p.byTier[1].total).toBeNil()
		expect(Progress.dex({ found = 50, total = 50 }, TIERS).percent).toBe("100%")
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
				{ ladder = "species", count = 8, reward = 500, bonus = 0.02, claimed = true },
				{ ladder = "species", count = 15, reward = 2500, bonus = 0.03, claimed = false },
				{ ladder = "species", count = 20, reward = 9000, bonus = 0.05, claimed = false },
			},
			dexBonus = 0.02,
		})
		expect(d.next).toBe("Next: 15 species +$2.5K, +3% income")
		expect(d.bonus).toBe("SlimeDex bonus: +2% income")
		local all = Progress.dexRewards({ dexRewards = { { count = 10, reward = 1, bonus = 0.02, claimed = true } } })
		expect(all.next).toBe("All SlimeDex rewards collected!")
		expect(all.bonus).toBeNil()
		expect(Progress.dexRewards({}).next).toBeNil()
	end)

	it("builds the bar to the next unclaimed dex milestone with ticks", function()
		local m = Progress.dexMilestones({
			dex = { found = 3, total = 50 },
			dexRewards = {
				{ ladder = "species", count = 10, reward = 1, bonus = 0.02, claimed = true },
				{ ladder = "species", count = 25, reward = 1, bonus = 0.03, claimed = false },
			},
		})
		expect(m.icon).toBe("Dex_25")
		expect(m.label).toBe("3 / 25")
		expect(m.fraction).toBe(3 / 25)
		expect(m.ticks[1].claimed).toBe(true)
		expect(m.ticks[2].claimed).toBe(false)
		expect(m.ticksText).toBe("✅10  25")
	end)
	it("fills the milestone bar once everything is claimed and is nil without rewards", function()
		local m = Progress.dexMilestones({
			dex = { found = 0, total = 50 },
			dexRewards = { { ladder = "species", count = 10, reward = 1, bonus = 0.02, claimed = true } },
		})
		expect(m.fraction).toBe(1)
		expect(m.next).toBeNil()
		expect(m.icon).toBe("Dex_10")
		expect(Progress.dexMilestones({})).toBeNil()
	end)
end)

describe("Progress.rebirthReason", function()
	local function nextUp(cost: number, have: number, missing: { string }): any
		local needs = {}
		for _, name in missing do
			table.insert(needs, { id = name, name = name, tier = 1, color = { 0, 0, 0 }, owned = false })
		end
		return {
			maxed = false,
			ready = false,
			cost = cost,
			have = have,
			missing = needs,
		}
	end
	it("says what is missing: cash, slimes, or both", function()
		expect(Progress.rebirthReason(nextUp(180000, 1240, {}))).toBe(`Need {Format.formatCash(178760)} more`)
		expect(Progress.rebirthReason(nextUp(100, 500, { "Flan" }))).toBe("Need a Flan")
		expect(Progress.rebirthReason(nextUp(36.9e6, 21.4e6, { "Flan" }))).toBe(
			`Need {Format.formatCash(15.5e6)} and a Flan`
		)
		expect(Progress.rebirthReason(nextUp(0, 0, { "Zap", "Imp", "Octo" }))).toBe("Need a Zap, an Imp and an Octo")
		expect(Progress.rebirthReason(nextUp(36.9e6, 21.4e6, { "Flan", "Imp" }))).toBe(
			`Need {Format.formatCash(15.5e6)}, a Flan and an Imp`
		)
	end)
	it("is empty when ready and says done at the top", function()
		local ready = nextUp(1, 1, {})
		ready.ready = true
		expect(Progress.rebirthReason(ready)).toBe("")
		local maxed = nextUp(0, 0, {})
		maxed.maxed = true
		expect(Progress.rebirthReason(maxed)).toBe("All rebirths done")
	end)
end)
