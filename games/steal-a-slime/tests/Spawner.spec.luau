--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local GameLoop = require("../src/server/GameLoop")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("Spawner", function()
	it("spawns one wild slime per SPAWN_INTERVAL", function()
		local world = ServerFixtures.world()
		Spawner.step(world, T0)
		expect(Spawner.wildCount(world)).toBe(1)
		Spawner.step(world, T0 + Config.SPAWN_INTERVAL - 0.1)
		expect(Spawner.wildCount(world)).toBe(1)
		Spawner.step(world, T0 + Config.SPAWN_INTERVAL)
		expect(Spawner.wildCount(world)).toBe(2)
	end)
	it("never exceeds MAX_WILD_SLIMES outside rain", function()
		local world = ServerFixtures.world()
		for i = 0, Config.MAX_WILD_SLIMES + 5 do
			Spawner.step(world, T0 + i * Config.SPAWN_INTERVAL * 0.01) -- before expiry
			world.nextSpawnAt = 0
		end
		expect(Spawner.wildCount(world)).toBe(Config.MAX_WILD_SLIMES)
	end)
	it("expires uncarried slimes after WILD_LIFETIME but keeps carried ones", function()
		local world = ServerFixtures.world()
		local a = Spawner.spawnOne(world, T0)
		local b = Spawner.spawnOne(world, T0)
		world.carriedBy[b] = 99
		world.nextSpawnAt = math.huge
		Spawner.step(world, T0 + Config.WILD_LIFETIME)
		expect(world.wild[a]).toBeNil()
		expect(world.wild[b] ~= nil).toBeTruthy()
	end)
	it("prices: free under FREE_DROP_CHANCE, else WILD_PRICE_SECONDS of base income", function()
		local slime = Fixtures.slime("w", 2, { size = 1 })
		expect(Spawner.price(slime, 0)).toBe(0)
		expect(Spawner.price(slime, Config.FREE_DROP_CHANCE - 0.01)).toBe(0)
		expect(Spawner.price(slime, 0.99)).toBe(3 * Config.WILD_PRICE_SECONDS)
	end)
	it("about FREE_DROP_CHANCE of spawns are free", function()
		local world = ServerFixtures.world()
		local free = 0
		for _ = 1, 2000 do
			local id = Spawner.spawnOne(world, T0)
			if world.wild[id].price == 0 then
				free += 1
			end
			world.wild[id] = nil
		end
		expect(math.abs(free / 2000 - Config.FREE_DROP_CHANCE) < 0.04).toBeTruthy()
	end)
end)

describe("Spawner Slime Rain", function()
	it("starts at RAIN_FIRST_AT, lasts RAIN_DURATION and repeats every RAIN_INTERVAL", function()
		local world = ServerFixtures.world()
		local active, endsAt, nextAt = Spawner.rain(world, T0)
		expect(active).toBe(false)
		expect(endsAt).toBeNil()
		expect(nextAt).toBe(T0 + Config.RAIN_FIRST_AT)
		active, endsAt = Spawner.rain(world, T0 + Config.RAIN_FIRST_AT + 1)
		expect(active).toBe(true)
		expect(endsAt).toBe(T0 + Config.RAIN_FIRST_AT + Config.RAIN_DURATION)
		active = Spawner.rain(world, T0 + Config.RAIN_FIRST_AT + Config.RAIN_DURATION)
		expect(active).toBe(false)
		active = Spawner.rain(world, T0 + Config.RAIN_FIRST_AT + Config.RAIN_INTERVAL + 5)
		expect(active).toBe(true)
	end)
	it("announces start and end once and marks players dirty", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.dirty = false
		local start = T0 + Config.RAIN_FIRST_AT
		Spawner.step(world, start)
		Spawner.step(world, start + 1)
		local rains = 0
		for _, e in world.outbox do
			if e.type == "Rain" then
				rains += 1
				expect(e.active).toBe(true)
			end
		end
		expect(rains).toBe(1)
		expect(s.dirty).toBe(true)
		Spawner.step(world, start + Config.RAIN_DURATION)
		expect(world.raining).toBe(false)
	end)
	it("warns everyone once RAIN_WARNING_SECONDS before each rain", function()
		local world = ServerFixtures.world()
		local function warnings(): number
			local n = 0
			for _, e in world.outbox do
				if e.type == "Notify" and e.userId == nil and string.find(e.text or "", "in 1 minute", 1, true) then
					n += 1
				end
			end
			return n
		end
		local start = T0 + Config.RAIN_FIRST_AT
		Spawner.step(world, start - Config.RAIN_WARNING_SECONDS - 1)
		expect(warnings()).toBe(0)
		Spawner.step(world, start - Config.RAIN_WARNING_SECONDS + 1)
		Spawner.step(world, start - 10)
		expect(warnings()).toBe(1)
		Spawner.step(world, start)
		Spawner.step(world, start + Config.RAIN_DURATION)
		Spawner.step(world, start + Config.RAIN_INTERVAL - 30)
		expect(warnings()).toBe(2)
	end)
	it("spawns faster and allows a bigger crowd during rain", function()
		local world = ServerFixtures.world()
		local start = T0 + Config.RAIN_FIRST_AT
		local t = start
		while t < start + 30 do
			GameLoop.step(world, t)
			t += 0.25
		end
		local expected = math.floor(30 / Config.RAIN_SPAWN_INTERVAL)
		expect(Spawner.wildCount(world) >= math.min(expected - 1, Config.MAX_WILD_SLIMES * 2)).toBeTruthy()
		expect(Spawner.wildCount(world) > Config.MAX_WILD_SLIMES).toBeTruthy()
	end)
	it("rain drops are luckier than normal drops", function()
		local function rareShare(raining: boolean): number
			local world = ServerFixtures.world()
			world.raining = raining
			local rare = 0
			for _ = 1, 3000 do
				local id = Spawner.spawnOne(world, T0)
				if world.wild[id].slime.tier >= 3 then
					rare += 1
				end
				world.wild[id] = nil
			end
			return rare / 3000
		end
		expect(rareShare(true) > rareShare(false) * 2).toBeTruthy()
	end)
	it("forceRain starts a rain right now", function()
		local world = ServerFixtures.world()
		Spawner.forceRain(world, T0 + 10)
		local active, endsAt = Spawner.rain(world, T0 + 11)
		expect(active).toBe(true)
		expect(endsAt).toBe(T0 + 10 + Config.RAIN_DURATION)
	end)
end)

describe("Boss Slime (FEATURES.BossSlime)", function()
	it("spawns a free, max-size Epic+ mutated boss that ignores the cap", function()
		local world = ServerFixtures.world()
		for _ = 1, Config.MAX_WILD_SLIMES do
			Spawner.spawnOne(world, T0)
		end
		local id = Spawner.spawnBoss(world, T0)
		local boss = world.wild[id]
		expect(boss.boss).toBe(true)
		expect(boss.price).toBe(0)
		expect(boss.slime.tier >= Config.BOSS_TIER).toBeTruthy()
		expect(boss.slime.size).toBe(Config.MAX_SIZE)
		expect(boss.slime.mutation ~= "None").toBeTruthy()
		expect(boss.expiresAt).toBe(T0 + Config.BOSS_LIFETIME)
		expect(Spawner.bossId(world)).toBe(id)
	end)
	it("spills on schedule, one at a time, and announces the catch", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local first = T0 + Config.BOSS_FIRST_AT
		Spawner.step(world, first - 1)
		expect(Spawner.bossId(world)).toBeNil()
		Spawner.step(world, first)
		local id = Spawner.bossId(world)
		expect(id ~= nil).toBeTruthy()
		expect(world.nextBossAt).toBe(first + Config.BOSS_INTERVAL)
		assert(id, "boss spawned")
		expect((Carry.grab(world, 1, id, 1, first + 1))).toBe(true)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(s.data.slimes[1].id).toBe(id)
		expect(Spawner.bossId(world)).toBeNil()
		local caught = false
		for _, e in world.outbox do
			if e.type == "Notify" and e.userId == nil and string.find(e.text or "", "caught the Boss", 1, true) then
				caught = true
			end
		end
		expect(caught).toBe(true)
	end)
	it("reports State.boss and pushes State to everyone when it starts and ends", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local first = T0 + Config.BOSS_FIRST_AT
		local active, endsAt = Spawner.boss(world)
		expect(active).toBe(false)
		expect(endsAt).toBeNil()
		Spawner.step(world, first - 1)
		s.dirty = false
		Spawner.step(world, first)
		active, endsAt = Spawner.boss(world)
		expect(active).toBe(true)
		expect(endsAt).toBe(first + Config.BOSS_LIFETIME)
		expect(s.dirty).toBe(true)
		s.dirty = false
		Spawner.step(world, first + 1)
		expect(s.dirty).toBe(false)
		Spawner.step(world, first + Config.BOSS_LIFETIME)
		expect((Spawner.boss(world))).toBe(false)
		expect(s.dirty).toBe(true)
	end)
end)
