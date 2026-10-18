--!strict
local RateLimiter = require("../src/core/RateLimiter")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

describe("RateLimiter", function()
	it("allows the first call and refuses calls inside the gap", function()
		local limiter = RateLimiter.new({ Buy = 1 })
		expect(limiter:allow(1, "Buy", 10)).toBe(true)
		expect(limiter:allow(1, "Buy", 10.5)).toBe(false)
		expect(limiter:allow(1, "Buy", 11)).toBe(true)
	end)

	it("does not reset the gap on a refused call", function()
		local limiter = RateLimiter.new({ Buy = 1 })
		limiter:allow(1, "Buy", 0)
		expect(limiter:allow(1, "Buy", 0.9)).toBe(false)
		expect(limiter:allow(1, "Buy", 1.0)).toBe(true)
	end)

	it("keeps keys apart", function()
		local limiter = RateLimiter.new({ Buy = 1 })
		expect(limiter:allow(1, "Buy", 0)).toBe(true)
		expect(limiter:allow(2, "Buy", 0)).toBe(true)
		expect(limiter:allow(1, "Buy", 0.5)).toBe(false)
	end)

	it("keeps actions apart", function()
		local limiter = RateLimiter.new({ Buy = 1, Sell = 1 })
		expect(limiter:allow(1, "Buy", 0)).toBe(true)
		expect(limiter:allow(1, "Sell", 0)).toBe(true)
	end)

	it("uses the default gap for unlisted actions", function()
		local limiter = RateLimiter.new({ Buy = 1 }, 0.25)
		expect(limiter:allow(1, "Other", 0)).toBe(true)
		expect(limiter:allow(1, "Other", 0.1)).toBe(false)
		expect(limiter:allow(1, "Other", 0.25)).toBe(true)
	end)

	it("does not limit unlisted actions without a default", function()
		local limiter = RateLimiter.new({ Buy = 1 })
		for i = 1, 5 do
			expect(limiter:allow(1, "Other", i * 0.001)).toBe(true)
		end
	end)

	it("does not limit actions with a zero gap", function()
		local limiter = RateLimiter.new({ Free = 0 }, 1)
		expect(limiter:allow(1, "Free", 0)).toBe(true)
		expect(limiter:allow(1, "Free", 0)).toBe(true)
	end)

	it("forget clears one key only", function()
		local limiter = RateLimiter.new({ Buy = 1 })
		limiter:allow(1, "Buy", 0)
		limiter:allow(2, "Buy", 0)
		limiter:forget(1)
		expect(limiter:allow(1, "Buy", 0.1)).toBe(true)
		expect(limiter:allow(2, "Buy", 0.1)).toBe(false)
	end)

	it("reset clears every key", function()
		local limiter = RateLimiter.new({ Buy = 1 })
		limiter:allow(1, "Buy", 0)
		limiter:allow(2, "Buy", 0)
		limiter:reset()
		expect(limiter:allow(1, "Buy", 0.1)).toBe(true)
		expect(limiter:allow(2, "Buy", 0.1)).toBe(true)
	end)

	it("copies the gap table so later edits do not change it", function()
		local gaps = { Buy = 1 }
		local limiter = RateLimiter.new(gaps)
		gaps.Buy = 0
		limiter:allow(1, "Buy", 0)
		expect(limiter:allow(1, "Buy", 0.5)).toBe(false)
	end)

	it("rejects bad setup", function()
		expect(function()
			RateLimiter.new({ Buy = "fast" :: any })
		end).toThrow()
		expect(function()
			RateLimiter.new({}, 0 / 0)
		end).toThrow()
	end)
end)
