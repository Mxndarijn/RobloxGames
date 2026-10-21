--!strict
-- End-to-end: the whole server loop on a fake clock, no Roblox.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local GameLoop = require("../src/server/GameLoop")
local PlayerData = require("../src/shared/PlayerData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("GameLoop end to end", function()
	it("grab a drop, earn from it, get it stolen, chase it home", function()
		local world = ServerFixtures.world()
		local alice = ServerFixtures.join(world, 1, nil, 1000)
		local bob = ServerFixtures.join(world, 2, nil, 0)
		GameLoop.step(world, T0)
		local id = next(world.wild)
		assert(type(id) == "string", "a slime dropped")

		expect((Carry.grab(world, 1, id, 2, T0))).toBe(true)
		expect((Carry.deposit(world, 1))).toBe(true)
		local cashAfterGrab = alice.data.cash

		local t = T0
		for _ = 1, 40 do
			t += 0.25
			GameLoop.step(world, t)
		end
		expect(alice.data.cash > cashAfterGrab).toBeTruthy()

		-- Alice's join lock runs out; Bob steals, holds it a long while, then drops it.
		t = T0 + Config.JOIN_LOCK_SECONDS
		GameLoop.step(world, t)
		expect((Carry.grab(world, 2, id, 2, t))).toBe(true)
		for _ = 1, 240 do
			t += 0.25
			GameLoop.step(world, t)
		end
		expect(bob.carry ~= nil).toBeTruthy()
		expect((Carry.release(world, 2, t, nil, "drop"))).toBe(true)
		expect(world.escaping[id] ~= nil).toBeTruthy()
		for _ = 1, 10 do
			t += 0.25
			GameLoop.step(world, t)
		end
		expect(world.escaping[id]).toBeNil()
		expect(PlayerData.findSlime(alice.data, id) ~= nil).toBeTruthy()
		expect(PlayerData.findSlime(bob.data, id)).toBeNil()
	end)
end)
