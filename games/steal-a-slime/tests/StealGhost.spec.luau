--!strict
-- A see-through copy stays on the pad while a thief carries the slime away, and only then.
local Carry = require("../src/server/Carry")
local Fixtures = require("./Fixtures")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local StealGhost = require("../src/server/StealGhost")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("StealGhost.wants", function()
	it("shows while a thief carries a pad slime, and not before or after", function()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		expect(StealGhost.wants(Scene.describe(world, T0)["a"])).toBe(false)
		Carry.grab(world, 2, "a", 1, T0)
		expect(StealGhost.wants(Scene.describe(world, T0)["a"])).toBe(true)
		Carry.deposit(world, 2)
		expect(StealGhost.wants(Scene.describe(world, T0)["a"])).toBe(false)
	end)
	it("never shows for a carried wild slime", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 2, nil, 1e12)
		local id = Spawner.spawnOne(world, T0)
		Carry.grab(world, 2, id, 1, T0)
		local e = Scene.describe(world, T0)[id]
		expect(e.state).toBe("Carried")
		expect(StealGhost.wants(e)).toBe(false)
	end)
	it("never shows when the owner carries their own slime", function()
		expect(StealGhost.wants({ state = "Carried", ownerUserId = 1, carrierUserId = 1, plotIndex = 1, pad = 1 })).toBe(
			false
		)
	end)
end)

describe("StealGhost.fade", function()
	it("only ever makes a part more see-through", function()
		expect(StealGhost.fade(0, 0.6)).toBe(0.6)
		expect(StealGhost.fade(1, 0.6)).toBe(1)
		expect(StealGhost.fade(0.5, 0.6) > 0.5).toBe(true)
	end)
end)
