--!strict
-- The Appraise screen's size tape, reroll odds and result (src/ui/AppraiseView.luau).
local Appraise = require("../../src/shared/Appraise")
local AppraiseView = require("../../src/ui/AppraiseView")
local Config = require("../../src/shared/Config")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local MIN, MAX = Config.MIN_SIZE, Config.MAX_SIZE

describe("AppraiseView odds", function()
	it("places a size on the reroll range", function()
		expect(AppraiseView.fraction(MIN, MIN, MAX)).toBe(0)
		expect(AppraiseView.fraction(MAX, MIN, MAX)).toBe(1)
		expect(AppraiseView.fraction(MAX + 1, MIN, MAX)).toBe(1)
	end)
	it("matches the real reroll: the share of rolls that land bigger", function()
		local size = 1.42
		local bigger, n = 0, 1000
		for i = 0, n - 1 do
			if Appraise.rollSize((i + 0.5) / n) > size then
				bigger += 1
			end
		end
		expect(math.abs(bigger / n - AppraiseView.betterChance(size, MIN, MAX)) < 0.01).toBe(true)
	end)
	it("warns near the top and spells out a fair chance lower down", function()
		local top = AppraiseView.odds(1.97, MIN, MAX)
		expect(top.chance).toBe("2% chance")
		expect(top.warn).toBe(true)
		expect(string.find(top.detail, "Almost any", 1, true) ~= nil).toBe(true)
		local mid = AppraiseView.odds(1.6, MIN, MAX)
		expect(mid.warn).toBe(true)
		local low = AppraiseView.odds(1.0, MIN, MAX)
		expect(low.warn).toBe(false)
		expect(low.detail).toBe("to roll bigger than 1.00.")
		expect(AppraiseView.odds(1.999, MIN, MAX).chance).toBe("<1% chance")
		expect(AppraiseView.odds(MAX, MIN, MAX).chance).toBe("No chance")
	end)
end)

describe("AppraiseView.result", function()
	it("scales income with size and says which way it went", function()
		local r = AppraiseView.result(2, 1, 100)
		expect(r.incomeAfter).toBe(50)
		expect(r.better).toBe(false)
		expect(AppraiseView.result(1, 1.5, 10).better).toBe(true)
		expect(AppraiseView.result(1.2, 1.2, 10).better).toBeNil()
	end)
	it("labels the tape every 0.2 from the smallest to the biggest size", function()
		local ticks = AppraiseView.ticks(MIN, MAX)
		expect(ticks[1]).toBe(MIN)
		expect(ticks[#ticks]).toBe(MAX)
		expect(#ticks).toBe(math.floor((MAX - MIN) / 0.2 + 0.5) + 1)
	end)
end)
