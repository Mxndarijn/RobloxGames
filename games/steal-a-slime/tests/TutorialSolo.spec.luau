--!strict
-- Solo tutorial: the Steal step skips itself when no other player has a slime on a pad.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local GameLoop = require("../src/server/GameLoop")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local TutorialProgress = require("../src/shared/TutorialProgress")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function run(world: World.World, from: number, seconds: number): number
	local t = from
	for _ = 1, seconds do
		t += 1
		GameLoop.step(world, t)
	end
	return t
end

describe("solo tutorial Steal step", function()
	it("completes all 7 steps without anyone to steal from", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.tutorialStep = 1
		for _, name in { "Grab", "Deposit", "Lock", "BuyPad", "Merge" } do
			World.tutorial(world, s, name)
		end
		expect(TutorialProgress.currentId(s.data)).toBe("Steal")
		local t = run(world, T0, Config.TUTORIAL_STEAL_SKIP_SECONDS - 2)
		expect(TutorialProgress.currentId(s.data)).toBe("Steal")
		t = run(world, t, 4)
		expect(TutorialProgress.currentId(s.data)).toBe("Rebirth")
		World.tutorial(world, s, "Rebirth")
		expect(s.data.tutorialStep).toBe(0)
	end)

	it("waits while another player has a slime on a pad", function()
		local world = ServerFixtures.world()
		local a = ServerFixtures.join(world, 1)
		ServerFixtures.join(world, 2, { Fixtures.slime("b1", 1) })
		a.data.tutorialStep = 6
		run(world, T0, Config.TUTORIAL_STEAL_SKIP_SECONDS * 2)
		expect(TutorialProgress.currentId(a.data)).toBe("Steal")
	end)
end)
