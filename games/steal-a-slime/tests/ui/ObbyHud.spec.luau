--!strict
-- The Goo Gauntlet on screen (contract/obby.md): the HUD status slot (HudClusters.obby), the portal sign's two lines
-- and the run card (ui/ObbyHud).
local HudClusters = require("../../src/ui/HudClusters")
local Layout = require("../../src/ui/Layout")
local ObbyHud = require("../../src/ui/ObbyHud")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function view(extra: { [string]: any }?): any
	local v: { [string]: any } = { bonus = 0.5, sections = { "Jelly Steps" }, rotatesAt = 1600 }
	for k, x in extra or {} do
		v[k] = x
	end
	return v
end

describe("Goo Gauntlet HUD slot", function()
	it("shows x1.5 with the time left while boosted, and nothing otherwise", function()
		local slot = HudClusters.obby(view({ endsAt = 1300 }), 1000) :: HudClusters.Slot
		expect(slot.id).toBe("Obby")
		expect(slot.icon).toBe("Boost_Obby")
		expect(slot.text).toBe("5:00")
		local tip = HudClusters.tooltip(slot)
		expect(tip.title).toBe("Goo Gauntlet")
		expect(string.find(tip.body, "income for clearing the sky obby", 1, true) ~= nil).toBe(true)
		expect(HudClusters.obby(view(), 1000)).toBeNil()
		expect(HudClusters.obby(view({ endsAt = 1000 }), 1000)).toBeNil()
		expect(HudClusters.obby(nil, 1000)).toBeNil()
	end)

	it("sits after the Boss Champion slot and before the code boost", function()
		expect(table.find(HudClusters.STATUS_IDS, "Obby")).toBe(table.find(HudClusters.STATUS_IDS, "Mvp") :: number + 1)
		expect(table.concat(Layout.STATUS_SLOTS, ",")).toBe(table.concat(HudClusters.STATUS_IDS, ","))
		local slots = HudClusters.status({
			modifierEnabled = false,
			friendsEnabled = false,
			obby = view({ endsAt = 1300 }),
			codes = { boostMult = 2, boostEndsAt = 1300 },
		}, 1000, 9)
		expect(slots[1].id).toBe("Obby")
		expect(slots[2].id).toBe("Boost")
	end)
end)

describe("Goo Gauntlet portal sign", function()
	it("says what this player gets: ready, boosted, or cooling down", function()
		expect(ObbyHud.statusText(view(), 1000)).toBe("Step in: x1.5 income!")
		expect(ObbyHud.statusText(view({ endsAt = 1192, readyAt = 1492 }), 1000)).toBe("x1.5 income · 3:12 left")
		expect(ObbyHud.statusText(view({ readyAt = 1100 }), 1000)).toBe("Boost ready in 1:40")
		expect(ObbyHud.statusText(nil, 1000)).toBe("Step in to start!")
	end)

	it("counts down to the next course", function()
		expect(ObbyHud.courseText(view(), 1235)).toBe("New course in 6:05")
	end)
end)

describe("Goo Gauntlet run card", function()
	it("shows the checkpoint and the run clock only while running", function()
		expect(ObbyHud.runText(view(), 1000)).toBeNil()
		local title, clock = ObbyHud.runText(view({ run = { reached = 0, of = 5, startedAt = 990 } }), 1000)
		expect(title).toBe("GOO GAUNTLET")
		expect(clock).toBe("0:10.0")
		title, clock = ObbyHud.runText(view({ run = { reached = 2, of = 5, startedAt = 900 } }), 1003.5)
		expect(title).toBe("CHECKPOINT 2/5")
		expect(clock).toBe("1:43.5")
	end)
end)
