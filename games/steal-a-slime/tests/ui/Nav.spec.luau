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
	end)
	it("is exactly Rebirth, Goals, SlimeDex, Codes (Plot, Merge, Shop and Top have no button)", function()
		local keys = {}
		for _, entry in Nav.ENTRIES do
			table.insert(keys, entry.key)
		end
		expect(table.concat(keys, ",")).toBe("Rebirth,Goals,Dex,Codes")
	end)
	it("shows the Dex entry as SlimeDex (internal key stays Dex)", function()
		local labels = {}
		for _, entry in Nav.ENTRIES do
			labels[entry.key] = entry.label
		end
		expect(labels.Dex).toBe("SlimeDex")
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
	it("flags rebirth and dex % (no Plot / Merge / Shop badges: those buttons are gone)", function()
		local badges = Nav.badges({
			cash = 600,
			slimes = { view("a", 1, 7), view("b", 2), view("c", 2) },
			shop = {
				LockUpgrade = { price = 500, level = 0, maxLevel = 5 },
				SpeedCoil = { price = 1500, owned = false },
			},
			canRebirth = true,
			dex = { found = 2, total = 50 },
		})
		expect(badges.Plot).toBeNil()
		expect(badges.Merge).toBeNil()
		expect(badges.Shop).toBeNil()
		expect(badges.Rebirth).toBe("!")
		expect(badges.Dex).toBe("4%")
	end)
	it("stays quiet when there is nothing to do", function()
		local badges = Nav.badges({
			cash = 10,
			slimes = { view("a", 1) },
			shop = { LockUpgrade = { price = nil, level = 5, maxLevel = 5 }, SpeedCoil = { price = 1500 } },
			canRebirth = false,
			dex = { found = 0, total = 0 },
		})
		expect(next(badges)).toBeNil()
		expect(next(Nav.badges(nil))).toBeNil()
	end)
end)
