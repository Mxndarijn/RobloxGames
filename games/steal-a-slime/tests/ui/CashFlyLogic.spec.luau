--!strict
-- Cash fly-in (src/ui/CashFlyLogic.luau, ui/CashFly): coins for earned cash, the +/- rows above the number (max 3,
-- 2 s, joined within 1 s), the counted-up plate number, Auto Collect sums, and nothing for the first State or a rebirth.
local CashFlyLogic = require("../../src/ui/CashFlyLogic")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T = CashFlyLogic.TUNING

local function started(cash: number): CashFlyLogic.Model
	local m = CashFlyLogic.new()
	CashFlyLogic.observe(m, { cash = cash }, 0)
	return m
end

local function landAll(m: CashFlyLogic.Model, event: any, now: number)
	for _ = 1, event.coins do
		CashFlyLogic.land(m, event.id, now)
	end
end

describe("CashFlyLogic changes", function()
	it("shows nothing for the first State", function()
		local m = CashFlyLogic.new()
		expect(CashFlyLogic.observe(m, { cash = 5000 }, 0)).toBeNil()
		expect(#m.rows).toBe(0)
		expect(CashFlyLogic.shownCash(m)).toBe(5000)
	end)

	it("flies earned cash and shows the + row when the first coin lands", function()
		local m = started(1000)
		local event = CashFlyLogic.observe(m, { cash = 1500 }, 1) :: any
		expect(event.kind).toBe("flight")
		expect(event.amount).toBe(500)
		expect(event.coins >= T.COINS_MIN and event.coins <= T.COINS_MAX).toBe(true)
		expect(#m.rows).toBe(0)
		expect(CashFlyLogic.shownCash(m)).toBe(1000)
		CashFlyLogic.land(m, event.id, 1.5)
		expect(#m.rows).toBe(1)
		expect(m.rows[1].sign).toBe(1)
		expect(m.rows[1].amount).toBe(500)
	end)

	it("counts the plate number up coin by coin and ends on the real cash", function()
		local m = started(1000)
		local event = CashFlyLogic.observe(m, { cash = 1999 }, 1) :: any
		local last = CashFlyLogic.shownCash(m)
		for _ = 1, event.coins do
			CashFlyLogic.land(m, event.id, 1.5)
			local now = CashFlyLogic.shownCash(m)
			expect(now >= last).toBe(true)
			last = now
		end
		expect(CashFlyLogic.shownCash(m)).toBe(1999)
		expect(CashFlyLogic.counting(m)).toBe(false)
	end)

	it("shows spending as a - row at once", function()
		local m = started(5000)
		local event = CashFlyLogic.observe(m, { cash = 2500 }, 1) :: any
		expect(event.kind).toBe("spend")
		expect(event.amount).toBe(2500)
		expect(#m.rows).toBe(1)
		expect(m.rows[1].sign).toBe(-1)
		expect(CashFlyLogic.rowText(m.rows[1], function(n)
			return `${n}`
		end)).toBe("-$2500")
		expect(CashFlyLogic.shownCash(m)).toBe(2500)
	end)

	it("spending during a flight keeps the coins' share pending", function()
		local m = started(1000)
		local event = CashFlyLogic.observe(m, { cash = 2000 }, 1) :: any
		CashFlyLogic.observe(m, { cash = 1700 }, 1.1)
		expect(CashFlyLogic.shownCash(m)).toBe(700)
		landAll(m, event, 1.6)
		expect(CashFlyLogic.shownCash(m)).toBe(1700)
	end)

	it("never shows a negative number when spending below what is still landing", function()
		local m = started(0)
		CashFlyLogic.observe(m, { cash = 5000 }, 1)
		CashFlyLogic.observe(m, { cash = 1000 }, 1.1)
		expect(CashFlyLogic.shownCash(m)).toBe(0)
	end)

	it("shows nothing on a rebirth and drops the coins still flying", function()
		local m = started(1000)
		CashFlyLogic.observe(m, { cash = 9000, rebirths = 0 }, 1)
		local before = #m.rows
		expect(CashFlyLogic.observe(m, { cash = 0, rebirths = 1 }, 2)).toBeNil()
		expect(#m.rows).toBe(before)
		expect(CashFlyLogic.shownCash(m)).toBe(0)
		expect(CashFlyLogic.counting(m)).toBe(false)
	end)

	it("ignores a malformed cash value", function()
		local m = started(1000)
		expect(CashFlyLogic.observe(m, { cash = 0 / 0 }, 1)).toBeNil()
		expect(CashFlyLogic.shownCash(m)).toBe(1000)
	end)
end)

describe("CashFlyLogic rows", function()
	it("keeps at most 3 rows, dropping the oldest", function()
		local m = started(100000)
		local cash = 100000
		for i = 1, 5 do
			cash -= 100 * i
			CashFlyLogic.observe(m, { cash = cash }, i * 2 * T.JOIN_SECONDS) -- far apart: no joining
		end
		expect(#m.rows).toBe(T.ROWS)
		expect(m.rows[1].amount).toBe(300)
		expect(m.rows[3].amount).toBe(500)
	end)

	it("joins a same-sign change within a second, and not a later one or the other sign", function()
		local m = started(10000)
		CashFlyLogic.observe(m, { cash = 9000 }, 1)
		CashFlyLogic.observe(m, { cash = 8500 }, 1.5)
		expect(#m.rows).toBe(1)
		expect(m.rows[1].amount).toBe(1500)
		CashFlyLogic.observe(m, { cash = 8000 }, 1.5 + T.JOIN_SECONDS)
		expect(#m.rows).toBe(2)
		local event = CashFlyLogic.observe(m, { cash = 9000 }, 3) :: any
		CashFlyLogic.land(m, event.id, 3.1)
		expect(#m.rows).toBe(3)
		expect(m.rows[3].sign).toBe(1)
	end)

	it("removes a row 2 seconds after its last change", function()
		local m = started(10000)
		CashFlyLogic.observe(m, { cash = 9000 }, 1)
		expect(CashFlyLogic.tick(m, 1 + T.ROW_SECONDS - 0.05)).toBe(false)
		expect(#m.rows).toBe(1)
		expect(CashFlyLogic.tick(m, 1 + T.ROW_SECONDS)).toBe(true)
		expect(#m.rows).toBe(0)
	end)

	it("restarts a row's 2 seconds when a change joins it", function()
		local m = started(10000)
		CashFlyLogic.observe(m, { cash = 9000 }, 1)
		CashFlyLogic.observe(m, { cash = 8000 }, 1.8)
		CashFlyLogic.tick(m, 1 + T.ROW_SECONDS + 0.1)
		expect(#m.rows).toBe(1)
	end)
end)

describe("CashFlyLogic limits", function()
	it("flies at most 3 at once; past that the row shows at once with no coins", function()
		local m = started(0)
		local cash = 0
		local flights = 0
		for i = 1, 5 do
			cash += 1000
			local event = CashFlyLogic.observe(m, { cash = cash }, i * 0.01)
			if event then
				flights += 1
			end
		end
		expect(flights).toBe(T.FLIGHTS)
		expect(#m.rows).toBe(1) -- the 4th and 5th joined into one + row
		expect(m.rows[1].amount).toBe(2000)
	end)

	it("shows the row at once with reduced motion", function()
		local m = started(0)
		expect(CashFlyLogic.observe(m, { cash = 500, reducedMotion = true }, 1)).toBeNil()
		expect(#m.rows).toBe(1)
		expect(CashFlyLogic.shownCash(m)).toBe(500)
	end)

	it("settles a flight whose coins never land", function()
		local m = started(0)
		local event = CashFlyLogic.observe(m, { cash = 800 }, 1) :: any
		CashFlyLogic.tick(m, 1 + CashFlyLogic.flightSeconds(event.coins) + 1.1)
		expect(CashFlyLogic.counting(m)).toBe(false)
		expect(CashFlyLogic.shownCash(m)).toBe(800)
		expect(#m.rows).toBe(1)
	end)

	it("more cash sends more coins, between the min and max", function()
		expect(CashFlyLogic.coinCount(1)).toBe(T.COINS_MIN)
		expect(CashFlyLogic.coinCount(1e15)).toBe(T.COINS_MAX)
		expect(CashFlyLogic.coinCount(1e6) > CashFlyLogic.coinCount(100)).toBe(true)
	end)
end)

describe("CashFlyLogic auto collect", function()
	it("sums the steady income into one row every 5 seconds, with no coins", function()
		local m = started(0)
		local cash = 0
		for s = 1, 5 do
			cash += 120
			expect(CashFlyLogic.observe(m, { cash = cash, incomePerSec = 120, autoCollect = true }, s)).toBeNil()
		end
		expect(#m.rows).toBe(0)
		expect(CashFlyLogic.shownCash(m)).toBe(600)
		CashFlyLogic.tick(m, 1 + T.AUTO_SECONDS)
		expect(#m.rows).toBe(1)
		expect(m.rows[1].amount).toBe(600)
	end)

	it("still flies a reward bigger than a few seconds of income", function()
		local m = started(0)
		local event = CashFlyLogic.observe(m, { cash = 25000, incomePerSec = 120, autoCollect = true }, 1) :: any
		expect(event.kind).toBe("flight")
	end)

	it("without Auto Collect a small rise still flies", function()
		local m = started(0)
		local event = CashFlyLogic.observe(m, { cash = 100, incomePerSec = 120 }, 1) :: any
		expect(event.kind).toBe("flight")
	end)
end)
