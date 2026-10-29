--!strict
-- PvpEffectsLogic.shows: with "Other players' effects" off, a client draws only the PvP effects it fired, was hit
-- by or owns, and every trap marker.
local Logic = require("../../src/ui/PvpEffectsLogic")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ME, OTHER, THIRD = 1, 2, 3

describe("PvpEffectsLogic.shows", function()
	it("draws everything with other players' effects on", function()
		expect(Logic.shows({ kind = "Effect", effect = "Knockback", attacker = OTHER, target = THIRD }, ME, true)).toBe(
			true
		)
	end)
	it("hides an effect between two other players when off", function()
		expect(Logic.shows({ kind = "Effect", effect = "Knockback", attacker = OTHER, target = THIRD }, ME, false)).toBe(
			false
		)
		expect(Logic.shows({ effect = "Freeze", attacker = OTHER }, ME, false)).toBe(false)
	end)
	it("keeps effects I fired, was hit by or own", function()
		expect(Logic.shows({ kind = "Effect", attacker = ME, target = OTHER }, ME, false)).toBe(true)
		expect(Logic.shows({ kind = "Effect", attacker = OTHER, target = ME }, ME, false)).toBe(true)
		expect(Logic.shows({ kind = "Effect", attacker = OTHER, owner = ME }, ME, false)).toBe(true)
		expect(Logic.shows({ kind = "Effect", attacker = OTHER, targets = { THIRD, ME } }, ME, false)).toBe(true)
		expect(Logic.shows({ kind = "Effect", attacker = OTHER, targets = { THIRD } }, ME, false)).toBe(false)
	end)
	it("always draws trap markers", function()
		expect(Logic.shows({ kind = "TrapPlaced", owner = OTHER, trapId = "t1" }, ME, false)).toBe(true)
		expect(Logic.shows({ kind = "TrapCleared", trapId = "t1" }, ME, false)).toBe(true)
	end)
end)
