--!strict
-- The merge vat's rules (VatState, CONTRACT.md §21): filling it, the full and wrong-rarity refusals, taking
-- slimes out, brewing on the unix clock, locking while brewing, cancel, collect and pruning lost slimes.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Perks = require("../src/shared/Perks")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")
local Upgrades = require("../src/shared/Upgrades")
local VatState = require("../src/shared/VatState")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local slime = Fixtures.slime
local NOW = 1_800_000_000

local function plot(): PlayerData.Data
	return Fixtures.data({
		slime("a", 1),
		slime("b", 1),
		slime("c", 1),
		slime("d", 1),
		slime("r", 3),
		slime("egg", 1, { egg = true }),
	})
end

local function filled(): PlayerData.Data
	local data = plot()
	for _, id in { "a", "b", "c" } do
		assert(VatState.add(data, id))
	end
	return data
end

describe("VatState: filling", function()
	it("adds slimes in spot order and keeps them on their pads", function()
		local data = plot()
		expect(VatState.add(data, "b")).toBe(true)
		expect(VatState.add(data, "a")).toBe(true)
		expect(table.concat(VatState.ids(data), ",")).toBe("b,a")
		expect((PlayerData.findSlime(data, "b") :: any).pad).toBe(2)
		expect(VatState.tier(data)).toBe(1)
	end)

	it("refuses a fourth slime with 'The vat is full'", function()
		local data = filled()
		local ok, reason = VatState.add(data, "d")
		expect(ok).toBe(false)
		expect(reason).toBe("The vat is full")
		expect(#VatState.ids(data)).toBe(3)
	end)

	it("refuses another rarity, naming the one it takes", function()
		local data = plot()
		VatState.add(data, "a")
		local ok, reason = VatState.add(data, "r")
		expect(ok).toBe(false)
		expect(reason).toBe("The vat takes Common slimes")
	end)

	it("refuses eggs, repeats and slimes that aren't yours", function()
		local data = plot()
		VatState.add(data, "a")
		expect(select(2, VatState.add(data, "egg"))).toBe("Eggs can't go in the vat")
		expect(select(2, VatState.add(data, "a"))).toBe("Already in the vat")
		expect(select(2, VatState.add(data, "nobody"))).toBe("not your slime")
	end)

	it("takes a slime back out; an empty vat leaves no save field", function()
		local data = plot()
		VatState.add(data, "a")
		expect(VatState.remove(data, "a")).toBe(true)
		expect(#VatState.ids(data)).toBe(0)
		expect((data :: any).vat).toBe(nil)
		expect((PlayerData.findSlime(data, "a") :: any).pad).toBe(1)
	end)

	it("says what is missing before it can start", function()
		local data = plot()
		expect(VatState.missingText(data)).toBe("Add 3 slimes of one rarity")
		VatState.add(data, "a")
		VatState.add(data, "b")
		expect(VatState.missingText(data)).toBe("Add 1 more Common")
		expect(select(2, VatState.start(data, NOW))).toBe("Add 1 more Common")
	end)
end)

describe("VatState: brewing", function()
	it("brews for the rarity's time and is ready after it, offline included", function()
		local data = filled()
		expect(VatState.start(data, NOW)).toBe(true)
		local seconds = Config.MERGE_BREW_SECONDS[1]
		expect(VatState.endsAt(data)).toBe(NOW + seconds)
		expect(VatState.isReady(data, NOW + seconds - 1)).toBe(false)
		expect(VatState.timeLeft(data, NOW + 10)).toBe(seconds - 10)
		expect(VatState.isReady(data, NOW + seconds + 86400)).toBe(true)
	end)

	it("locks the inputs while brewing and refuses changes", function()
		local data = filled()
		expect(VatState.isLocked(data, "a")).toBe(false)
		VatState.start(data, NOW)
		expect(VatState.isLocked(data, "a")).toBe(true)
		expect(VatState.isLocked(data, "d")).toBe(false)
		expect(VatState.lockedSet(data).c).toBe(true)
		expect(select(2, VatState.remove(data, "a"))).toBe("Cancel the brew first")
		expect(select(2, VatState.add(data, "d"))).toBe("The vat is brewing")
	end)

	it("cancel keeps the slimes in the vat", function()
		local data = filled()
		VatState.start(data, NOW)
		expect(VatState.cancel(data)).toBe(true)
		expect(VatState.isBrewing(data)).toBe(false)
		expect(#VatState.ids(data)).toBe(3)
	end)

	it("collect waits for the timer, then merges onto the first input's pad and empties the vat", function()
		local data = filled()
		VatState.start(data, NOW)
		expect(select(2, VatState.collect(data, NOW + 1, Rng.new(7), "child"))).toBe("still brewing")
		local ok, child = VatState.collect(data, NOW + 3600, Rng.new(7), "child")
		expect(ok).toBe(true)
		expect((child :: any).tier >= 2).toBe(true)
		expect((child :: any).pad).toBe(1)
		expect(PlayerData.findSlime(data, "a")).toBe(nil)
		expect(PlayerData.findSlime(data, "b")).toBe(nil)
		expect(PlayerData.findSlime(data, "d") ~= nil).toBe(true)
		expect((data :: any).vat).toBe(nil)
	end)

	it("Quick Brew shortens brews, each level behind more rebirths", function()
		expect(VatState.brewSeconds(4, 1)).toBe(Config.MERGE_BREW_SECONDS[4])
		local data = filled()
		data.rebirths = 2
		data.cash = 10 ^ 9
		expect(Upgrades.buy(data, "QuickBrew")).toBe(true)
		expect(select(2, Upgrades.buy(data, "QuickBrew"))).toBe("locked: reach 4 rebirths")
		data.rebirths = 4
		expect(Upgrades.buy(data, "QuickBrew")).toBe(true)
		expect(Perks.brewFactor(data)).toBe(0.7)
		VatState.start(data, NOW, Perks.brewFactor(data))
		expect(VatState.endsAt(data)).toBe(NOW + math.floor(Config.MERGE_BREW_SECONDS[1] * 0.7 + 0.5))
	end)
end)

describe("VatState: lost slimes", function()
	it("a slime that leaves the plot while waiting leaves the vat", function()
		local data = filled()
		PlayerData.removeSlime(data, "b")
		expect(table.concat(VatState.ids(data), ",")).toBe("a,c")
	end)

	it("a brew that somehow loses an input stops instead of merging two", function()
		local data = filled()
		VatState.start(data, NOW)
		PlayerData.removeSlime(data, "b")
		expect(VatState.isBrewing(data)).toBe(false)
		expect(select(2, VatState.collect(data, NOW + 3600, Rng.new(1), "x"))).toBe("not brewing")
	end)

	it("sanitize keeps strings and a number end time, and drops junk", function()
		local clean = VatState.sanitize({ ids = { "a", 5, "b", "c", "d" }, endsAt = 12 }) :: VatState.Vat
		expect(table.concat(clean.ids, ",")).toBe("a,b,c")
		expect(clean.endsAt).toBe(12)
		expect(VatState.sanitize({ ids = {} })).toBe(nil)
		expect(VatState.sanitize("x")).toBe(nil)
	end)
end)
