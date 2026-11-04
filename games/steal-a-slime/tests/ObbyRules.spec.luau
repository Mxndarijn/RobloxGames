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

	it("the best run counts: a run's total starts the boost, and raises it only when it beats it", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0, obbyEarned = 0 }
		local share = ObbyRules.share(6)
		expect(share).toBeCloseTo(OBBY.BONUS / 6, 1e-12)
		-- ready: this run's first section starts the boost
		expect(ObbyRules.earn(data, 1000, share)).toBe(true)
		expect(ObbyRules.bonus(data, 1001)).toBeCloseTo(share, 1e-12)
		expect(data.obbyUntil).toBe(1000 + OBBY.BOOST_SECONDS)
		-- the same run's next sections raise it, and every raise runs BOOST_SECONDS from then
		for k = 2, 4 do
			expect(ObbyRules.earn(data, 1000 + k * 10, k * share)).toBe(true)
		end
		expect(ObbyRules.bonus(data, 1041)).toBeCloseTo(4 * share, 1e-12)
		expect(data.obbyUntil).toBe(1040 + OBBY.BOOST_SECONDS)
		-- another run while that boost runs: its first four sections add nothing (no farming by re-entering) ...
		for k = 1, 4 do
			expect(ObbyRules.earn(data, 1100 + k * 10, k * share)).toBe(false)
		end
		expect(data.obbyUntil).toBe(1040 + OBBY.BOOST_SECONDS)
		-- ... its fifth and sixth beat the running boost: a full clear always ends on the full bonus
		expect(ObbyRules.earn(data, 1150, 5 * share)).toBe(true)
		expect(ObbyRules.earn(data, 1160, 6 * share)).toBe(true)
		expect(ObbyRules.bonus(data, 1161)).toBe(OBBY.BONUS) -- six sixths land exactly on the full bonus
		expect(data.obbyUntil).toBe(1160 + OBBY.BOOST_SECONDS)
		expect(data.obbyReadyAt).toBe(1160 + OBBY.BOOST_SECONDS + OBBY.COOLDOWN_SECONDS)
		-- never past the full bonus, and a full boost can't be raised
		expect(ObbyRules.earn(data, 1170, 7 * share)).toBe(false)
		expect(data.obbyEarned).toBe(OBBY.BONUS)
		-- while it cools down nothing; once ready a run starts again from its own total
		expect(ObbyRules.earn(data, data.obbyUntil + 1, 6 * share)).toBe(false)
		expect(ObbyRules.earn(data, data.obbyReadyAt, share)).toBe(true)
		expect(data.obbyEarned).toBeCloseTo(share, 1e-12)
	end)

	it("the view's bonus is the running boost while boosted, else a full clear's", function()
		local data = { obbyUntil = 0, obbyReadyAt = 0, obbyEarned = 0 }
		expect(ObbyRules.view(data, 5).bonus).toBe(OBBY.BONUS)
		ObbyRules.earn(data, 10, ObbyRules.share(6))
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
