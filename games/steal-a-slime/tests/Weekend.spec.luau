--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Income = require("../src/server/Income")
local Perks = require("../src/shared/Perks")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local Weekend = require("../src/shared/Weekend")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function utc(y: number, m: number, d: number, h: number, min: number, s: number): number
	return os.time({ year = y, month = m, day = d, hour = h, min = min, sec = s }) -- Lune runs in UTC
end

describe("Weekend window", function()
	it("uses the unix epoch weekday math (1970-01-01 = Thursday)", function()
		expect(Weekend.active(0)).toBe(false)
		expect(Weekend.active(2 * 86400)).toBe(true) -- Sat 1970-01-03
		expect(Weekend.active(3 * 86400)).toBe(true) -- Sun
		expect(Weekend.active(4 * 86400)).toBe(false) -- Mon
	end)
	it("Fri 23:59:59 off, Sat 00:00 on, Sun 23:59:59 on, Mon 00:00 off", function()
		local sat = 2 * 86400
		expect(Weekend.active(sat - 1)).toBe(false)
		expect(Weekend.active(sat)).toBe(true)
		expect(Weekend.active(4 * 86400 - 1)).toBe(true)
		expect(Weekend.active(4 * 86400)).toBe(false)
		expect(Weekend.multiplier(sat - 1)).toBe(1)
		expect(Weekend.multiplier(sat)).toBe(Config.WEEKEND.multiplier)
	end)
	it("a real date: Sat 2026-10-17 is on, Mon 2026-10-19 is off", function()
		expect(Weekend.active(utc(2026, 10, 16, 23, 59, 59))).toBe(false)
		expect(Weekend.active(utc(2026, 10, 17, 0, 0, 0))).toBe(true)
		expect(Weekend.active(utc(2026, 10, 18, 23, 59, 59))).toBe(true)
		expect(Weekend.active(utc(2026, 10, 19, 0, 0, 0))).toBe(false)
	end)
	it("endsAt is Monday 00:00 UTC, nil when off", function()
		expect(Weekend.endsAt(2 * 86400 + 5)).toBe(4 * 86400)
		expect(Weekend.endsAt(3 * 86400 + 80000)).toBe(4 * 86400)
		expect(Weekend.endsAt(86400)).toBeNil()
		local view = Weekend.view(2 * 86400 + 5)
		expect(view.active).toBe(true)
		expect(view.endsAt).toBe(4 * 86400)
		expect(Weekend.view(0).active).toBe(false)
	end)
end)

describe("Weekend config", function()
	local function cfg(patch: { [string]: any }): any
		local out = table.clone(Config.WEEKEND)
		for k, v in patch do
			out[k] = v
		end
		return table.freeze(out)
	end
	it("the enabled flag off means never", function()
		local off = cfg({ enabled = false })
		expect(Weekend.active(2 * 86400, off)).toBe(false)
		expect(Weekend.multiplier(2 * 86400, off)).toBe(1)
		expect(Weekend.endsAt(2 * 86400, off)).toBeNil()
	end)
	it("override dates add whole UTC days", function()
		local c = cfg({ overrideDates = table.freeze({ "1970-01-02" }) }) -- a Friday
		expect(Weekend.active(86400, c)).toBe(true)
		expect(Weekend.active(86400 - 1, c)).toBe(false)
		expect(Weekend.endsAt(86400, c)).toBe(4 * 86400) -- runs into the real weekend
		expect(Weekend.active(4 * 86400, c)).toBe(false)
	end)
	it("a multiplier of 1 or less never doubles", function()
		expect(Weekend.active(2 * 86400, cfg({ multiplier = 1 }))).toBe(false)
	end)
end)

describe("Weekend income", function()
	it("Perks.bonusMultiplier multiplies by weekendMult and ignores < 1", function()
		local data = Fixtures.data()
		local base = Perks.bonusMultiplier(data)
		data.weekendMult = 2
		expect(math.abs(Perks.bonusMultiplier(data) - base * 2) < 1e-9).toBe(true)
		data.weekendMult = 0.5
		expect(math.abs(Perks.bonusMultiplier(data) - base) < 1e-9).toBe(true)
	end)
	it("stacks multiplicatively with the code boost", function()
		local data = Fixtures.data()
		data.boostMult = 3
		local base = Perks.bonusMultiplier(data)
		data.weekendMult = 2
		expect(math.abs(Perks.bonusMultiplier(data) - base * 2) < 1e-9).toBe(true)
	end)
	it("Income.step doubles pay on a weekend and not otherwise or without a clock", function()
		local function earned(now: number?): number
			local world = ServerFixtures.world()
			local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 0)
			Income.step(world, 1, now)
			return s.data.cash + s.incomeRemainder
		end
		local plain = earned(nil)
		expect(plain > 0).toBe(true)
		expect(math.abs(earned(0) - plain) < 1e-9).toBe(true) -- Thursday
		expect(math.abs(earned(2 * 86400) - plain * 2) < 1e-9).toBe(true) -- Saturday
		expect(math.abs(earned(4 * 86400) - plain) < 1e-9).toBe(true) -- Monday again
	end)
end)
