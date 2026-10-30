--!strict
-- SafeCall: one pcall + log helper for steps that may fail.
local SafeCall = require("../src/core/SafeCall")
local TestRunner = require("../testing/TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("SafeCall", function()
	it("returns true and every result of a call that works, logging nothing", function()
		local log = {}
		local safeCall = SafeCall.new(function(message)
			table.insert(log, message)
		end)
		local ok, a, b, c = safeCall("sum", function(x: number, y: number)
			return x + y, nil, "third"
		end, 2, 3)
		expect(ok).toBe(true)
		expect(a).toBe(5)
		expect(b).toBeNil()
		expect(c).toBe("third")
		expect(#log).toBe(0)
	end)
	it("logs one named line for an error and returns false plus the error", function()
		local log = {}
		local safeCall = SafeCall.new(function(message)
			table.insert(log, message)
		end)
		local ok, err = safeCall("MeshSwap.apply", function()
			error("no mesh", 0)
		end)
		expect(ok).toBe(false)
		expect(err).toBe("no mesh")
		expect(log).toEqual({ "[Server] MeshSwap.apply failed: no mesh" })
	end)
	it("puts the given tag in front of the log line", function()
		local log = {}
		local safeCall = SafeCall.new(function(message)
			table.insert(log, message)
		end, "[UI]")
		safeCall("panel", function()
			error("bad", 0)
		end)
		expect(log).toEqual({ "[UI] panel failed: bad" })
	end)
end)
