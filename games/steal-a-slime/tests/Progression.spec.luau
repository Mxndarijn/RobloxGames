--!strict
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local Progression = require("../src/shared/Progression")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local slime = Fixtures.slime
local FIRST = Config.REBIRTH_SLIMES[1][1] -- the species rebirth 1 uses up

describe("Rebirth", function()
	it("needs enough cash", function()
		local data = Fixtures.data(nil, Economy.rebirthCost(0) - 1)
		expect((Progression.rebirth(data))).toBe(false)
		expect(data.rebirths).toBe(0)
	end)
	it("resets cash, uses up the required slime and keeps every other slime on its pad", function()
		local data = Fixtures.data(
			{ slime("a", 1), slime("b", 5), slime("c", 2), slime("d", 2, { species = FIRST }) },
			Economy.rebirthCost(0) + 50
		)
		data.padsUnlocked = 7
		data.favoriteId = "c"
		local pads = {}
		for _, s in data.slimes do
			pads[s.id] = s.pad
		end
		expect((Progression.rebirth(data))).toBe(true)
		expect(data.rebirths).toBe(1)
		expect(data.cash).toBe(Config.STARTING_CASH)
		local ids = {}
		for _, s in data.slimes do
			table.insert(ids, s.id)
			expect(s.pad).toBe(pads[s.id])
		end
		expect(ids).toEqual({ "a", "b", "c" })
		expect(data.favoriteId).toBe("c")
		expect(data.padsUnlocked).toBe(7)
	end)
	it("works with just the required slime, uses it up and raises the income multiplier", function()
		local data = Fixtures.data({ slime("x", 2, { species = FIRST }) }, 1e9)
		expect((Progression.rebirth(data))).toBe(true)
		expect(#data.slimes).toBe(0)
		local s = slime("x", 1)
		expect(Economy.slimeIncome(s, data.rebirths)).toBe(1 + Economy.rebirthStep(1))
	end)
	it("next rebirth costs more", function()
		local data = Fixtures.data({ slime("x", 2, { species = FIRST }) }, Economy.rebirthCost(0))
		expect((Progression.rebirth(data))).toBe(true)
		expect(Economy.rebirthCost(data.rebirths) > Economy.rebirthCost(0)).toBe(true)
		data.cash = Economy.rebirthCost(0)
		expect(select(2, Progression.canRebirth(data))).toBe("not enough cash")
	end)
	it("stops at MAX_REBIRTHS", function()
		local data = Fixtures.data(nil, 1e15)
		data.rebirths = Config.MAX_REBIRTHS
		expect(select(2, Progression.canRebirth(data))).toBe("max rebirths reached")
	end)
end)

describe("Daily reward", function()
	local DAY = 86400
	it("first claim gives streak 1", function()
		local data = Fixtures.data(nil, 0)
		local ok, amount = Progression.claimDaily(data, 100 * DAY + 5)
		expect(ok).toBe(true)
		expect(amount).toBe(Config.DAILY_BASE)
		expect(data.cash).toBe(Config.DAILY_BASE)
		expect(data.daily.streak).toBe(1)
	end)
	it("only once per UTC day", function()
		local data = Fixtures.data(nil, 0)
		Progression.claimDaily(data, 100 * DAY + 5)
		expect(Progression.dailyAvailable(data.daily, 100 * DAY + 80000)).toBe(false)
		expect((Progression.claimDaily(data, 100 * DAY + 80000))).toBe(false)
		expect(Progression.dailyAvailable(data.daily, 101 * DAY)).toBe(true)
	end)
	it("consecutive days grow the streak (capped), a gap resets it", function()
		local data = Fixtures.data(nil, 0)
		for d = 1, 10 do
			Progression.claimDaily(data, (100 + d) * DAY)
		end
		expect(data.daily.streak).toBe(10)
		expect(Progression.dailyAmount(10, 0)).toBe(Config.DAILY_BASE * Config.DAILY_STREAK_CAP)
		Progression.claimDaily(data, 115 * DAY)
		expect(data.daily.streak).toBe(1)
	end)
	it("scales with rebirths", function()
		expect(Progression.dailyAmount(1, 2)).toBe(math.floor(Config.DAILY_BASE * Economy.rebirthMultiplier(2)))
	end)
end)

describe("Slime Rain schedule", function()
	it("waits for the first rain", function()
		local active, left = Progression.rainStatus(0)
		expect(active).toBe(false)
		expect(left).toBe(Config.RAIN_FIRST_AT)
	end)
	it("rains for RAIN_DURATION then waits for the next interval", function()
		local t = Config.RAIN_FIRST_AT
		local active, left = Progression.rainStatus(t + 10)
		expect(active).toBe(true)
		expect(left).toBe(Config.RAIN_DURATION - 10)
		active, left = Progression.rainStatus(t + Config.RAIN_DURATION)
		expect(active).toBe(false)
		expect(left).toBe(Config.RAIN_INTERVAL - Config.RAIN_DURATION)
		expect((Progression.rainStatus(t + Config.RAIN_INTERVAL + 1))).toBe(true)
	end)
	it("can be forced early", function()
		local active, left = Progression.rainStatus(10, 40)
		expect(active).toBe(true)
		expect(left).toBe(30)
	end)
end)
