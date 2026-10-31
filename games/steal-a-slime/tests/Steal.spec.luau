--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local Steal = require("../src/shared/Steal")
local TestRunner = require("./TestRunner")
local VatState = require("../src/shared/VatState")

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
		thiefCanSave = true,
		ownerCanSave = true,
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
	it("lock duration is capped at LOCK_MAX_SECONDS (4 min) however many rebirths", function()
		expect(Config.LOCK_MAX_SECONDS).toBe(240)
		expect(Steal.lockDuration(1000)).toBe(Config.LOCK_MAX_SECONDS)
		local data = Fixtures.data(nil, 1e6)
		data.rebirths = 1000
		local ok, untilT = Steal.buyLock(data, 0, 500)
		expect(ok).toBe(true)
		expect(untilT).toBe(500 + Config.LOCK_MAX_SECONDS)
	end)
	it("locking is free and starts from now when expired", function()
		local data = Fixtures.data(nil, 0)
		local ok, untilT = Steal.buyLock(data, 0, 500)
		expect(ok).toBe(true)
		expect(untilT).toBe(500 + Config.LOCK_SECONDS)
		expect(data.cash).toBe(0)
	end)
	it("refuses a lock while one is running: no extending, nothing changes", function()
		local data = Fixtures.data(nil, 1e6)
		local ok, untilT, reason = Steal.buyLock(data, 530, 500) -- 30 s left
		expect(ok).toBe(false)
		expect(untilT).toBe(530)
		expect(reason).toBe("your base is already locked")
	end)
	it("one lock gives the full duration, and again after it expired", function()
		local data = Fixtures.data(nil, 0)
		data.rebirths = 3
		local full = Config.LOCK_SECONDS + 3 * Config.LOCK_SECONDS_PER_REBIRTH
		local ok, untilT = Steal.buyLock(data, 0, 500)
		expect(ok).toBe(true)
		expect(untilT).toBe(500 + full)
		expect((Steal.buyLock(data, untilT, untilT - 1))).toBe(false)
		local ok2, again = Steal.buyLock(data, untilT, untilT)
		expect(ok2).toBe(true)
		expect(again).toBe(untilT + full)
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
	it("blocks a steal when either player's progress can't be saved", function()
		expect(select(2, Steal.canSteal(ctx({ thiefCanSave = false })))).toBe(
			"your progress can't be saved on this server"
		)
		expect(select(2, Steal.canSteal(ctx({ ownerCanSave = false })))).toBe(
			"their slimes can't be saved on this server"
		)
	end)
	it("blocks a thief outside the owner's base, however close, guests and lock breaks included", function()
		expect(select(2, Steal.canSteal(ctx({ thiefInside = false, distance = 1 })))).toBe(Steal.OUTSIDE_TEXT)
		expect(select(2, Steal.canSteal(ctx({ thiefInside = false, thiefIsGuest = true })))).toBe(Steal.OUTSIDE_TEXT)
		expect(select(2, Steal.canSteal(ctx({ thiefInside = false, thiefLockBreak = true })))).toBe(Steal.OUTSIDE_TEXT)
		expect((Steal.canSteal(ctx({ thiefInside = true })))).toBe(true)
	end)
	it("says the base is locked before it says go inside", function()
		expect(select(2, Steal.canSteal(ctx({ thiefInside = false, lockUntil = 101 })))).toBe("base is locked")
	end)
end)

describe("Steal carry", function()
	it("carries have no time limit", function()
		local c = Steal.newCarry("stolen", Config.MAX_TIER, 0)
		expect((c :: any).escapeAt).toBeNil()
		expect(c.kind).toBe("stolen")
		expect(c.startedAt).toBe(0)
	end)
	it("rarer slimes slow you more", function()
		local slowCommon = Steal.carrySlow(Steal.newCarry("wild", 1, 0))
		local slowMythic = Steal.carrySlow(Steal.newCarry("wild", 6, 0))
		expect(slowMythic > slowCommon).toBeTruthy()
		expect(Steal.walkSpeed(nil)).toBe(Config.BASE_WALK_SPEED)
		expect(Steal.walkSpeed(Steal.newCarry("wild", 1, 0))).toBeCloseTo(16 * 0.95)
	end)
	it("a stolen slime slows you by its rarity only, the same however long you hold it", function()
		for tier = 1, Config.MAX_TIER do
			local c = Steal.newCarry("stolen", tier, 0)
			expect(Steal.carrySlow(c)).toBeCloseTo(math.min(Config.RARITIES[tier].carrySlow, Config.MAX_CARRY_SLOW))
		end
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
		expect((Steal.canSlap(slap({ targetCarry = Steal.newCarry("wild", 1, 0) })))).toBe(true) -- any carried slime
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
	it("takes a slime waiting in the victim's vat out of it", function()
		local victim = Fixtures.data({ Fixtures.slime("a", 1), Fixtures.slime("b", 1) })
		VatState.add(victim, "a")
		VatState.add(victim, "b")
		local ok = Steal.complete(victim, Fixtures.data(), "a")
		expect(ok).toBe(true)
		expect(table.concat(VatState.ids(victim), ",")).toBe("b")
	end)
	it("clears the victim's favourite", function()
		local victim = Fixtures.data({ Fixtures.slime("a") })
		victim.favoriteId = "a"
		Steal.complete(victim, Fixtures.data(), "a")
		expect(victim.favoriteId).toBeNil()
	end)
end)
