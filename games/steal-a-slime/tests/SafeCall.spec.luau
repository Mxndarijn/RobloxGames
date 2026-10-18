--!strict
-- SafeCall: the entry scripts' one pcall + log helper.
local SafeCall = require("../src/server/SafeCall")
local TestRunner = require("./TestRunner")

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
end)
