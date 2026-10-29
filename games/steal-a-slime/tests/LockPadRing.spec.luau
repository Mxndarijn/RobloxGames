--!strict
-- What the lock pad ring shows (src/shared/LockPadRing.luau, CONTRACT.md §8.5): dark on a free plot, green while the
-- owner can lock, the charge sweep, the lock counting down.
local Config = require("../src/shared/Config")
local LockPadRing = require("../src/shared/LockPadRing")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = 1000
local PAD = Config.LOCK_PAD

describe("LockPadRing.ring", function()
	local n = PAD.SEGMENTS
	it("is dark on a free plot", function()
		expect(LockPadRing.ring(false, T0, 0, 0, nil)).toEqual({ mode = "idle", lit = 0 })
		expect(LockPadRing.ring(false, T0, T0 + 60, T0, T0)).toEqual({ mode = "idle", lit = 0 })
	end)
	it("is green all round while the owner can lock", function()
		expect(LockPadRing.ring(true, T0, 0, 0, nil)).toEqual({ mode = "ready", lit = n })
		expect(LockPadRing.ring(true, T0 + 60, T0, T0 - 120, nil)).toEqual({ mode = "ready", lit = n })
	end)
	it("sweeps round while the owner stands on it", function()
		expect(LockPadRing.ring(true, T0, 0, 0, T0).lit).toBe(0)
		expect(LockPadRing.ring(true, T0 + PAD.STAND_SECONDS / 2, 0, 0, T0)).toEqual({ mode = "charge", lit = n / 2 })
		expect(LockPadRing.ring(true, T0 + PAD.STAND_SECONDS * 2, 0, 0, T0).lit).toBe(n)
	end)
	it("counts the lock down, never below one segment, then turns green again", function()
		expect(LockPadRing.ring(true, T0, T0 + 120, T0, nil)).toEqual({ mode = "locked", lit = n })
		expect(LockPadRing.ring(true, T0 + 60, T0 + 120, T0, nil).lit).toBe(n / 2)
		expect(LockPadRing.ring(true, T0 + 119.9, T0 + 120, T0, nil).lit).toBe(1)
		expect(LockPadRing.ring(true, T0 + 120, T0 + 120, T0, nil)).toEqual({ mode = "ready", lit = n })
	end)
end)
