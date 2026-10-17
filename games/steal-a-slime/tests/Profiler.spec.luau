--!strict
local Config = require("../src/shared/Config")
local Profiler = require("../src/server/Profiler")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function make(enabled: boolean, overrides: Profiler.Overrides?)
	local now = { t = 0 }
	local p = Profiler.new(enabled, function()
		return now.t
	end, overrides)
	return p, now
end

describe("Profiler", function()
	it("is off by default and the flag is declared", function()
		expect(Config.FEATURES.ServerProfiler).toBe(false)
		expect(Profiler.new().enabled).toBe(false)
	end)

	it("disabled is a no-op: nothing recorded, fn still runs and returns", function()
		local p = make(false)
		local a, b = Profiler.time(p, "X", function(x: number, y: number)
			return x + y, "ok"
		end, 1, 2)
		expect(a).toBe(3)
		expect(b).toBe("ok")
		Profiler.record(p, "X", 5)
		Profiler.count(p, "Request")
		expect(Profiler.stats(p, "X")).toBe(nil)
		expect(next(p.counters)).toBe(nil)
		expect(#p.order).toBe(0)
		local line, warnings = Profiler.flush(p)
		expect(line).toBe(nil)
		expect(warnings).toBe(nil)
	end)

	it("rolling average, max and nearest-rank p95", function()
		local p = make(true, { window = 100 })
		for i = 1, 100 do
			Profiler.record(p, "S", i)
		end
		local st = Profiler.stats(p, "S") :: Profiler.Stats
		expect(st.count).toBe(100)
		expect(st.avg).toBe(50.5)
		expect(st.p95).toBe(95)
		expect(st.max).toBe(100)
	end)

	it("keeps only the last window samples", function()
		local p = make(true, { window = 4 })
		for i = 1, 10 do
			Profiler.record(p, "S", i)
		end
		local st = Profiler.stats(p, "S") :: Profiler.Stats
		expect(st.count).toBe(4)
		expect(st.avg).toBe(8.5) -- 7, 8, 9, 10
		expect(st.max).toBe(10)
	end)

	it("time measures the clock delta in ms", function()
		local p, now = make(true)
		Profiler.time(p, "T", function()
			now.t += 0.002
		end)
		local st = Profiler.stats(p, "T") :: Profiler.Stats
		expect(math.abs(st.avg - 2) < 1e-9).toBeTruthy()
	end)

	it("lists systems over budget, worst ratio first", function()
		local p = make(true, { budgets = { A = 1, B = 1, C = 10 } })
		Profiler.record(p, "A", 2)
		Profiler.record(p, "B", 5)
		Profiler.record(p, "C", 3)
		Profiler.record(p, "D", 99) -- no budget
		local over = Profiler.overBudget(p)
		expect(#over).toBe(2)
		expect(over[1].name).toBe("B")
		expect(over[2].name).toBe("A")
	end)

	it("flush logs once per interval with counter rates, warnings and a counter reset", function()
		local p, now = make(true, { interval = 10, budgets = { S = 1 } })
		Profiler.record(p, "S", 3)
		Profiler.count(p, "Request", 20)
		now.t = 5
		expect(Profiler.flush(p)).toBe(nil)
		now.t = 10
		local line, warnings = Profiler.flush(p, function()
			return { instances = 1234 }
		end)
		expect(line).toBe("[Profiler] | S 3.00/3.00ms | instances=1234 | Request=2.0/s")
		expect(#(warnings :: { string })).toBe(1)
		expect(string.find((warnings :: { string })[1], "S p95 3.00ms over budget 1.00ms", 1, true) ~= nil).toBeTruthy()
		expect(next(p.counters)).toBe(nil)
		now.t = 12
		expect(Profiler.flush(p)).toBe(nil)
	end)
end)
