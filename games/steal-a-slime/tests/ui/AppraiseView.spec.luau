--!strict
-- The Appraise screen's size tape, reroll odds and result (src/ui/AppraiseView.luau).
local Appraise = require("../../src/shared/Appraise")
local AppraiseView = require("../../src/ui/AppraiseView")
local Config = require("../../src/shared/Config")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local MIN, MAX, DEC = Config.MIN_SIZE, Config.MAX_SIZE, Config.APPRAISE_SIZE_DECIMALS

-- The real share of rolls that land strictly bigger than `size`: one roll per bin midpoint, with enough bins
-- that every rounding boundary of Appraise.rollSize falls on a bin edge, so the share is exact.
local function realChance(size: number): number
	local bigger, n = 0, 12000
	for i = 0, n - 1 do
		if Appraise.rollSize((i + 0.5) / n) > size then
			bigger += 1
		end
	end
	return bigger / n
end

describe("AppraiseView odds", function()
	it("places a size on the reroll range", function()
		expect(AppraiseView.fraction(MIN, MIN, MAX)).toBe(0)
		expect(AppraiseView.fraction(MAX, MIN, MAX)).toBe(1)
		expect(AppraiseView.fraction(MAX + 1, MIN, MAX)).toBe(1)
	end)
	it("matches the real reroll exactly: the share of rolls that land strictly bigger", function()
		for _, size in { 0.8, 1.0, 1.39, 1.4, 1.42, 1.97, 1.99, 1.999, 2.0 } do
			expect(math.abs(realChance(size) - AppraiseView.betterChance(size, MIN, MAX, DEC)) < 1e-9).toBe(true)
		end
	end)
	it("words the odds as the real reroll: never 100%, <1% just under the top, none at the top", function()
		expect(AppraiseView.odds(0.8, MIN, MAX, DEC).chance).toBe("99% chance")
		expect(AppraiseView.odds(1.0, MIN, MAX, DEC).chance).toBe("82% chance")
		expect(AppraiseView.odds(1.42, MIN, MAX, DEC).chance).toBe("47% chance")
		local top = AppraiseView.odds(1.97, MIN, MAX, DEC)
		expect(top.chance).toBe("2% chance")
		expect(top.warn).toBe(true)
		expect(string.find(top.detail, "Almost any", 1, true) ~= nil).toBe(true)
		expect(AppraiseView.odds(1.99, MIN, MAX, DEC).chance).toBe("<1% chance")
		expect(AppraiseView.odds(1.999, MIN, MAX, DEC).chance).toBe("<1% chance")
		local none = AppraiseView.odds(MAX, MIN, MAX, DEC)
		expect(none.chance).toBe("No chance")
		expect(none.warn).toBe(true)
		local low = AppraiseView.odds(1.0, MIN, MAX, DEC)
		expect(low.warn).toBe(false)
		expect(low.detail).toBe("to roll bigger than 1.00.")
	end)
	it("warns from the first size where a reroll is more likely to shrink it", function()
		-- 1.39: 60.5 of 120 steps above (50.4%); 1.40: 59.5 (49.6%).
		local fair = AppraiseView.odds(1.39, MIN, MAX, DEC)
		expect(fair.chance).toBe("50% chance")
		expect(fair.warn).toBe(false)
		local worse = AppraiseView.odds(1.4, MIN, MAX, DEC)
		expect(worse.chance).toBe("49% chance")
		expect(worse.warn).toBe(true)
		expect(realChance(1.39) > 0.5 and realChance(1.4) < 0.5).toBe(true)
	end)
end)

describe("AppraiseView.result", function()
	it("takes was -> now from the server's answer and says which way it went", function()
		local r = AppraiseView.result({ beforeSize = 2, afterSize = 1, incomeBefore = 100, incomeAfter = 51 })
		expect(r.incomeBefore).toBe(100)
		expect(r.incomeAfter).toBe(51)
		expect(r.better).toBe(false)
		local up = { beforeSize = 1, afterSize = 1.5, incomeBefore = 10, incomeAfter = 15 }
		expect(AppraiseView.result(up).better).toBe(true)
		local same = { beforeSize = 1.2, afterSize = 1.2, incomeBefore = 10, incomeAfter = 10 }
		expect(AppraiseView.result(same).better).toBeNil()
	end)
	it("words a refused reroll plainly", function()
		expect(AppraiseView.refusal("not enough cash")).toBe("Not enough cash for this reroll.")
		expect(AppraiseView.refusal("slime is busy")).toBe("This slime is busy right now.")
		expect(AppraiseView.refusal(nil)).toBe("The reroll didn't go through. Try again.")
	end)
	it("labels the tape every 0.2 from the smallest to the biggest size", function()
		local ticks = AppraiseView.ticks(MIN, MAX)
		expect(ticks[1]).toBe(MIN)
		expect(ticks[#ticks]).toBe(MAX)
		expect(#ticks).toBe(math.floor((MAX - MIN) / 0.2 + 0.5) + 1)
	end)
end)
