--!strict
-- The plot lock blocks non-owners both ways: no way in, no way out while it lasts. It never moves anyone.
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("PlotLockGuard: locked both ways", function()
	it("has no leaver pass and moves nobody: no set-down out of the doorway", function()
		expect((PlotLockGuard :: any).isLeaver).toBeNil()
		expect((PlotLockGuard :: any).LEAVER_GROUP).toBeNil()
		expect((PlotLockGuard :: any).wedged).toBeNil()
		expect((PlotLockGuard :: any).doorwayExit).toBeNil()
	end)
	it("names one lock and one owner group per plot", function()
		expect(PlotLockGuard.lockGroup(3)).toBe("PlotLock_3")
		expect(PlotLockGuard.ownerGroup(3)).toBe("PlotOwner_3")
	end)
end)

describe("PlotLockGuard.intruder", function()
	it("calls a character that entered after the lock began an intruder", function()
		expect(PlotLockGuard.intruder(105, 100)).toBe(true)
		expect(PlotLockGuard.intruder(95, 100)).toBe(false)
		-- pushed in by the stopper shutting on them in the doorway
		expect(PlotLockGuard.intruder(100 + PlotLockGuard.SHUT_GRACE, 100)).toBe(false)
	end)
end)
