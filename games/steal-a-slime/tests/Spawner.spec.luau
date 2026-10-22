--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Fountain = require("../src/shared/Fountain")
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
	it("has no cap: keeps dropping however many wild slimes are alive", function()
		local world = ServerFixtures.world()
		for _ = 1, 300 do
			Spawner.spawnOne(world, T0)
		end
		world.nextSpawnAt = 0
		Spawner.step(world, T0 + 1)
		expect(Spawner.wildCount(world)).toBe(301)
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
	it("sends no heads-up toast before a rain", function()
		local world = ServerFixtures.world()
		local start = T0 + Config.RAIN_FIRST_AT
		local before = #world.outbox
		Spawner.step(world, start - 30)
		Spawner.step(world, start - 1)
		for k = before + 1, #world.outbox do
			local e = world.outbox[k]
			expect(e.type == "Notify" and string.find(e.text or "", "Slime Rain", 1, true) ~= nil).toBe(false)
		end
	end)
	it("spawns on the rain interval and builds a bigger crowd during rain", function()
		local world = ServerFixtures.world()
		local start = T0 + Config.RAIN_FIRST_AT
		local t = start
		while t < start + 30 do
			GameLoop.step(world, t)
			t += 0.25
		end
		local expected = math.floor(30 / Config.RAIN_SPAWN_INTERVAL)
		expect(Spawner.wildCount(world) >= expected - 1).toBeTruthy()
		while t < start + Config.RAIN_DURATION - 1 do
			GameLoop.step(world, t)
			t += 0.25
		end
		-- Unclaimed drops expire after WILD_LIFETIME, so the crowd levels off at about lifetime / interval.
		local steady = math.floor(Config.WILD_LIFETIME / Config.RAIN_SPAWN_INTERVAL)
		expect(Spawner.wildCount(world) >= steady - 1).toBeTruthy()
		expect(Spawner.wildCount(world) > Config.WILD_LIFETIME / Config.SPAWN_INTERVAL).toBeTruthy()
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

describe("Spawner and the boss event", function()
	it("the boss never counts in wildCount and never expires through the fountain", function()
		local world = ServerFixtures.world()
		world.wild.boss = {
			slime = Fixtures.slime("boss", 6),
			price = 0,
			spawnedAt = T0,
			expiresAt = T0 + 1,
			angle = 0,
			radius = 40,
			boss = true,
		}
		expect(Spawner.wildCount(world)).toBe(0)
		world.nextSpawnAt = math.huge
		Spawner.step(world, T0 + Config.WILD_LIFETIME * 2)
		expect(world.wild.boss ~= nil).toBe(true)
	end)
	it("spawnBonus adds free slimes", function()
		local world = ServerFixtures.world()
		for _ = 1, 20 do
			Spawner.spawnOne(world, T0)
		end
		local ids = Spawner.spawnBonus(world, T0, 2, 3)
		expect(#ids).toBe(2)
		expect(Spawner.wildCount(world)).toBe(22)
		for _, id in ids do
			local wild = world.wild[id]
			expect(wild.price).toBe(0)
			expect(wild.expiresAt).toBe(wild.spawnedAt + Fountain.wildLifetime(wild.slime))
		end
	end)
	it("drops take turns on the fountain slide: never two within SLIDE_GAP, bonus drops included", function()
		if not Config.FEATURES.Parade then
			return
		end
		local BONUS = 6
		local world = ServerFixtures.world()
		Spawner.spawnOne(world, T0)
		local ids = Spawner.spawnBonus(world, T0, BONUS, 3)
		Spawner.spawnOne(world, T0 + 1)
		local times = {}
		for _, wild in world.wild do
			table.insert(times, wild.spawnedAt)
		end
		table.sort(times)
		expect(#times).toBe(BONUS + 2)
		expect(times[1]).toBe(T0)
		for i = 2, #times do
			expect(times[i] - times[i - 1] >= Spawner.SLIDE_GAP - 1e-4).toBe(true) -- server-time sized floats
		end
		expect(#ids).toBe(BONUS)
	end)
end)
