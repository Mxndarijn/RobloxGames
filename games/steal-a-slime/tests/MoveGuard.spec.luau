--!strict
local Config = require("../src/shared/Config")
local MoveGuard = require("../src/shared/MoveGuard")
local MoveWatch = require("../src/server/MoveWatch")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TICK = 0.1
local WALK = Config.BASE_WALK_SPEED
local COIL = Config.SPEED_COIL_WALK_SPEED

local function at(x: number, y: number?, z: number?): MoveGuard.Vec
	return { X = x, Y = y or 3, Z = z or 0 }
end

-- Samples a straight walk at `speed` for `seconds`, returns how many samples were flagged.
local function walk(state: MoveGuard.State, t0: number, speed: number, seconds: number, cap: number): number
	local flagged = 0
	local steps = math.floor(seconds / TICK + 0.5)
	for i = 0, steps do
		local t = t0 + i * TICK
		if not MoveGuard.sample(state, at(speed * (t - t0)), t, cap).ok then
			flagged += 1
		end
	end
	return flagged
end

describe("MoveGuard", function()
	it("passes a player walking at the base speed", function()
		expect(walk(MoveGuard.newState(), 0, WALK, 30, WALK)).toBe(0)
	end)

	it("passes a coil owner at coil speed when the cap is the coil speed", function()
		expect(walk(MoveGuard.newState(), 0, COIL, 30, COIL)).toBe(0)
	end)

	it("flags coil speed against the base cap only past the headroom", function()
		-- 24 vs 16: 2.4 studs per tick against 16 x 0.1 x 1.5 + slack: inside the headroom by design
		expect(walk(MoveGuard.newState(), 0, COIL, 30, WALK)).toBe(0)
		-- a 120 studs/s runner is not
		expect(walk(MoveGuard.newState(), 0, 120, 5, WALK) > 0).toBe(true)
	end)

	it("flags a 100 stud teleport and records the excess", function()
		local state = MoveGuard.newState()
		MoveGuard.sample(state, at(0), 0, WALK)
		MoveGuard.sample(state, at(1), TICK, WALK)
		local result = MoveGuard.sample(state, at(101), 2 * TICK, WALK)
		expect(result.ok).toBe(false)
		expect(result.excess > 90).toBe(true)
		expect(state.violations).toBe(1)
		expect(state.maxExcess > 90).toBe(true)
	end)

	it("an allow-window suppresses the jump and re-baselines", function()
		local state = MoveGuard.newState()
		MoveGuard.sample(state, at(0), 0, WALK)
		MoveGuard.allow(state, 0.05, 1)
		expect(MoveGuard.sample(state, at(100), TICK, WALK).ok).toBe(true)
		-- moves inside the window are not judged either, baseline follows
		expect(MoveGuard.sample(state, at(300), 0.5, WALK).ok).toBe(true)
		-- after the window the new place is the baseline
		expect(MoveGuard.sample(state, at(301), 1.2, WALK).ok).toBe(true)
		-- and a teleport after the window is flagged again
		expect(MoveGuard.sample(state, at(400), 1.3, WALK).ok).toBe(false)
		expect(state.violations).toBe(1)
	end)

	it("a server hitch re-baselines instead of flagging", function()
		local state = MoveGuard.newState()
		MoveGuard.sample(state, at(0), 0, WALK)
		-- 5 s stall: the player walked 80 studs meanwhile
		expect(MoveGuard.sample(state, at(80), 5, WALK).ok).toBe(true)
		expect(MoveGuard.sample(state, at(81.6), 5.1, WALK).ok).toBe(true)
		expect(state.violations).toBe(0)
	end)

	it("a longer-than-tick gap within MAX_DT still gets proportional room", function()
		local state = MoveGuard.newState()
		MoveGuard.sample(state, at(0), 0, WALK)
		local dt = Config.MOVE_GUARD.MAX_DT * 0.9
		expect(MoveGuard.sample(state, at(WALK * dt), dt, WALK).ok).toBe(true)
	end)

	it("a new character resets the baseline", function()
		local book = MoveGuard.newBook()
		local first, second = {}, {}
		MoveGuard.step(book, 1, first, at(0), 0, WALK)
		MoveGuard.step(book, 1, first, at(1), TICK, WALK)
		-- respawn far away on the plot
		expect(MoveGuard.step(book, 1, second, at(500), 2 * TICK, WALK).ok).toBe(true)
		expect(MoveGuard.step(book, 1, second, at(900), 3 * TICK, WALK).ok).toBe(true) -- inside RESPAWN_ALLOW
		expect(book.players[1].violations).toBe(0)
		local later = 3 * TICK + Config.MOVE_GUARD.RESPAWN_ALLOW + 0.5
		MoveGuard.step(book, 1, second, at(900), later, WALK)
		expect(MoveGuard.step(book, 1, second, at(1000), later + TICK, WALK).ok).toBe(false)
	end)

	it("a fall from height is not flagged, a drop teleport is", function()
		local state = MoveGuard.newState()
		local y, v, t = 300, 0, 0
		MoveGuard.sample(state, at(0, y), t, WALK)
		local flagged = 0
		while y > 3 do
			v += 196.2 * TICK
			y = math.max(3, y - v * TICK)
			t += TICK
			if not MoveGuard.sample(state, at(0, y), t, WALK).ok then
				flagged += 1
			end
		end
		expect(flagged).toBe(0)
		expect(MoveGuard.sample(state, at(0, 3 - 200), t + TICK, WALK).ok).toBe(false)
	end)

	it("jumps and the tallest bounce pad are not flagged", function()
		local state = MoveGuard.newState()
		MoveGuard.sample(state, at(0, 3), 0, WALK)
		expect(MoveGuard.sample(state, at(0, 3 + 7.2), TICK, WALK).ok).toBe(true)
		MoveGuard.sample(state, at(0, 3), 1, WALK)
		-- Bounce Pad 25 studs: rise speed ~99 studs/s
		expect(MoveGuard.sample(state, at(0, 3 + 9.9), 1.1, WALK).ok).toBe(true)
	end)

	it("a carry slowdown (lower real speed) is fine", function()
		expect(walk(MoveGuard.newState(), 0, WALK * 0.5, 20, WALK)).toBe(0)
	end)

	it("ignores non-finite positions without poisoning the baseline", function()
		local state = MoveGuard.newState()
		MoveGuard.sample(state, at(0), 0, WALK)
		expect(MoveGuard.sample(state, at(0 / 0), TICK, WALK).ok).toBe(true)
		expect(MoveGuard.sample(state, at(1), 2 * TICK, WALK).ok).toBe(true)
	end)

	it("summaries are rate limited and name only players flagged since the last line", function()
		local book = MoveGuard.newBook()
		local c = {}
		MoveGuard.step(book, 7, c, at(0), 0, WALK)
		MoveGuard.step(book, 7, c, at(0), Config.MOVE_GUARD.RESPAWN_ALLOW + 1, WALK)
		local t = Config.MOVE_GUARD.RESPAWN_ALLOW + 1.1
		MoveGuard.step(book, 7, c, at(200), t, WALK)
		expect(MoveGuard.summary(book, t) ~= nil).toBe(true)
		MoveGuard.step(book, 7, c, at(400), t + TICK, WALK)
		expect(MoveGuard.summary(book, t + TICK)).toBe(nil) -- within LOG_INTERVAL
		expect(MoveGuard.summary(book, t + Config.MOVE_GUARD.LOG_INTERVAL + 1) ~= nil).toBe(true)
		expect(MoveGuard.summary(book, t + 3 * Config.MOVE_GUARD.LOG_INTERVAL)).toBe(nil) -- nothing new
	end)

	it("allowUser applies at the user's next sample", function()
		local book = MoveGuard.newBook()
		local c = {}
		MoveGuard.step(book, 2, c, at(0), 0, WALK)
		MoveGuard.step(book, 2, c, at(0), Config.MOVE_GUARD.RESPAWN_ALLOW + 1, WALK)
		MoveGuard.allowUser(book, 2, 1)
		expect(MoveGuard.step(book, 2, c, at(150), Config.MOVE_GUARD.RESPAWN_ALLOW + 1.1, WALK).ok).toBe(true)
	end)
end)

describe("MoveWatch wiring", function()
	it("is off by default and records no allow-window while off", function()
		expect(Config.FEATURES.MoveGuardLog).toBe(false)
		MoveWatch.allow(99, 5)
		expect(MoveWatch.book().pendingAllow[99]).toBe(nil)
	end)

	it("forget drops a user's state", function()
		MoveGuard.step(MoveWatch.book(), 98, {}, at(0), 0, WALK)
		MoveWatch.forget(98)
		expect(MoveWatch.book().players[98]).toBe(nil)
	end)
end)
