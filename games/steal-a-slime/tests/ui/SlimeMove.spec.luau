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
		expect(SlimeMove.hintText("keyboard")).toBe("Click a pad or press E to place · Q to cancel")
		expect(SlimeMove.hintText("touch")).toBe("Tap a pad to place it there")
		expect(SlimeMove.hintText("gamepad")).toBe("X: place on the lit pad · B: cancel")
	end)
end)
