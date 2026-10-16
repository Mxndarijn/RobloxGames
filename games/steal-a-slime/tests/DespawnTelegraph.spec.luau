--!strict
local fs = require("@lune/fs")

local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local DespawnTelegraph = require("../src/shared/DespawnTelegraph")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local SlimeMesh = require("../src/server/SlimeMesh")
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

describe("DespawnTelegraph FX helpers", function()
	local FX = DespawnTelegraph.FX

	it("shrinkFactor runs 1 -> shrinkTo and clamps", function()
		expect(DespawnTelegraph.shrinkFactor(0, 0.55)).toBe(1)
		expect(DespawnTelegraph.shrinkFactor(1, 0.55)).toBe(0.55)
		expect(math.abs(DespawnTelegraph.shrinkFactor(0.5, 0.55) - 0.775) < 1e-9).toBeTruthy()
		expect(DespawnTelegraph.shrinkFactor(-1, 0.55)).toBe(1)
		expect(DespawnTelegraph.shrinkFactor(2, 0.55)).toBe(0.55)
		expect(DespawnTelegraph.shrinkFactor(1, 1)).toBe(1)
	end)
	it("fallback size scales every axis by the factor", function()
		local x, y, z = DespawnTelegraph.fallbackSizeXYZ(2, 4, 6, 0.5)
		expect(x).toBe(1)
		expect(y).toBe(2)
		expect(z).toBe(3)
		x, y, z = DespawnTelegraph.fallbackSizeXYZ(2, 4, 6, 1)
		expect(x).toBe(2)
		expect(y).toBe(4)
		expect(z).toBe(6)
		local f = DespawnTelegraph.shrinkFactor(1, FX.shrinkTo)
		x, y, z = DespawnTelegraph.fallbackSizeXYZ(4, 4, 4, f)
		expect(x).toBe(4 * 0.55)
		expect(y).toBe(4 * 0.55)
		expect(z).toBe(4 * 0.55)
	end)
	it("FX table is frozen slime-green poof data", function()
		expect(table.isfrozen(FX)).toBeTruthy()
		expect(FX.texture).toBe("rbxasset://textures/particles/sparkles_main.dds")
		expect(FX.smokeTexture).toBe("rbxasset://textures/particles/smoke_main.dds")
		expect(FX.count > 0).toBeTruthy()
		expect(FX.smokeCount < FX.count).toBeTruthy()
		expect(FX.shrinkTo).toBe(0.55)
		local goo = Config.RARITIES[1].color
		for i = 1, 3 do
			expect(FX.color[i]).toBe(goo[i])
		end
		-- green-dominant, not white / grey
		expect(FX.color[2] > FX.color[1] and FX.color[2] > FX.color[3]).toBeTruthy()
		expect(FX.colorBright[2] > FX.colorBright[1] and FX.colorBright[2] > FX.colorBright[3]).toBeTruthy()
		expect(FX.blinkHz[1] < FX.blinkHz[2]).toBeTruthy()
	end)
	it("poof sound is off with a placeholder id", function()
		expect(Config.DESPAWN_POOF_SOUND).toBe(false)
		expect(Config.DESPAWN_POOF_SOUND_ID).toBe("rbxassetid://0")
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

describe("DespawnTelegraph after a carry", function()
	local enabled = Config.FEATURES.DespawnTelegraph
	local WINDOW = Config.DESPAWN_TELEGRAPH_SECONDS

	local function grabAndDrop(boss: boolean, dropAt: number): (any, string)
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, nil, 1e9)
		local id = if boss then Spawner.spawnBoss(world, T0) else Spawner.spawnOne(world, T0)
		expect((Carry.grab(world, 1, id, 5, T0 + 1))).toBe(true)
		expect(Carry.release(world, 1, dropAt, nil, "drop")).toBe(true)
		return world, id
	end

	it("a dropped wild slime gets a fresh WILD_LIFETIME and warns again before it", function()
		local dropAt = T0 + 30
		local world, id = grabAndDrop(false, dropAt)
		local expiresAt = dropAt + Config.WILD_LIFETIME
		expect(world.wild[id].expiresAt).toBe(expiresAt)
		expect(Scene.describe(world, expiresAt - WINDOW - 0.1)[id].despawnAt).toBeNil()
		expect(Scene.describe(world, expiresAt - WINDOW)[id].despawnAt).toBe(if enabled then expiresAt else nil)
	end)
	it("a dropped Boss Slime keeps the boss lifetime, not the normal one", function()
		local dropAt = T0 + 30
		local world, id = grabAndDrop(true, dropAt)
		expect(world.wild[id].expiresAt).toBe(dropAt + Config.BOSS_LIFETIME)
		local early = dropAt + Config.WILD_LIFETIME - 1 -- the old (wrong) window
		expect(Scene.describe(world, early)[id].despawnAt).toBeNil()
	end)
	it("the warning window closes in the same step the slime is removed", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		world.nextSpawnAt = math.huge
		local expiresAt = world.wild[id].expiresAt
		expect(Scene.describe(world, expiresAt - 0.01)[id].despawnAt).toBe(if enabled then expiresAt else nil)
		Spawner.step(world, expiresAt)
		expect(world.wild[id]).toBeNil()
		expect(Scene.describe(world, expiresAt)[id]).toBeNil()
	end)
	it("the Size fallback never sets CFrame on welded parts (that drags the whole slime)", function()
		local fx = fs.readFile("src/visuals/client/DespawnTelegraphFx.luau")
		local body = string.match(fx, "local function applyFallback.-\nend\n") or ""
		expect(body ~= "").toBe(true)
		expect(string.find(body, "%.CFrame%s*=") == nil).toBe(true)
		expect(string.find(body, "f.part.Position = ", 1, true) ~= nil).toBe(true)
	end)
	it("the client FX blinks the part SlimeMesh dresses the slime with", function()
		-- Body is invisible under the mesh: if these names drift the blink silently stops.
		local fx = fs.readFile("src/visuals/client/DespawnTelegraphFx.luau")
		expect(string.find(fx, `MESH_NAME = "{SlimeMesh.MESH_NAME}"`, 1, true) ~= nil).toBe(true)
	end)
end)
