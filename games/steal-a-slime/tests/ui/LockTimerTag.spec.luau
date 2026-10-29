--!strict
-- LockTimerTag (src/ui/LockTimerTag.luau): everyone, the owner too, sees how long a locked base stays locked, through glass only.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local LockTimerTag = UiHarness.ui("LockTimerTag")

local ME, OWNER, T0 = 7, 42, 1000

describe("LockTimerTag", function()
	it("shows on every locked base, your own included", function()
		expect(LockTimerTag.shows(OWNER, T0 + 60, T0)).toBe(true)
		expect(LockTimerTag.shows(ME, T0 + 60, T0)).toBe(true) -- your own base
		expect(LockTimerTag.shows(OWNER, T0, T0)).toBe(false) -- the lock ran out
		expect(LockTimerTag.shows(OWNER, nil, T0)).toBe(false)
		expect(LockTimerTag.shows(0, T0 + 60, T0)).toBe(false) -- a free plot
		expect(LockTimerTag.shows(nil, T0 + 60, T0)).toBe(false)
	end)
	it("says how long is left", function()
		expect(LockTimerTag.text(102)).toBe("LOCKED 1:42")
		expect(LockTimerTag.text(0.2)).toBe("LOCKED 0:01")
	end)
	it("glass doesn't hide it, solid parts do", function()
		expect(LockTimerTag.seeThrough(0.6)).toBe(true) -- jar glass
		expect(LockTimerTag.seeThrough(0.55)).toBe(true) -- drop tube glass
		expect(LockTimerTag.seeThrough(1)).toBe(true)
		expect(LockTimerTag.seeThrough(0)).toBe(false)
		expect(LockTimerTag.seeThrough(0.1)).toBe(false)
	end)
end)
