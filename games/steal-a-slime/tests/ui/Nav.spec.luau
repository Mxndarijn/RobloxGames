--!strict
-- Left-bar entries and badges (src/ui/Nav.luau).
local Nav = require("../../src/ui/Nav")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function view(id: string, tier: number, stolenBy: number?): any
	return { slime = { id = id, tier = tier }, income = 1, sellPrice = 1, stolenBy = stolenBy }
end

describe("Nav.ENTRIES", function()
	it("has unique keys, an icon and a readable label each", function()
		local seen = {}
		for _, entry in Nav.ENTRIES do
			expect(seen[entry.key]).toBeNil()
			seen[entry.key] = true
			expect(#entry.icon > 0).toBe(true)
			expect(#entry.label > 0 and #entry.label <= 8).toBe(true)
		end
		expect(seen.Plot and seen.Shop and seen.Rebirth and seen.Dex).toBe(true)
	end)
end)

describe("Nav.canMerge", function()
	it("needs two slimes of one tier that aren't being stolen", function()
		expect(Nav.canMerge({ view("a", 1), view("b", 1) })).toBe(true)
		expect(Nav.canMerge({ view("a", 1), view("b", 2) })).toBe(false)
		expect(Nav.canMerge({ view("a", 1), view("b", 1, 42) })).toBe(false)
		expect(Nav.canMerge(nil)).toBe(false)
	end)
end)

describe("Nav.shopAffordable", function()
	it("also counts unlocked v13 upgrades", function()
		local upgrades =
			{ { id = "Income", price = 100, unlocked = true }, { id = "Luck", price = 5, unlocked = false } }
		expect(Nav.shopAffordable({ cash = 150, upgrades = upgrades })).toBe(true)
		expect(Nav.shopAffordable({ cash = 50, upgrades = upgrades })).toBe(false)
	end)
end)

describe("Nav.badges", function()
	it("flags stolen slimes, merges, affordable upgrades, rebirth and dex %", function()
		local badges = Nav.badges({
			cash = 600,
			slimes = { view("a", 1, 7), view("b", 2), view("c", 2) },
			shop = {
				LockUpgrade = { price = 500, level = 0, maxLevel = 5 },
				SpeedCoil = { price = 1500, owned = false },
			},
			canRebirth = true,
			dex = { "1:None:Plain:Round", "1:None:Plain:Wide" },
			dexTotal = 720,
		})
		expect(badges.Plot).toBe("!")
		expect(badges.Merge).toBe("!")
		expect(badges.Shop).toBe("$")
		expect(badges.Rebirth).toBe("!")
		expect(badges.Dex).toBe("0%")
	end)
	it("stays quiet when there is nothing to do", function()
		local badges = Nav.badges({
			cash = 10,
			slimes = { view("a", 1) },
			shop = { LockUpgrade = { price = nil, level = 5, maxLevel = 5 }, SpeedCoil = { price = 1500 } },
			canRebirth = false,
			dex = {},
			dexTotal = 0,
		})
		expect(next(badges)).toBeNil()
		expect(next(Nav.badges(nil))).toBeNil()
	end)
end)
