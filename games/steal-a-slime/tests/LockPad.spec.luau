--!strict
-- The lock pad round the LockButton (LockPad, CONTRACT.md §8.5): standing on it for STAND_SECONDS locks the base with
-- the Lock action's rules.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local LockPad = require("../src/server/LockPad")
local PlotPadGuard = require("../src/server/PlotPadGuard")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local PAD = Config.LOCK_PAD

local function owner()
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, nil, 1000)
	ServerFixtures.unlock(session)
	return world, session
end

describe("LockPad.inside", function()
	it("counts the ring and the button top, not a step outside or the floor above", function()
		expect(LockPad.inside(PAD.RADIUS, 3, 0)).toBe(true)
		expect(LockPad.inside(0, 6, 0)).toBe(true)
		expect(LockPad.inside(PAD.REACH + 0.1, 3, 0)).toBe(false)
		expect(LockPad.inside(0, PAD.HEIGHT + 0.1, 0)).toBe(false)
		expect(LockPad.inside(0 / 0, 3, 0)).toBe(false)
	end)
	it("the whole ring is inside the reach, and the reach inside the Lock prompt's range", function()
		expect(PAD.RADIUS + PAD.WIDTH / 2 <= PAD.REACH).toBe(true)
		expect(PAD.REACH < PlotPadGuard.range()).toBe(true)
	end)
end)

describe("LockPad.step", function()
	it("fires once the owner has stood on it for STAND_SECONDS", function()
		local _, session = owner()
		expect(LockPad.step(session, true, false, T0)).toBe(false)
		expect(LockPad.step(session, true, false, T0 + PAD.STAND_SECONDS / 2)).toBe(false)
		expect(LockPad.step(session, true, false, T0 + PAD.STAND_SECONDS)).toBe(true)
		expect(session.lockPadSince).toBeNil()
	end)
	it("stepping off starts the count again", function()
		local _, session = owner()
		LockPad.step(session, true, false, T0)
		LockPad.step(session, false, false, T0 + 0.5)
		expect(session.lockPadSince).toBeNil()
		LockPad.step(session, true, false, T0 + 0.6)
		expect(LockPad.step(session, true, false, T0 + 0.6 + PAD.STAND_SECONDS - 0.1)).toBe(false)
	end)
	it("does nothing while the base is locked", function()
		local _, session = owner()
		for i = 0, 30 do
			expect(LockPad.step(session, true, true, T0 + i * 0.1)).toBe(false)
		end
		expect(session.lockPadSince).toBeNil()
	end)
	it("the Lock it fires locks the owner's base like the prompt does", function()
		local world, session = owner()
		LockPad.step(session, true, false, T0)
		local now = T0 + PAD.STAND_SECONDS
		expect(LockPad.step(session, true, false, now)).toBe(true)
		expect(Actions.triggerPlotPrompt(world, 1, session.plotIndex, "Lock", now, {} :: any).ok).toBe(true)
		expect(session.lockUntil > now).toBe(true)
		expect(LockPad.step(session, true, now < session.lockUntil, now + 0.1)).toBe(false)
	end)
end)
