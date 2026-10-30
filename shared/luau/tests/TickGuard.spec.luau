--!strict
-- A frame or countdown loop runs every component tick through TickGuard: a thrown tick is caught, logged once
-- per component, and the others keep running.
local TestRunner = require("../testing/TestRunner")
local TickGuard = require("../src/core/TickGuard")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("TickGuard", function()
	it("catches a failing tick, logs it once per component and lets the next tick run", function()
		local logs = 0
		local guard = TickGuard.new(function()
			logs += 1
		end)
		local ran = 0
		for _ = 1, 5 do
			expect(guard("hud", function()
				error("boom")
			end)).toBe(false)
			guard("inventory", function()
				ran += 1
			end)
		end
		expect(logs).toBe(1)
		expect(ran).toBe(5)
		guard("codes", function()
			error("other")
		end)
		expect(logs).toBe(2)
	end)
end)
