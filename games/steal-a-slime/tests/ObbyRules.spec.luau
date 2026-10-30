--!strict
local T = require("./TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Config = require("../src/shared/Config")
local ObbyRules = require("../src/shared/ObbyRules")

local OBBY = Config.OBBY

describe("ObbyRules", function()
	it("a first finish earns the boost, then the cooldown starts when the boost ends", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0 }
		expect(ObbyRules.phase(data, 1000)).toBe("ready")
		expect(ObbyRules.grant(data, 1000)).toBe(true)
		expect(data.obbyUntil).toBe(1000 + OBBY.BOOST_SECONDS)
		expect(data.obbyReadyAt).toBe(1000 + OBBY.BOOST_SECONDS + OBBY.COOLDOWN_SECONDS)
		expect(ObbyRules.bonus(data, 1001)).toBe(OBBY.BONUS)
		expect(ObbyRules.phase(data, 1000 + OBBY.BOOST_SECONDS)).toBe("cooling")
		expect(ObbyRules.bonus(data, 1000 + OBBY.BOOST_SECONDS)).toBeNil()
		expect(ObbyRules.phase(data, data.obbyReadyAt)).toBe("ready")
	end)

	it("a finish while boosted or cooling earns nothing and moves no timer", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0 }
		ObbyRules.grant(data, 1000)
		local untilAt, readyAt = data.obbyUntil, data.obbyReadyAt
		expect(ObbyRules.grant(data, 1100)).toBe(false)
		expect(ObbyRules.grant(data, untilAt + 10)).toBe(false)
		expect(data.obbyUntil).toBe(untilAt)
		expect(data.obbyReadyAt).toBe(readyAt)
	end)

	it("the view shows the end while boosted and the ready time until ready", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0 }
		expect(ObbyRules.view(data, 5).endsAt).toBeNil()
		expect(ObbyRules.view(data, 5).readyAt).toBeNil()
		ObbyRules.grant(data, 10)
		expect(ObbyRules.view(data, 11).endsAt).toBe(data.obbyUntil)
		expect(ObbyRules.view(data, data.obbyUntil + 1).endsAt).toBeNil()
		expect(ObbyRules.view(data, data.obbyUntil + 1).readyAt).toBe(data.obbyReadyAt)
	end)

	it("cleans junk saved timers", function()
		local t = ObbyRules.clean({ untilAt = "x", readyAt = -4 })
		expect(t.obbyUntil).toBe(0)
		expect(t.obbyReadyAt).toBe(0)
		t = ObbyRules.clean({ untilAt = 500, readyAt = 100 })
		expect(t.obbyReadyAt).toBe(500)
		t = ObbyRules.clean(nil)
		expect(t.obbyUntil).toBe(0)
	end)
end)
