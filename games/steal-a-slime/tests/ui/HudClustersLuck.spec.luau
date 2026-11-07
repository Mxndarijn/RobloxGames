--!strict
-- The server Luck Potion's bottom-right status slot: its time left while State.consumables.luckUntil is ahead,
-- nothing once it runs out.
local HudClusters = require("../../src/ui/HudClusters")
local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function ids(input: any): string
	local out = {}
	for _, s in HudClusters.status(input, 1000, Layout.STATUS.count) do
		table.insert(out, s.id)
	end
	return table.concat(out, ",")
end

describe("HudClusters luck potion slot", function()
	it("shows the potion's time left with its icon and multiplier", function()
		local slot = HudClusters.luck({ luckUntil = 1000 + 4 * 60 + 5, luckMult = 2.5 }, 1000)
		expect(slot).toBeTruthy()
		local s = slot :: HudClusters.Slot
		expect(s.id).toBe("Luck")
		expect(s.icon).toBe("Consumable_LuckPotion")
		expect(s.kind).toBe("active")
		expect(s.text).toBe("4:05")
		expect(string.find(s.effect, "x2.5", 1, true) ~= nil).toBe(true)
		expect(HudClusters.tooltip(s).title).toBe("Luck Potion")
	end)
	it("is gone with no potion, an ended one or a malformed view", function()
		expect(HudClusters.luck(nil, 1000)).toBe(nil)
		expect(HudClusters.luck({ luckUntil = 0, luckMult = 2.5 }, 1000)).toBe(nil)
		expect(HudClusters.luck({ luckUntil = 999, luckMult = 2.5 }, 1000)).toBe(nil)
		expect(HudClusters.luck({ luckUntil = 0 / 0 } :: any, 1000)).toBe(nil)
		expect(HudClusters.luck({ slot = 1 } :: any, 1000)).toBe(nil)
	end)
	it("sits right after the server modifier in the row", function()
		expect(ids({
			modifier = { label = "Dawn", luck = 2, endsAt = 1100 },
			modifierEnabled = true,
			luckPotion = { luckUntil = 1200, luckMult = 2.5 },
			friends = { count = 1, bonus = 0.1 },
			friendsEnabled = true,
		})).toBe("Event,Luck,Friend")
		expect(table.find(HudClusters.STATUS_IDS, "Luck")).toBe(
			table.find(HudClusters.STATUS_IDS, "Event") :: number + 1
		)
	end)
end)
