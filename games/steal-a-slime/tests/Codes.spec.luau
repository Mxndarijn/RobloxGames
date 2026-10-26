--!strict
local Actions = require("../src/server/Actions")
local Codes = require("../src/shared/Codes")
local Config = require("../src/shared/Config")
local Income = require("../src/server/Income")
local Perks = require("../src/shared/Perks")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
}

local WELCOME_CASH = (Config.CODES :: any).WELCOME.reward.amount

describe("Codes", function()
	it("pays cash once, case-insensitively, and then says used", function()
		local data = PlayerData.new()
		local start = data.cash
		local ok, status = Codes.redeem(data, "  welcome ", T0)
		expect(ok).toBe(true)
		expect(status).toBe("ok")
		expect(data.cash).toBe(start + WELCOME_CASH)
		local ok2, status2 = Codes.redeem(data, "WELCOME", T0)
		expect(ok2).toBe(false)
		expect(status2).toBe("used")
		expect(data.cash).toBe(start + WELCOME_CASH)
	end)
	it("rejects unknown and malformed codes", function()
		local data = PlayerData.new()
		expect(select(2, Codes.redeem(data, "NOPE", T0))).toBe("invalid")
		expect(select(2, Codes.redeem(data, "", T0))).toBe("invalid")
		expect(select(2, Codes.redeem(data, "a b!", T0))).toBe("invalid")
		expect(select(2, Codes.redeem(data, 5, T0))).toBe("invalid")
	end)
	it("rejects an expired code and does not mark it used", function()
		local data = PlayerData.new()
		local late = (Config.CODES :: any).LAUNCH.expiresAt + 1
		expect(select(2, Codes.redeem(data, "LAUNCH", late))).toBe("expired")
		expect(data.redeemed.LAUNCH).toBe(nil)
		expect(select(2, Codes.redeem(data, "LAUNCH", T0))).toBe("ok")
	end)
	it("boost multiplies income and ends on time", function()
		local data = PlayerData.new()
		local before = Perks.bonusMultiplier(data)
		Codes.redeem(data, "SLIMEBOOST", T0)
		expect(Perks.bonusMultiplier(data)).toBe(before * 2)
		expect(data.boostUntil).toBe(T0 + 600)
		expect(Codes.expireBoost(data, T0 + 599)).toBe(false)
		expect(Codes.expireBoost(data, T0 + 600)).toBe(true)
		expect(Perks.bonusMultiplier(data)).toBe(before)
	end)
	it("Income.step ends a finished boost", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.boostMult, s.data.boostUntil = 2, T0 + 5
		Income.step(world, 1, T0 + 6)
		expect(s.data.boostMult).toBe(1)
	end)
	it("save round-trips and old saves default to nothing redeemed", function()
		local data = PlayerData.new()
		Codes.redeem(data, "welcome", T0)
		Codes.redeem(data, "slimeboost", T0)
		local back = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(back.redeemed.WELCOME).toBe(true)
		expect(back.boostMult).toBe(2)
		expect(back.boostUntil).toBe(T0 + 600)
		local old = SaveData.serialize(PlayerData.new(), T0)
		old.redeemed, old.boost = nil, nil
		local fresh = SaveData.deserialize(old)
		expect(next(fresh.redeemed)).toBe(nil)
		expect(fresh.boostMult).toBe(1)
	end)
	it("Redeem action toasts, is server-side and rate limited", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local cash = s.data.cash
		local r = Actions.handle(world, 1, "Redeem", { "welcome" }, T0 + 100, ctx)
		expect(r.ok).toBe(true)
		expect(s.data.cash).toBe(cash + WELCOME_CASH)
		local r2 = Actions.handle(world, 1, "Redeem", { "welcome" }, T0 + 100, ctx)
		expect(r2.message).toBe("too fast")
		s.limiter = {}
		local r3 = Actions.handle(world, 1, "Redeem", { "welcome" }, T0 + 100, ctx)
		expect(r3.message).toBe(Codes.MESSAGES.used)
		expect(Actions.handle(world, 1, "Redeem", { 5 }, T0 + 100, ctx).message).toBe("bad argument")
	end)
end)
