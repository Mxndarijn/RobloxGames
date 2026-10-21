--!strict
-- Carry fade rule (src/ui/CarryFade.luau): only the slime you are stealing turns see-through for you. The live fade
-- (LocalTransparencyModifier) is checked in a Studio playtest.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local CarryFade = UiHarness.ui("CarryFade")
local SlimeMove = UiHarness.ui("SlimeMove")

local ME, VICTIM = 10, 20

describe("CarryFade.wants", function()
	it("fades the slime you carry when it belongs to someone else", function()
		expect(CarryFade.wants("gem", "gem", VICTIM, ME)).toBe(true)
	end)
	it("leaves a carried wild slime solid", function()
		expect(CarryFade.wants("gem", "gem", nil, ME)).toBe(false)
		expect(CarryFade.wants("gem", "gem", 0, ME)).toBe(false)
	end)
	it("leaves your own slimes and slimes you don't carry alone", function()
		expect(CarryFade.wants("gem", "gem", ME, ME)).toBe(false)
		expect(CarryFade.wants("gem", "other", VICTIM, ME)).toBe(false)
		expect(CarryFade.wants(nil, "gem", VICTIM, ME)).toBe(false)
	end)
	it("uses the same fade as moving your own slime", function()
		expect(CarryFade.FADE).toBe(SlimeMove.FADE)
	end)
end)
