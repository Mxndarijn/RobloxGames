--!strict
local Rescue = require("../src/server/Rescue")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Rescue", function()
	it("rescues living characters below the kill plane only", function()
		expect(Rescue.shouldRescue(Rescue.KILL_PLANE_Y - 1, true)).toBe(true)
		expect(Rescue.shouldRescue(Rescue.KILL_PLANE_Y + 1, true)).toBe(false)
		expect(Rescue.shouldRescue(0, true)).toBe(false)
		expect(Rescue.shouldRescue(-500, false)).toBe(false)
	end)
	it("keeps the destroy height far below the kill plane", function()
		expect(Rescue.DESTROY_HEIGHT < Rescue.KILL_PLANE_Y - 500).toBe(true)
	end)
	it("prefers the plot spawn, then the hub spawn, then the fallback", function()
		expect(Rescue.target("plot", "hub", "origin")).toBe("plot")
		expect(Rescue.target(nil, "hub", "origin")).toBe("hub")
		expect(Rescue.target(nil, nil, "origin")).toBe("origin")
	end)
end)
