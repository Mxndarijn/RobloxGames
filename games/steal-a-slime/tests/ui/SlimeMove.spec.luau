--!strict
-- Move mode rules (src/ui/SlimeMove.luau, FEATURES.MoveSlime): what a place on a pad would do, the nearest
-- unlocked pad, and the bar's texts. The live mode (ghost, tint, input) is checked in a Studio playtest.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Vector3 = roblox.Vector3
local SlimeMove = UiHarness.ui("SlimeMove")

describe("SlimeMove.classify", function()
	local occupied = { [1] = true, [2] = true }
	it("an empty unlocked pad is a move, a taken one a swap", function()
		expect(SlimeMove.classify(3, 1, 4, occupied)).toBe("empty")
		expect(SlimeMove.classify(2, 1, 4, occupied)).toBe("swap")
	end)
	it("the slime's own pad is 'same', pads past padsUnlocked are locked", function()
		expect(SlimeMove.classify(1, 1, 4, occupied)).toBe("same")
		expect(SlimeMove.classify(5, 1, 4, occupied)).toBe("locked")
		expect(SlimeMove.classify(0, 1, 4, occupied)).toBe("locked")
	end)
end)

describe("SlimeMove.withinZone", function()
	local half = Vector3.new(30, 7, 30)
	it("keeps move mode on up the tower's upper jars when the zone reaches up", function()
		local upperJar = Vector3.new(5, 40, 5) -- well above the ground zone's 7 + 8 studs
		expect(SlimeMove.withinZone(upperJar, half, nil)).toBe(false)
		expect(SlimeMove.withinZone(upperJar, half, 48)).toBe(true)
	end)
	it("still ends move mode beside or above the plot", function()
		expect(SlimeMove.withinZone(Vector3.new(31, 0, 0), half, 48)).toBe(false)
		expect(SlimeMove.withinZone(Vector3.new(0, 7 + 8 + 48 + 1, 0), half, 48)).toBe(false)
		expect(SlimeMove.withinZone(Vector3.new(0, -12, 0), half, 48)).toBe(false)
	end)
end)

describe("SlimeMove.nearest", function()
	local pads = {
		{ index = 1, position = Vector3.new(0, 0, 0) },
		{ index = 2, position = Vector3.new(10, 0, 0) },
		{ index = 5, position = Vector3.new(20, 0, 0) },
	}
	it("picks the closest unlocked pad", function()
		expect(SlimeMove.nearest(pads, Vector3.new(9, 3, 1), 4)).toBe(2)
		expect(SlimeMove.nearest(pads, Vector3.new(-5, 0, 0), 4)).toBe(1)
	end)
	it("skips locked pads, even the closest one", function()
		expect(SlimeMove.nearest(pads, Vector3.new(21, 0, 0), 4)).toBe(2)
		expect(SlimeMove.nearest(pads, Vector3.new(21, 0, 0), 0)).toBeNil()
	end)
end)

describe("SlimeMove texts", function()
	it("names what a place would do", function()
		expect(SlimeMove.statusText("empty", 3)).toBe("Pad 3: empty")
		expect(SlimeMove.statusText("swap", 2, "Blorp")).toBe("Pad 2: swaps with Blorp")
		expect(SlimeMove.statusText("locked", 7)).toBe("Pad 7 is locked: buy it first")
		expect(SlimeMove.statusText("same", 1)).toBe("Pad 1: this slime's own pad")
		expect(SlimeMove.statusText(nil, nil)).toBe("Point at one of your pads")
	end)
	it("tells each input how to place and cancel", function()
		expect(SlimeMove.hintText("keyboard")).toBe("Click a pad or the vat, or press E to place · Q to cancel")
		expect(SlimeMove.hintText("touch")).toBe("Tap a pad or the vat to place it there")
		expect(SlimeMove.hintText("gamepad")).toBe("X: place on the lit pad or vat · B: cancel")
	end)
end)

describe("SlimeMove into the merge vat", function()
	local function slime(id: string, tier: number, extra: { [string]: any }?): any
		local s = { id = id, tier = tier, name = "Blorp" }
		for k, v in extra or {} do
			s[k] = v
		end
		return s
	end
	it("an empty vat or one of the same rarity with room takes the slime", function()
		expect(SlimeMove.vatClass({ ids = {} }, slime("a", 1))).toBe("vat")
		expect(SlimeMove.vatClass({ ids = { "x" }, tier = 1 }, slime("a", 1))).toBe("vat")
		expect(SlimeMove.vatStatus("vat", "Gummy", 1)).toBe("Merge vat: adds Gummy (2/3)")
	end)
	it("a full vat, another rarity, a brew or an egg say why", function()
		local function reason(vat: any, s: any): string?
			local class, why = SlimeMove.vatClass(vat, s)
			expect(class).toBe("vatRefused")
			return why
		end
		expect(reason({ ids = { "x", "y", "z" }, tier = 1 }, slime("a", 1))).toBe("The vat is full")
		expect(reason({ ids = { "x" }, tier = 1 }, slime("a", 3))).toBe("The vat takes Common slimes")
		expect(reason({ ids = { "x", "y", "z" }, tier = 1, endsAt = 5 }, slime("a", 1))).toBe("The vat is brewing")
		expect(reason({ ids = {} }, slime("a", 1, { egg = { kind = "shiny" } }))).toBe("Eggs can't go in the vat")
		expect(reason({ ids = { "a" }, tier = 1 }, slime("a", 1))).toBe("Already in the vat")
	end)
	it("the vat counts as a target for the nearest pick", function()
		local spots = {
			{ index = 1, position = Vector3.new(10, 0, 0) },
			{ index = SlimeMove.VAT, position = Vector3.new(1, 0, 0) },
		}
		expect(SlimeMove.nearest(spots, Vector3.new(0, 0, 0), 4)).toBe(SlimeMove.VAT)
	end)
end)
