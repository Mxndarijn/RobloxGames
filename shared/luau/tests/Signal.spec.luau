--!strict
local Signal = require("../src/core/Signal")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

describe("Signal", function()
	it("calls handlers in connection order with the fired arguments", function()
		local signal = Signal.new()
		local log = {}
		signal:connect(function(a, b)
			table.insert(log, `1:{a}:{b}`)
		end)
		signal:connect(function(a, b)
			table.insert(log, `2:{a}:{b}`)
		end)
		signal:fire("x", 5)
		expect(log).toEqual({ "1:x:5", "2:x:5" })
	end)

	it("passes nil arguments through", function()
		local signal = Signal.new()
		local count = -1
		signal:connect(function(...)
			count = select("#", ...)
		end)
		signal:fire(nil, 2)
		expect(count).toBe(2)
	end)

	it("stops calling a handler after disconnect", function()
		local signal = Signal.new()
		local calls = 0
		local conn = signal:connect(function()
			calls += 1
		end)
		signal:fire()
		conn:disconnect()
		signal:fire()
		expect(calls).toBe(1)
		expect(conn.connected).toBe(false)
		expect(signal:connectionCount()).toBe(0)
	end)

	it("disconnect twice is harmless", function()
		local signal = Signal.new()
		local conn = signal:connect(function() end)
		signal:connect(function() end)
		conn:disconnect()
		conn:disconnect()
		expect(signal:connectionCount()).toBe(1)
	end)

	it("once runs a single time and disconnects itself", function()
		local signal = Signal.new()
		local seen = {}
		local conn = signal:once(function(v)
			table.insert(seen, v)
		end)
		signal:fire(1)
		signal:fire(2)
		expect(seen).toEqual({ 1 })
		expect(conn.connected).toBe(false)
	end)

	it("once can be disconnected before it fires", function()
		local signal = Signal.new()
		local calls = 0
		local conn = signal:once(function()
			calls += 1
		end)
		conn:disconnect()
		signal:fire()
		expect(calls).toBe(0)
	end)

	it("does not call handlers connected during a fire until the next fire", function()
		local signal = Signal.new()
		local late = 0
		signal:connect(function()
			signal:connect(function()
				late += 1
			end)
		end)
		signal:fire()
		expect(late).toBe(0)
		signal:fire()
		expect(late).toBe(1)
	end)

	it("skips a handler disconnected earlier in the same fire", function()
		local signal = Signal.new()
		local second: any
		local calls = 0
		signal:connect(function()
			second:disconnect()
		end)
		second = signal:connect(function()
			calls += 1
		end)
		signal:fire()
		expect(calls).toBe(0)
	end)

	it("destroy disconnects everything and later connects are inert", function()
		local signal = Signal.new()
		local calls = 0
		local conn = signal:connect(function()
			calls += 1
		end)
		signal:destroy()
		expect(conn.connected).toBe(false)
		local late = signal:connect(function()
			calls += 1
		end)
		expect(late.connected).toBe(false)
		signal:fire()
		expect(calls).toBe(0)
		expect(signal:connectionCount()).toBe(0)
	end)

	it("rejects a non-function handler", function()
		local signal = Signal.new()
		expect(function()
			signal:connect(5 :: any)
		end).toThrow()
	end)
end)
