--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local GameLoop = require("../src/server/GameLoop")
local Income = require("../src/server/Income")
local PlayerData = require("../src/shared/PlayerData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("Income.step", function()
	it("pays plot income per second and tracks totalEarned", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2), Fixtures.slime("b", 1) }, 0)
		Income.step(world, 1)
		expect(s.data.cash).toBe(4)
		expect(s.data.totalEarned).toBe(4)
		expect(s.dirty).toBe(true)
	end)
	it("keeps fractional income in the remainder", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1, { size = 0.8 }) }, 0)
		for _ = 1, 5 do
			Income.step(world, 1)
		end
		expect(s.data.cash).toBe(4)
		expect(s.incomeRemainder).toBeCloseTo(0, 1e-3)
	end)
	it("applies the rebirth multiplier", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 3) }, 0)
		s.data.rebirths = 2
		Income.step(world, 1)
		expect(s.data.cash).toBe(math.floor(9 * Economy.rebirthMultiplier(2)))
	end)
	it("caps a single tick at MAX_TICK seconds", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) }, 0)
		Income.step(world, 1000)
		expect(s.data.cash).toBe(Income.MAX_TICK)
	end)
	it("skips slimes that are being carried away", function()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1), Fixtures.slime("b", 2) }, 0)
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		Carry.grab(world, 2, "b", 1, T0)
		Income.step(world, 1)
		expect(victim.data.cash).toBe(1)
	end)
	it("runs once a second from GameLoop.step", function()
		local world = ServerFixtures.world()
		world.nextSpawnAt = math.huge
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) }, 0)
		local t = T0
		for _ = 1, 16 do
			t += 0.25
			GameLoop.step(world, t)
		end
		expect(s.data.cash).toBe(4)
	end)
end)

describe("Income.applyOffline", function()
	it("pays OFFLINE_RATE of income for the time away, on join", function()
		local world = ServerFixtures.world()
		local data = Fixtures.data({ Fixtures.slime("a", 2) }, 0)
		data.lastOnline = T0 - 100
		data.padsUnlocked = Config.PADS_START -- no Pads goal reward on join
		local s = Sessions.join(world, 1, "P1", data, T0)
		assert(s, "session")
		expect(s.data.cash).toBe(math.floor(3 * 100 * Config.OFFLINE_RATE))
		expect(#ServerFixtures.notifications(world, 1)).toBe(1)
	end)
	it("caps offline income at OFFLINE_CAP_SECONDS", function()
		local world = ServerFixtures.world()
		local data = Fixtures.data({ Fixtures.slime("a", 1) }, 0)
		data.lastOnline = T0 - Config.OFFLINE_CAP_SECONDS * 10
		data.padsUnlocked = Config.PADS_START
		local s = Sessions.join(world, 1, "P1", data, T0)
		assert(s, "session")
		expect(s.data.cash).toBe(math.floor(Config.OFFLINE_CAP_SECONDS * Config.OFFLINE_RATE))
	end)
	it("pays nothing to new players or on clock skew", function()
		local world = ServerFixtures.world()
		local fresh = PlayerData.new()
		local s = Sessions.join(world, 1, "P1", fresh, T0)
		assert(s, "session")
		expect(s.data.cash).toBe(Config.STARTING_CASH)
		local skewed = Fixtures.data({ Fixtures.slime("a", 1) }, 0)
		skewed.lastOnline = T0 + 500
		expect(Income.applyOffline(world, { userId = 2, data = skewed } :: any, T0)).toBe(0)
	end)
end)
