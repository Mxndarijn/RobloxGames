--!strict
local Config = require("../src/shared/Config")
local DespawnTelegraph = require("../src/shared/DespawnTelegraph")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local W = 5
local EXPIRES = 100

describe("DespawnTelegraph timing", function()
	it("warns W seconds before expiresAt", function()
		expect(DespawnTelegraph.warnStartsAt(EXPIRES, W)).toBe(95)
	end)
	it("warn window is [expiresAt - W, expiresAt)", function()
		expect(DespawnTelegraph.inWarnWindow(94.99, EXPIRES, W)).toBe(false)
		expect(DespawnTelegraph.inWarnWindow(95, EXPIRES, W)).toBe(true)
		expect(DespawnTelegraph.inWarnWindow(99.99, EXPIRES, W)).toBe(true)
		expect(DespawnTelegraph.inWarnWindow(100, EXPIRES, W)).toBe(false)
	end)
	it("attribute is expiresAt only inside the window and only when enabled", function()
		expect(DespawnTelegraph.attributeValue(90, EXPIRES, W, true)).toBeNil()
		expect(DespawnTelegraph.attributeValue(95, EXPIRES, W, true)).toBe(EXPIRES)
		expect(DespawnTelegraph.attributeValue(99.5, EXPIRES, W, true)).toBe(EXPIRES)
		expect(DespawnTelegraph.attributeValue(100, EXPIRES, W, true)).toBeNil()
		expect(DespawnTelegraph.attributeValue(130, EXPIRES, W, true)).toBeNil()
		expect(DespawnTelegraph.attributeValue(97, EXPIRES, W, false)).toBeNil()
	end)
	it("removes only at expiresAt", function()
		expect(DespawnTelegraph.shouldRemove(99.99, EXPIRES)).toBe(false)
		expect(DespawnTelegraph.shouldRemove(100, EXPIRES)).toBe(true)
		expect(DespawnTelegraph.shouldRemove(101, EXPIRES)).toBe(true)
	end)
	it("counts down 5, 4, 3, 2, 1, then 0", function()
		expect(DespawnTelegraph.countdownSeconds(95, EXPIRES)).toBe(5)
		expect(DespawnTelegraph.countdownSeconds(95.5, EXPIRES)).toBe(5)
		expect(DespawnTelegraph.countdownSeconds(96, EXPIRES)).toBe(4)
		expect(DespawnTelegraph.countdownSeconds(99.1, EXPIRES)).toBe(1)
		expect(DespawnTelegraph.countdownSeconds(100, EXPIRES)).toBe(0)
		expect(DespawnTelegraph.countdownSeconds(103, EXPIRES)).toBe(0)
	end)
	it("progress runs 0 -> 1 over the window and clamps", function()
		expect(DespawnTelegraph.progress(90, EXPIRES, W)).toBe(0)
		expect(DespawnTelegraph.progress(95, EXPIRES, W)).toBe(0)
		expect(DespawnTelegraph.progress(97.5, EXPIRES, W)).toBe(0.5)
		expect(DespawnTelegraph.progress(100, EXPIRES, W)).toBe(1)
		expect(DespawnTelegraph.progress(105, EXPIRES, W)).toBe(1)
		expect(DespawnTelegraph.progress(97, EXPIRES, 0)).toBe(1)
	end)
	it("warn window fits inside both lifetimes", function()
		expect(Config.DESPAWN_TELEGRAPH_SECONDS > 0).toBeTruthy()
		expect(Config.DESPAWN_TELEGRAPH_SECONDS < Config.WILD_LIFETIME).toBeTruthy()
		expect(Config.DESPAWN_TELEGRAPH_SECONDS < Config.BOSS_LIFETIME).toBeTruthy()
		expect(type(Config.FEATURES.DespawnTelegraph)).toBe("boolean")
	end)
end)

describe("DespawnTelegraph in Scene / Spawner", function()
	local enabled = Config.FEATURES.DespawnTelegraph
	local warnAt = T0 + Config.WILD_LIFETIME - Config.DESPAWN_TELEGRAPH_SECONDS

	it("Scene sets despawnAt on a wild slime only inside the window", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		local expiresAt = world.wild[id].expiresAt
		expect(Scene.describe(world, warnAt - 0.1)[id].despawnAt).toBeNil()
		local inside = Scene.describe(world, warnAt)[id].despawnAt
		if enabled then
			expect(inside).toBe(expiresAt)
		else
			expect(inside).toBeNil()
		end
	end)
	it("Scene sets despawnAt on a wild Boss Slime too", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnBoss(world, T0)
		local at = T0 + Config.BOSS_LIFETIME - 1
		expect(Scene.describe(world, at)[id].despawnAt).toBe(if enabled then T0 + Config.BOSS_LIFETIME else nil)
	end)
	it("carried slimes never get despawnAt", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		world.carriedBy[id] = 99
		expect(Scene.describe(world, warnAt + 1)[id].despawnAt).toBeNil()
	end)
	it("the wild slime stays through the whole window and goes at expiresAt", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		world.nextSpawnAt = math.huge
		for t = warnAt, warnAt + Config.DESPAWN_TELEGRAPH_SECONDS - 0.5, 0.5 do
			Spawner.step(world, t)
			expect(world.wild[id] ~= nil).toBeTruthy()
		end
		Spawner.step(world, T0 + Config.WILD_LIFETIME)
		expect(world.wild[id]).toBeNil()
	end)
	it("carried slimes outlive expiresAt", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		world.carriedBy[id] = 99
		world.nextSpawnAt = math.huge
		Spawner.step(world, T0 + Config.WILD_LIFETIME + 10)
		expect(world.wild[id] ~= nil).toBeTruthy()
	end)
end)
