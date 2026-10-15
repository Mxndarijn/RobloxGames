--!strict
-- HUD lock block, Lock button and Buy-pad button (src/ui/LockHud.luau).
local LockHud = require("../../src/ui/LockHud")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local MAX = 300

describe("LockHud.status", function()
	it("shows the remaining time while locked", function()
		local s = LockHud.status(1083, 1000, MAX)
		expect(s.level).toBe("locked")
		expect(s.title).toBe("🔒 LOCKED 1:23")
		expect(s.fraction).toBeCloseTo(83 / MAX)
	end)
	it("fills the bar from lockStartedAt when sent (CONTRACT §9.3)", function()
		expect(LockHud.status(1060, 1000, MAX, 1000).fraction).toBeCloseTo(1)
		expect(LockHud.status(1030, 1000, MAX, 970).fraction).toBeCloseTo(0.5)
		-- junk / missing start falls back to the cap
		expect(LockHud.status(1083, 1000, MAX, 0 / 0).fraction).toBeCloseTo(83 / MAX)
		expect(LockHud.status(1083, 1000, MAX, 2000).fraction).toBeCloseTo(83 / MAX)
	end)
	it("warns when the lock is about to end", function()
		local s = LockHud.status(1000 + LockHud.LOW_SECONDS, 1000, MAX)
		expect(s.level).toBe("low")
		expect(s.title).toBe("🔒 LOCKED 0:10")
	end)
	it("says UNLOCKED / vulnerable when open or unknown", function()
		local s = LockHud.status(900, 1000, MAX)
		expect(s.level).toBe("open")
		expect(s.title).toBe("🔓 UNLOCKED")
		expect(string.find(s.sub, "Vulnerable", 1, true) ~= nil).toBe(true)
		expect(s.fraction).toBe(0)
		expect(LockHud.status(nil, 1000, MAX).level).toBe("open")
	end)
end)

describe("LockHud.lockButton", function()
	it("shows cost and duration, and whether it's affordable", function()
		local b = LockHud.lockButton({ cash = 100, lockCost = 250, lockDuration = 70, lockUntil = 0 }, 1000, MAX)
		expect(b.text).toBe("🔒 Lock $250\n+70s")
		expect(b.enabled).toBe(false)
		expect(LockHud.lockButton({ cash = 300, lockCost = 250, lockDuration = 70, lockUntil = 0 }, 1000, MAX).enabled).toBe(
			true
		)
	end)
	it("says Extend while locked and maxed at the server cap", function()
		local extend = LockHud.lockButton({ cash = 1e6, lockCost = 10, lockDuration = 60, lockUntil = 1030 }, 1000, MAX)
		expect(extend.text).toBe("🔒 Extend $10\n+60s")
		local maxed =
			LockHud.lockButton({ cash = 1e6, lockCost = 10, lockDuration = 60, lockUntil = 1000 + MAX }, 1000, MAX)
		expect(maxed.maxed).toBe(true)
		expect(maxed.enabled).toBe(false)
		expect(maxed.text).toBe("🔒 Lock maxed\n5:00 cap")
	end)
end)

describe("LockHud.padButton", function()
	local function slimes(n: number): { any }
		local out = {}
		for i = 1, n do
			out[i] = { slime = { id = `s{i}`, tier = 1 } }
		end
		return out
	end
	it("reads 'Buy next pad N/M' with the price", function()
		local p =
			LockHud.padButton({ cash = 50, padsUnlocked = 4, padsMax = 8, nextPadCost = 1200, slimes = slimes(1) })
		expect(p.visible).toBe(true)
		expect(p.text).toBe("Buy next pad 5/8\n$1.2K")
		expect(p.enabled).toBe(false)
		expect(p.urgent).toBe(false)
		expect(p.hint).toBeNil()
	end)
	it("turns urgent with a hint when the plot is full", function()
		local p =
			LockHud.padButton({ cash = 5000, padsUnlocked = 4, padsMax = 8, nextPadCost = 1200, slimes = slimes(4) })
		expect(p.enabled).toBe(true)
		expect(p.urgent).toBe(true)
		expect(p.hint).toBe("Plot full! Buy pad 5/8 for $1.2K (or merge / sell)")
	end)
	it("hides once every pad is unlocked", function()
		local p = LockHud.padButton({ cash = 0, padsUnlocked = 8, padsMax = 8, nextPadCost = nil, slimes = slimes(8) })
		expect(p.visible).toBe(false)
		expect(p.hint).toBe("Plot full - merge or sell to make room")
		expect(LockHud.padButton({ padsUnlocked = 8, padsMax = 8, slimes = slimes(2) }).hint).toBeNil()
	end)
end)

describe("LockHud compact (phone HUD)", function()
	it("shortens the pad button text", function()
		local p = LockHud.padButton({ cash = 50, padsUnlocked = 4, padsMax = 8, nextPadCost = 1200, slimes = {} }, true)
		expect(p.text).toBe("Buy pad 5/8\n$1.2K")
	end)
	it("dailyButton: shown while claimable, hidden during the tutorial, short on phones", function()
		local daily = { available = true, streak = 3, amount = 400 }
		expect(LockHud.dailyButton(daily).visible).toBe(true)
		expect(LockHud.dailyButton(daily).text).toBe("Daily $400\nStreak 3")
		expect(LockHud.dailyButton(daily, true).visible).toBe(false)
		expect(LockHud.dailyButton(daily, false, true).text).toBe("Daily\n$400")
		expect(LockHud.dailyButton({ available = false, streak = 3, amount = 400 }).visible).toBe(false)
		expect(LockHud.dailyButton(nil).visible).toBe(false)
	end)
end)
