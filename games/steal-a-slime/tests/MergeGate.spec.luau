--!strict
-- The merge rank gate (MergeGate, contract/merge-vat.md §21.9): which rarities each rank may merge, the vat's Start
-- refusal, the jump cap, the world tag lines and the rank reward text.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local MergeGate = require("../src/shared/MergeGate")
local MergeRecipes = require("../src/shared/MergeRecipes")
local Perks = require("../src/shared/Perks")
local Rng = require("../src/shared/Rng")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")
local TripleMerge = require("../src/shared/TripleMerge")
local VatState = require("../src/shared/VatState")
local VatView = require("../src/server/VatView")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local NOW = 1_800_000_000
local EPIC_AT = MergeGate.rebirthsFor(4) :: number

local function vat(tier: number, rebirths: number, count: number?): any
	local slimes = {}
	for i = 1, 4 do
		table.insert(slimes, Fixtures.slime(`s{i}`, tier))
	end
	local data = Fixtures.data(slimes)
	data.rebirths = rebirths
	for i = 1, count or 3 do
		assert(VatState.add(data, `s{i}`))
	end
	return data
end

local function three(tier: number): { any }
	return { Fixtures.slime("a", tier), Fixtures.slime("b", tier), Fixtures.slime("c", tier) }
end

describe("MergeGate ranks", function()
	it(
		"opens Common at 0, Uncommon at 1, Rare at 3, Epic at 5, Legendary at 8, Mythic at 12 and Secret never",
		function()
			local cases = {
				{ 0, 1 },
				{ 1, 2 },
				{ 2, 2 },
				{ 3, 3 },
				{ 4, 3 },
				{ 5, 4 },
				{ 7, 4 },
				{ 8, 5 },
				{ 11, 5 },
				{ 12, 6 },
				{ Config.MAX_REBIRTHS, 6 },
			}
			for _, case in cases do
				expect(MergeGate.topTier(case[1])).toBe(case[2])
			end
			expect(MergeGate.rebirthsFor(1)).toBe(0)
			expect(MergeGate.rebirthsFor(2)).toBe(1)
			expect(MergeGate.rebirthsFor(3)).toBe(3)
			expect(MergeGate.rebirthsFor(4)).toBe(5)
			expect(MergeGate.rebirthsFor(5)).toBe(8)
			expect(MergeGate.rebirthsFor(6)).toBe(12)
			expect(MergeGate.rebirthsFor(7)).toBe(nil)
			expect(MergeGate.allows(4, 4)).toBe(false)
			expect(MergeGate.allows(4, 5)).toBe(true)
			expect(MergeGate.allows(7, Config.MAX_REBIRTHS)).toBe(false)
		end
	)

	it("writes the lock, opens and cap texts", function()
		expect(MergeGate.lockText(4)).toBe("Rebirth 5 to unlock")
		expect(MergeGate.lockText(7)).toBe("Locked")
		expect(MergeGate.opensText(4)).toBe("Epic merges open at Rebirth 5")
		expect(MergeGate.capText(1)).toBe("Up to Uncommon")
		expect(MergeGate.capText(Config.MAX_REBIRTHS)).toBe("Up to Mythic")
	end)

	it("never asks a rebirth for a hybrid the player can't brew yet", function()
		for level, list in Config.REBIRTH_SLIMES do
			for _, id in list do
				local entry = SlimeRoster.get(id)
				if entry and entry.kind == "hybrid" then
					local inputs = (MergeRecipes.recipeFor(id) :: any).inputs
					local inputTier = (SlimeRoster.get(inputs[1]) :: any).tier
					expect(MergeGate.allows(inputTier, level - 1)).toBe(true)
				end
			end
		end
	end)
end)

describe("VatState with the rank gate", function()
	it("loads a locked rarity but refuses Start with the rebirth it needs", function()
		local data = vat(4, EPIC_AT - 1)
		expect(#VatState.ids(data)).toBe(3)
		expect(VatState.gateText(data)).toBe(`Rebirth {EPIC_AT} to unlock`)
		local ok, reason = VatState.start(data, NOW)
		expect(ok).toBe(false)
		expect(reason).toBe(`Rebirth {EPIC_AT} to unlock`)
		expect(VatState.isBrewing(data)).toBe(false)
	end)

	it("starts once the rank opens the rarity", function()
		local data = vat(4, EPIC_AT)
		expect(VatState.gateText(data)).toBe(nil)
		expect(VatState.start(data, NOW)).toBe(true)
	end)

	it("a brew already running still collects", function()
		local data = vat(4, EPIC_AT)
		assert(VatState.start(data, NOW))
		data.rebirths = 0
		local ok = VatState.collect(data, NOW + Config.MERGE_BREW_SECONDS[4], Rng.new(1), "child")
		expect(ok).toBe(true)
	end)
end)

describe("TripleMerge jump with the rank gate", function()
	it("never jumps past the rank's top result", function()
		-- Rare merges are open but Epic ones are not, so a Rare load may not jump to Legendary
		local rareAt = MergeGate.rebirthsFor(3) :: number
		local ctx = { unlocked = MergeRecipes.everySpecies, rebirths = rareAt }
		local rng = Rng.new(7)
		for i = 1, 200 do
			expect(TripleMerge.merge(three(3), rng, `r{i}`, ctx).tier).toBe(4)
		end
		expect(TripleMerge.odds(3, rareAt).jumpTier).toBe(nil)
		expect(TripleMerge.odds(3, EPIC_AT).jumpTier).toBe(5)
		expect(TripleMerge.odds(2, rareAt).jumpTier).toBe(4)
		expect(TripleMerge.odds(2, MergeGate.rebirthsFor(2) :: number).jumpTier).toBe(nil)
	end)

	it("keeps the draw order: an open rank gives the same child as no gate", function()
		local open = { unlocked = MergeRecipes.everySpecies, rebirths = 50 }
		local none = { unlocked = MergeRecipes.everySpecies }
		for seed = 1, 20 do
			local a = TripleMerge.merge(three(2), Rng.new(seed), "x", open)
			local b = TripleMerge.merge(three(2), Rng.new(seed), "x", none)
			expect(a.tier).toBe(b.tier)
			expect(a.species).toBe(b.species)
			expect(a.pattern).toBe(b.pattern)
		end
	end)

	it("reads the rank from the save", function()
		local data = Fixtures.data({})
		data.rebirths = 6
		expect(TripleMerge.ctxFor(data).rebirths).toBe(6)
	end)
end)

describe("VatView with the rank gate", function()
	it("shows the owner's cap under the pill while not brewing", function()
		local empty = Fixtures.data({})
		empty.rebirths = 1
		expect((VatView.capLine(empty) :: any).text).toBe("Up to Uncommon")
		local data = vat(2, 1)
		expect((VatView.capLine(data) :: any).text).toBe("Up to Uncommon")
		assert(VatState.start(data, NOW))
		expect(VatView.capLine(data)).toBe(nil)
	end)

	it("turns a locked load's pill and line Warn", function()
		local data = vat(4, EPIC_AT - 1)
		expect(VatView.tagLine(data, NOW).color).toBe("Warn")
		local line = VatView.capLine(data) :: any
		expect(line.text).toBe(`Rebirth {EPIC_AT} to merge`)
		expect(line.color).toBe("Warn")
	end)
end)

describe("Rank reward text", function()
	it("names the rarities a rank opens", function()
		local function rank(rebirths: number): any
			for _, r in Config.REBIRTH_TIERS do
				if r.rebirths == rebirths then
					return r
				end
			end
			return nil
		end
		expect(string.find(Perks.tierText(rank(3)), "opens Rare merges", 1, true) ~= nil).toBe(true)
		expect(string.find(Perks.tierText(rank(12)), "opens Mythic merges", 1, true) ~= nil).toBe(true)
		expect(string.find(Perks.tierText(rank(6)), "merges", 1, true)).toBe(nil)
		expect(Perks.tierText(rank(0))).toBe("")
	end)
end)
