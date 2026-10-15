--!strict
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local Volcano = require("../src/shared/Volcano")

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

describe("Volcano", function()
	it("drops land in the ring around the volcano", function()
		local rng = Rng.new(3)
		for i = 1, 200 do
			local d = Volcano.roll(rng, tostring(i), false)
			expect(d.radius >= Volcano.MIN_RADIUS and d.radius <= Volcano.MAX_RADIUS).toBeTruthy()
			expect(d.angle >= 0 and d.angle < math.pi * 2).toBeTruthy()
			expect(d.slime.id).toBe(tostring(i))
		end
	end)
	it("Slime Rain drops more mutations and rarer slimes", function()
		local r1, r2 = Rng.new(9), Rng.new(9)
		local normalMut, rainMut, normalRare, rainRare = 0, 0, 0, 0
		for i = 1, 3000 do
			local a = Volcano.roll(r1, tostring(i), false).slime
			local b = Volcano.roll(r2, tostring(i), true).slime
			normalMut += if a.mutation ~= "None" then 1 else 0
			rainMut += if b.mutation ~= "None" then 1 else 0
			normalRare += if a.tier >= 3 then 1 else 0
			rainRare += if b.tier >= 3 then 1 else 0
		end
		expect(rainMut > normalMut * 4).toBeTruthy()
		expect(rainRare > normalRare * 1.5).toBeTruthy()
	end)
	it("spawn cap and interval change during rain", function()
		expect(Volcano.canSpawn(Config.MAX_WILD_SLIMES - 1, false)).toBe(true)
		expect(Volcano.canSpawn(Config.MAX_WILD_SLIMES, false)).toBe(false)
		expect(Volcano.canSpawn(Config.MAX_WILD_SLIMES, true)).toBe(true)
		expect(Volcano.spawnInterval(true) < Volcano.spawnInterval(false)).toBeTruthy()
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
	it("escape times stay within the 15-25 s design range", function()
		for _, r in Config.RARITIES do
			expect(r.escapeTime >= 15 and r.escapeTime <= 25).toBeTruthy()
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
