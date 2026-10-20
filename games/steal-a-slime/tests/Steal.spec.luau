--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local Steal = require("../src/shared/Steal")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function ctx(overrides: { [string]: any }?): Steal.StealContext
	local c: Steal.StealContext = {
		thiefId = 1,
		ownerId = 2,
		now = 100,
		lockUntil = 50,
		thiefCarrying = false,
		slimeBusy = false,
		distance = 5,
	}
	for k, v in overrides or {} do
		(c :: any)[k] = v
	end
	return c
end

describe("Steal lock", function()
	it("join lock lasts JOIN_LOCK_SECONDS", function()
		local untilT = Steal.joinLockUntil(1000)
		expect(Steal.isLocked(untilT, 1000 + Config.JOIN_LOCK_SECONDS - 0.1)).toBe(true)
		expect(Steal.isLocked(untilT, 1000 + Config.JOIN_LOCK_SECONDS)).toBe(false)
	end)
	it("lock duration grows with rebirths", function()
		expect(Steal.lockDuration(0)).toBe(Config.LOCK_SECONDS)
		expect(Steal.lockDuration(3)).toBe(Config.LOCK_SECONDS + 3 * Config.LOCK_SECONDS_PER_REBIRTH)
		expect(Steal.lockDuration(-1)).toBe(Config.LOCK_SECONDS)
	end)
	it("lock duration is capped at LOCK_MAX_REMAINING (3 min) however many rebirths", function()
		expect(Config.LOCK_MAX_REMAINING).toBe(180)
		expect(Steal.lockDuration(1000)).toBe(Config.LOCK_MAX_REMAINING)
		local data = Fixtures.data(nil, 1e6)
		data.rebirths = 1000
		local ok, untilT = Steal.buyLock(data, 0, 500, 0)
		expect(ok).toBe(true)
		expect(untilT).toBe(500 + Config.LOCK_MAX_REMAINING)
	end)
	it("buying a lock charges cash and starts from now when expired", function()
		local data = Fixtures.data(nil, 1000)
		local ok, untilT, cost = Steal.buyLock(data, 0, 500, 0)
		expect(ok).toBe(true)
		expect(untilT).toBe(500 + Config.LOCK_SECONDS)
		expect(cost).toBe(Config.LOCK_BASE_COST)
		expect(data.cash).toBe(1000 - Config.LOCK_BASE_COST)
	end)
	it("extends a running lock, capped at LOCK_MAX_REMAINING", function()
		local data = Fixtures.data(nil, 1e6)
		local _, untilT = Steal.buyLock(data, 530, 500, 0) -- 30 s left
		expect(untilT).toBe(500 + 30 + Config.LOCK_SECONDS)
		local lockUntil = untilT
		for _ = 1, 10 do
			local _, u = Steal.buyLock(data, lockUntil, 500, 0)
			lockUntil = u
		end
		expect(lockUntil).toBe(500 + Config.LOCK_MAX_REMAINING)
		local ok, _, reason = Steal.buyLock(data, lockUntil, 500, 0)
		expect(ok).toBe(false)
		expect(reason).toBe("lock is already at max")
	end)
	it("refuses when you can't afford it, without changes", function()
		local data = Fixtures.data(nil, 5)
		local ok, untilT, reason = Steal.buyLock(data, 0, 500, 100)
		expect(ok).toBe(false)
		expect(untilT).toBe(0)
		expect(reason).toBe("not enough cash")
		expect(data.cash).toBe(5)
	end)
end)

describe("Steal.canSteal", function()
	it("allows stealing from an unlocked plot in reach", function()
		expect((Steal.canSteal(ctx()))).toBe(true)
	end)
	it("blocks own slimes, locked bases, busy carriers and distance", function()
		expect(select(2, Steal.canSteal(ctx({ thiefId = 2 })))).toBe("that's your own slime")
		expect(select(2, Steal.canSteal(ctx({ lockUntil = 101 })))).toBe("base is locked")
		expect(select(2, Steal.canSteal(ctx({ thiefCarrying = true })))).toBe("already carrying a slime")
		expect(select(2, Steal.canSteal(ctx({ slimeBusy = true })))).toBe("someone is already carrying it")
		expect(select(2, Steal.canSteal(ctx({ distance = Config.STEAL_REACH + 1 })))).toBe("too far away")
		expect((Steal.canSteal(ctx({ distance = 0 / 0 })))).toBe(false)
	end)
end)

describe("Steal carry", function()
	it("rarer slimes escape sooner (15-25 s)", function()
		expect(Steal.escapeTime(1)).toBe(25)
		expect(Steal.escapeTime(Config.MAX_TIER)).toBe(15)
		for t = 2, Config.MAX_TIER do
			expect(Steal.escapeTime(t) <= Steal.escapeTime(t - 1)).toBeTruthy()
		end
	end)
	it("wild carries never escape and have no timer", function()
		local c = Steal.newCarry("wild", 6, 0)
		expect(c.escapeAt).toBeNil()
		expect(Steal.shouldEscape(c, 9999, 0)).toBe(false)
		expect(Steal.wriggleChance(c, 9999)).toBe(0)
	end)
	it("rarer slimes slow you more", function()
		local slowCommon = Steal.carrySlow(Steal.newCarry("wild", 1, 0), 0)
		local slowMythic = Steal.carrySlow(Steal.newCarry("wild", 6, 0), 0)
		expect(slowMythic > slowCommon).toBeTruthy()
		expect(Steal.walkSpeed(nil, 0)).toBe(Config.BASE_WALK_SPEED)
		expect(Steal.walkSpeed(Steal.newCarry("wild", 1, 0), 0)).toBeCloseTo(16 * 0.95)
	end)
	it("stolen slimes slow you progressively, capped", function()
		local c = Steal.newCarry("stolen", 3, 0)
		local early = Steal.carrySlow(c, 0)
		local late = Steal.carrySlow(c, Steal.escapeTime(3))
		expect(early).toBeCloseTo(Config.RARITIES[3].carrySlow)
		expect(late).toBeCloseTo(Config.RARITIES[3].carrySlow + Config.STOLEN_EXTRA_SLOW)
		local m = Steal.newCarry("stolen", 6, 0)
		expect(Steal.carrySlow(m, 100) <= Config.MAX_CARRY_SLOW).toBeTruthy()
	end)
	it("wriggle chance starts at 0 and grows to WRIGGLE_MAX_CHANCE", function()
		local c = Steal.newCarry("stolen", 1, 0)
		expect(Steal.wriggleChance(c, 0)).toBe(0)
		local mid = Steal.wriggleChance(c, 12.5)
		expect(mid).toBeCloseTo(Config.WRIGGLE_MAX_CHANCE * 0.25)
		expect(Steal.wriggleChance(c, 25)).toBeCloseTo(Config.WRIGGLE_MAX_CHANCE)
	end)
	it("escapes on a lucky roll or when the timer runs out", function()
		local c = Steal.newCarry("stolen", 1, 0)
		expect(Steal.shouldEscape(c, 1, 0.5)).toBe(false)
		expect(Steal.shouldEscape(c, 20, 0.0001)).toBe(true)
		expect(Steal.shouldEscape(c, 20, 0.99)).toBe(false)
		expect(Steal.shouldEscape(c, 25, 0.99)).toBe(true)
	end)
	it("simulated thieves escape within the timer at a sensible rate", function()
		-- Seeded walk: thieves who need the full timer always lose the slime;
		-- some slimes wriggle free early.
		local rng = require("../src/shared/Rng").new(4)
		local early = 0
		for _ = 1, 500 do
			local c = Steal.newCarry("stolen", 3, 0)
			local t = 0
			while not Steal.shouldEscape(c, t, rng:float()) do
				t += 1
			end
			expect(t <= Steal.escapeTime(3)).toBeTruthy()
			if t < Steal.escapeTime(3) then
				early += 1
			end
		end
		expect(early > 50 and early < 450).toBeTruthy()
	end)
end)

describe("Steal.canSlap", function()
	local function slap(overrides: { [string]: any }?): Steal.SlapContext
		local c: Steal.SlapContext = {
			now = 10,
			lastSlapAt = 0,
			distance = 4,
			slapperId = 1,
			targetId = 2,
			targetCarry = Steal.newCarry("stolen", 1, 5),
		}
		for k, v in overrides or {} do
			(c :: any)[k] = v
		end
		return c
	end
	it("lets you slap a nearby thief", function()
		expect((Steal.canSlap(slap()))).toBe(true)
	end)
	it("blocks self, cooldown, distance and non-thieves", function()
		expect((Steal.canSlap(slap({ targetId = 1 })))).toBe(false)
		expect((Steal.canSlap(slap({ lastSlapAt = 9.5 })))).toBe(false)
		expect((Steal.canSlap(slap({ distance = 50 })))).toBe(false)
		expect((Steal.canSlap(slap({ targetCarry = Steal.newCarry("wild", 1, 0) })))).toBe(false)
		expect((Steal.canSlap(slap({ targetCarry = false })))).toBe(false)
	end)
end)

describe("Steal.complete", function()
	it("moves the slime to a free pad on the thief's plot", function()
		local victim = Fixtures.data({ Fixtures.slime("a", 4), Fixtures.slime("b") })
		local thief = Fixtures.data({ Fixtures.slime("t") })
		local ok, s = Steal.complete(victim, thief, "a")
		expect(ok).toBe(true)
		assert(type(s) == "table", "precondition")
		expect(s.pad).toBe(2)
		expect(PlayerData.findSlime(victim, "a")).toBeNil()
		expect(PlayerData.findSlime(thief, "a")).toBeTruthy()
		expect(thief.totalStolen).toBe(1)
	end)
	it("fails without changes when the thief's plot is full", function()
		local victim = Fixtures.data({ Fixtures.slime("a") })
		local thief = PlayerData.new()
		for i = 1, thief.padsUnlocked do
			PlayerData.addSlime(thief, Fixtures.slime(`t{i}`))
		end
		local ok, reason = Steal.complete(victim, thief, "a")
		expect(ok).toBe(false)
		expect(reason).toBe("plot full")
		expect(PlayerData.findSlime(victim, "a")).toBeTruthy()
	end)
	it("fails if the slime is already gone", function()
		expect((Steal.complete(Fixtures.data(), Fixtures.data(), "a"))).toBe(false)
	end)
	it("clears the victim's favourite", function()
		local victim = Fixtures.data({ Fixtures.slime("a") })
		victim.favoriteId = "a"
		Steal.complete(victim, Fixtures.data(), "a")
		expect(victim.favoriteId).toBeNil()
	end)
end)
