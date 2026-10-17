--!strict
-- v20 welcome-back: the join report (threshold, contents) and its State field (CONTRACT.md §19).
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local WelcomeBack = require("../src/shared/WelcomeBack")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local MIN = Config.WELCOME_BACK_MIN_SECONDS

local function join(away: number): any
	local world = ServerFixtures.world()
	local data = Fixtures.data({ Fixtures.slime("a", 2), Fixtures.slime("b", 1) }, 0)
	data.lastOnline = T0 - away
	data.padsUnlocked = Config.PADS_START
	local s = Sessions.join(world, 1, "P1", data, T0)
	assert(s, "session")
	return { world = world, session = s }
end

describe("WelcomeBack.report", function()
	it("is on by default with a multi-hour threshold", function()
		expect(Config.FEATURES.WelcomeBack).toBe(true)
		expect(MIN >= 3600).toBe(true)
	end)
	it("needs at least WELCOME_BACK_MIN_SECONDS away", function()
		expect(WelcomeBack.report(T0 - MIN + 1, T0, 50, 1)).toBeNil()
		local report = WelcomeBack.report(T0 - MIN, T0, 50, 2)
		assert(report, "report")
		expect(report.away).toBe(MIN)
		expect(report.cash).toBe(50)
		expect(report.grown).toBe(2)
	end)
	it("ignores new players, clock skew and garbage", function()
		expect(WelcomeBack.report(0, T0, 0, 0)).toBeNil()
		expect(WelcomeBack.report(T0 + 5, T0, 0, 0)).toBeNil()
		expect(WelcomeBack.report(0 / 0, T0, 0, 0)).toBeNil()
	end)
end)

describe("welcome-back on join", function()
	it("carries the offline cash and the slimes that grew", function()
		local j = join(MIN)
		local report = j.session.welcome
		assert(report, "welcome report")
		expect(report.away).toBe(MIN)
		expect(report.cash > 0).toBe(true)
		expect(report.grown).toBe(2)
	end)
	it("is absent below the threshold and for a fresh save", function()
		expect(join(MIN - 60).session.welcome).toBeNil()
		expect(join(0).session.welcome).toBeNil()
	end)
	it("rides in State.welcomeBack only when there is a report", function()
		local with = join(MIN)
		local state = Snapshot.build(with.world, with.session, T0)
		assert(state.welcomeBack, "state field")
		expect(state.welcomeBack.away).toBe(MIN)
		local without = join(60)
		expect(Snapshot.build(without.world, without.session, T0).welcomeBack).toBeNil()
	end)
end)
