--!strict
local Spring = require("../src/core/Spring")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60

-- Steps `s` towards `target` for `seconds`; returns the values.
local function run(s: Spring.Spring, target: number, seconds: number): { number }
	local out = {}
	for _ = 1, math.floor(seconds / DT) do
		table.insert(out, Spring.step(s, DT, target))
	end
	return out
end

local function peak(list: { number }): number
	local m = -math.huge
	for _, v in list do
		m = math.max(m, v)
	end
	return m
end

describe("Spring", function()
	it("settles on the target", function()
		local s = Spring.new(3, 0.5, 0, 0)
		local ys = run(s, 1, 4)
		expect(ys[#ys]).toBeCloseTo(1, 3)
	end)

	it("overshoots and wobbles out when under-damped, never with zeta >= 1", function()
		expect(peak(run(Spring.new(3, 0.25, 0, 0), 1, 3)) > 1.2).toBe(true)
		expect(peak(run(Spring.new(3, 1, 0, 0), 1, 3)) <= 1 + 1e-6).toBe(true)
	end)

	it("moves the wrong way first with a negative response (anticipation)", function()
		local s = Spring.new(2, 0.6, -1, 0)
		local ys = run(s, 1, 0.1)
		local low = math.huge
		for _, y in ys do
			low = math.min(low, y)
		end
		expect(low < 0).toBe(true)
	end)

	it("responds faster with a higher frequency", function()
		local slow = run(Spring.new(1, 1, 0, 0), 1, 0.3)
		local fast = run(Spring.new(5, 1, 0, 0), 1, 0.3)
		expect(fast[#fast] > slow[#slow]).toBe(true)
	end)

	it("stays stable through long frames", function()
		local s = Spring.new(8, 0.1, 2, 0)
		for _ = 1, 50 do
			Spring.step(s, 0.5, 1)
		end
		expect(math.abs(s.y) < 10).toBe(true)
	end)

	it("a kick rings out and comes back to rest", function()
		local s = Spring.new(3, 0.3, 0, 0)
		Spring.kick(s, 5)
		local ys = run(s, 0, 4)
		expect(peak(ys) > 0.1).toBe(true)
		expect(math.abs(ys[#ys]) < 1e-3).toBe(true)
	end)

	it("ignores a zero or negative dt", function()
		local s = Spring.new(3, 0.3, 0, 2)
		expect(Spring.step(s, 0, 5)).toBe(2)
		expect(Spring.step(s, -1, 5)).toBe(2)
	end)

	it("reset puts it at rest on a value", function()
		local s = Spring.new(3, 0.3, 0, 0)
		run(s, 1, 0.2)
		Spring.reset(s, 4)
		expect(s.y).toBe(4)
		expect(s.v).toBe(0)
		expect(Spring.step(s, DT, 4)).toBeCloseTo(4, 6)
	end)
end)
