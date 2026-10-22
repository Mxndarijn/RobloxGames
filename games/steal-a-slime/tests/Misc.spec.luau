--!strict
local Config = require("../src/shared/Config")
local Fountain = require("../src/shared/Fountain")
local ParadeLane = require("../src/shared/ParadeLane")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Validate", function()
	it("accepts GUID-style slime ids only", function()
		expect(Validate.slimeId("{0A1B-2C3D}")).toBe("{0A1B-2C3D}")
		expect(Validate.slimeId("abc_123")).toBe("abc_123")
		expect(Validate.slimeId("")).toBeNil()
		expect(Validate.slimeId(42)).toBeNil()
		expect(Validate.slimeId("a b")).toBeNil()
		expect(Validate.slimeId(string.rep("a", 65))).toBeNil()
		expect(Validate.slimeId({})).toBeNil()
	end)
	it("accepts only known actions", function()
		expect(Validate.action("Merge")).toBe("Merge")
		expect(Validate.action("GiveMeCash")).toBeNil()
		expect(Validate.action(nil)).toBeNil()
	end)
	it("rate-limits per action", function()
		local limiter = {}
		expect(Validate.allow(limiter, "Rebirth", 10)).toBe(true)
		expect(Validate.allow(limiter, "Rebirth", 11)).toBe(false)
		expect(Validate.allow(limiter, "Merge", 11)).toBe(true)
		expect(Validate.allow(limiter, "Rebirth", 12)).toBe(true)
		expect(Validate.allow(limiter, "Nope", 12)).toBe(false)
	end)
end)

describe("Fountain", function()
	it("drops land in the ring around the fountain", function()
		local rng = Rng.new(3)
		for i = 1, 200 do
			local d = Fountain.roll(rng, tostring(i), false)
			expect(d.radius >= Fountain.MIN_RADIUS and d.radius <= Fountain.MAX_RADIUS).toBeTruthy()
			expect(d.angle >= 0 and d.angle < math.pi * 2).toBeTruthy()
			expect(d.slime.id).toBe(tostring(i))
		end
	end)
	it("no spawn, bonus drop, dropped spot or lane step lands in the ring band (r 31-34, plus margin)", function()
		local SAFE = Fountain.RING_BAND_OUTER + Fountain.SLIME_RADIUS -- whole slime past the curb
		expect(Fountain.RING_BAND_INNER <= 31 and Fountain.RING_BAND_OUTER >= 34).toBe(true)
		local world = ServerFixtures.world()
		for i = 1, 300 do
			local id = if i % 10 == 0 then Spawner.spawnBonus(world, 0, 1, 3)[1] else Spawner.spawnOne(world, 0)
			local wild = world.wild[id]
			expect(wild.radius >= SAFE).toBe(true)
			-- walking the lane (the wander route), whatever lateral offset the roll gives
			local lateral = ParadeLane.lateral(wild.radius, Fountain.MIN_RADIUS, Fountain.MAX_RADIUS)
			for k = 0, 40 do
				local pose = ParadeLane.pose(0, 100, lateral, k * 2.5)
				local r = math.sqrt(pose.position[1] ^ 2 + pose.position[3] ^ 2)
				-- the lead-in from the slide mouth runs through the landing ring's open gap (still Riding)
				expect(ParadeLane.distance(0, 100, k * 2.5) < 0 or r >= SAFE).toBe(true)
			end
		end
		-- dropped spots anywhere in or near the band are pushed out; others are untouched
		for r = 0, 70, 0.5 do
			for a = 0, 330, 30 do
				local x, z = Fountain.clearOfRing(math.cos(math.rad(a)) * r, math.sin(math.rad(a)) * r)
				local out = math.sqrt(x * x + z * z)
				expect(out <= Fountain.RING_BAND_INNER - Fountain.SLIME_RADIUS or out >= Fountain.MIN_RADIUS - 1e-6).toBe(
					true
				)
				if r >= Fountain.MIN_RADIUS or r < Fountain.RING_BAND_INNER - Fountain.SLIME_RADIUS - 1e-6 then
					expect(out).toBeCloseTo(r)
				end
			end
		end
		for _, r in { 31, 32.5, 34, 38, 44.4 } do
			local x, z = Fountain.clearOfRing(r, 0)
			expect(x).toBeCloseTo(Fountain.MIN_RADIUS)
			expect(z).toBeCloseTo(0)
		end
	end)
	it("Slime Rain drops rarer slimes", function()
		local r1, r2 = Rng.new(9), Rng.new(9)
		local normalRare, rainRare = 0, 0
		for i = 1, 3000 do
			local a = Fountain.roll(r1, tostring(i), false).slime
			local b = Fountain.roll(r2, tostring(i), true).slime
			normalRare += if a.tier >= 3 then 1 else 0
			rainRare += if b.tier >= 3 then 1 else 0
		end
		expect(rainRare > normalRare * 1.5).toBeTruthy()
	end)
	it("rain uses its own interval", function()
		expect(Fountain.spawnInterval(true)).toBe(Config.RAIN_SPAWN_INTERVAL)
		expect(Fountain.spawnInterval(false)).toBe(Config.SPAWN_INTERVAL)
	end)
end)

describe("Config", function()
	it("is frozen and rarities are ordered", function()
		expect(table.isfrozen(Config)).toBe(true)
		for i, r in Config.RARITIES do
			expect(r.tier).toBe(i)
			if i > 1 then
				expect(r.income > Config.RARITIES[i - 1].income).toBeTruthy()
				expect(r.weight < Config.RARITIES[i - 1].weight).toBeTruthy()
			end
		end
	end)
end)

describe("DayNight.clockTime", function()
	local DayNight = require("../src/shared/DayNight")
	it("runs sunrise -> sunset over the day fraction, then the night back to sunrise", function()
		expect(DayNight.clockTime(0)).toBeCloseTo(DayNight.SUNRISE)
		expect(DayNight.clockTime(Config.DAY_LENGTH * Config.DAY_FRACTION)).toBeCloseTo(DayNight.SUNSET)
		local midnight = Config.DAY_LENGTH * (Config.DAY_FRACTION + (1 - Config.DAY_FRACTION) * (6.5 / 13))
		expect(DayNight.clockTime(midnight)).toBeCloseTo(0)
		expect(DayNight.clockTime(Config.DAY_LENGTH)).toBeCloseTo(DayNight.SUNRISE)
		for t = 0, Config.DAY_LENGTH, 7 do
			local c = DayNight.clockTime(t)
			expect(c >= 0 and c < 24).toBeTruthy()
		end
	end)
end)
