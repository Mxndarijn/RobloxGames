--!strict
-- selftest.sh copies this into tests/ of a temp copy: logic.sh must FAIL.
local Economy = require("../src/shared/Economy")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("pr-gate selftest (deliberately broken)", function()
	it("a wrong assertion fails the logic gate", function()
		expect(Economy ~= nil).toBe(true)
		expect(1 + 1).toBe(3)
	end)
end)
