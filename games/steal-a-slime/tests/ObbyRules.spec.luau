--!strict
local T = require("./TestRunner")
local describe, it, expect = T.describe, T.it, T.expect
local Config = require("../src/shared/Config")
local ObbyRules = require("../src/shared/ObbyRules")

local OBBY = Config.OBBY

describe("ObbyRules", function()
	it("a first finish earns the boost, then the cooldown starts when the boost ends", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0, obbyEarned = 0 }
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
		local data = { obbyUntil = 0, obbyReadyAt = 0, obbyEarned = 0 }
		ObbyRules.grant(data, 1000)
		local untilAt, readyAt = data.obbyUntil, data.obbyReadyAt
		expect(ObbyRules.grant(data, 1100)).toBe(false)
		expect(ObbyRules.grant(data, untilAt + 10)).toBe(false)
		expect(data.obbyUntil).toBe(untilAt)
		expect(data.obbyReadyAt).toBe(readyAt)
	end)

	it("the view shows the end while boosted and the ready time until ready", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0, obbyEarned = 0 }
		expect(ObbyRules.view(data, 5).endsAt).toBeNil()
		expect(ObbyRules.view(data, 5).readyAt).toBeNil()
		ObbyRules.grant(data, 10)
		expect(ObbyRules.view(data, 11).endsAt).toBe(data.obbyUntil)
		expect(ObbyRules.view(data, data.obbyUntil + 1).endsAt).toBeNil()
		expect(ObbyRules.view(data, data.obbyUntil + 1).readyAt).toBe(data.obbyReadyAt)
	end)

	it("each section adds a share; the first needs the boost ready, the rest continue this run's boost", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0, obbyEarned = 0 }
		local share = ObbyRules.share(6)
		expect(share).toBeCloseTo(OBBY.BONUS / 6, 1e-12)
		expect(ObbyRules.earn(data, 1000, share, false)).toBe(true)
		expect(ObbyRules.bonus(data, 1001)).toBeCloseTo(share, 1e-12)
		expect(data.obbyUntil).toBe(1000 + OBBY.BOOST_SECONDS)
		-- another run while boosted: no new start
		expect(ObbyRules.earn(data, 1010, share, false)).toBe(false)
		-- this run's next sections: the boost grows and runs BOOST_SECONDS from the latest
		for k = 2, 6 do
			expect(ObbyRules.earn(data, 1000 + k * 10, share, true)).toBe(true)
		end
		expect(ObbyRules.bonus(data, 1061)).toBe(OBBY.BONUS) -- six sixths land exactly on the full bonus
		expect(data.obbyUntil).toBe(1060 + OBBY.BOOST_SECONDS)
		expect(data.obbyReadyAt).toBe(1060 + OBBY.BOOST_SECONDS + OBBY.COOLDOWN_SECONDS)
		-- never past the full bonus
		ObbyRules.earn(data, 1070, share, true)
		expect(data.obbyEarned).toBe(OBBY.BONUS)
		-- continuing after the boost ran out is a new start, and that needs ready
		expect(ObbyRules.earn(data, data.obbyUntil + 1, share, true)).toBe(false)
		expect(ObbyRules.earn(data, data.obbyReadyAt, share, true)).toBe(true)
		expect(data.obbyEarned).toBeCloseTo(share, 1e-12)
	end)

	it("the view's bonus is the running boost while boosted, else a full clear's", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0, obbyEarned = 0 }
		expect(ObbyRules.view(data, 5).bonus).toBe(OBBY.BONUS)
		ObbyRules.earn(data, 10, ObbyRules.share(6), false)
		expect(ObbyRules.view(data, 11).bonus).toBeCloseTo(OBBY.BONUS / 6, 1e-12)
		expect(ObbyRules.view(data, data.obbyUntil).bonus).toBe(OBBY.BONUS)
	end)

	it("cleans junk saved timers", function()
		local t = ObbyRules.clean({ untilAt = "x", readyAt = -4 })
		expect(t.obbyUntil).toBe(0)
		expect(t.obbyReadyAt).toBe(0)
		t = ObbyRules.clean({ untilAt = 500, readyAt = 100 })
		expect(t.obbyReadyAt).toBe(500)
		t = ObbyRules.clean(nil)
		expect(t.obbyUntil).toBe(0)
		expect(t.obbyEarned).toBe(0)
		expect(ObbyRules.clean({ untilAt = 500, readyAt = 800, bonus = 0.5 }).obbyEarned).toBe(0.5)
		expect(ObbyRules.clean({ untilAt = 500, readyAt = 800, bonus = 9 }).obbyEarned).toBe(OBBY.BONUS)
		-- a boost saved without its bonus counts as a full clear
		expect(ObbyRules.clean({ untilAt = 500, readyAt = 800 }).obbyEarned).toBe(OBBY.BONUS)
	end)
end)
