--!strict
-- PvpRules, PvpService, the pvp save field and Config.PVP_TOOLS validation (FEATURES.PvP, CONTRACT.md §26).
-- Every flag-dependent call passes the flag explicitly, so the specs hold in the forced-flag runs too.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local serde = require("@lune/serde")
local PVP = Config.PVP
local T0 = ServerFixtures.T0

local function data(rebirths: number, cash: number): PlayerData.Data
	local d = Fixtures.data(nil, cash)
	d.rebirths = rebirths
	return d
end

local FAR = { X = 200, Y = 3, Z = -200 }
local function fighter(position: any?, extra: { [string]: any }?): any
	local f: any = { position = position or FAR }
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

describe("PvpRules config", function()
	it("lists the whole ladder", function()
		local count = { Knockback = 0, Trap = 0, Blaster = 0, Fun = 0 }
		for _, tool in Config.PVP_TOOLS do
			count[tool.line] += 1
		end
		expect(count.Knockback).toBe(5)
		expect(count.Trap).toBe(3)
		expect(count.Blaster).toBe(3)
		expect(count.Fun).toBe(8)
	end)
	it("passes its own validation", function()
		expect(#Validate.pvpTools(Config.PVP_TOOLS, PVP, Config.REBIRTH_TIERS)).toBe(0)
	end)
	it("validation rejects a fast cooldown, a long control, a bad gate and a damage field", function()
		local function check(patch: { [string]: any }): number
			local tool: any = table.clone(Config.PVP_TOOLS[1])
			for k, v in patch do
				tool[k] = v
			end
			return #Validate.pvpTools({ tool }, PVP, Config.REBIRTH_TIERS)
		end
		expect(check({})).toBe(0)
		expect(check({ cooldown = 1.4 })).toBe(1)
		expect(check({ control = 2.5 })).toBe(1)
		expect(check({ slowSeconds = 3.5 })).toBe(1)
		expect(check({ rebirths = 4 })).toBe(1) -- not a REBIRTH_TIERS threshold
		expect(check({ damage = 5 })).toBe(1)
		expect(check({ health = -1 })).toBe(1)
		expect(check({ shotGap = 0.1 })).toBe(1) -- faster than the UsePvpItem rate limit
	end)
	it("the strongest power punch fits the knockback cap", function()
		local top = PvpRules.toolAt("Knockback", PvpRules.maxTier("Knockback"))
		expect(top ~= nil and (top.push or 0) * PVP.CHARGE_PUSH <= PVP.KNOCKBACK_MAX_PUSH).toBe(true)
		expect(top ~= nil and (top.arc or 0) <= PVP.KNOCKBACK_ARC_HEIGHT).toBe(true)
	end)
end)

describe("PvpRules pricing and gating", function()
	it("price = factor x rebirthCost(gate), at least PRICE_MIN", function()
		expect(PvpRules.price("KnockGlove1")).toBe(math.floor(0.03 * Economy.rebirthCost(1)))
		expect(PvpRules.price("KnockGlove5")).toBe(math.floor(0.03 * Economy.rebirthCost(20)))
		expect(PvpRules.price("FunBalloon")).toBe(math.floor(0.01 * Economy.rebirthCost(1)))
		expect(PvpRules.price("FunConfetti")).toBe(PVP.PRICE_MIN) -- gate 0: 50 -> the minimum
		expect(PvpRules.price("GooTrap2")).toBe(
			math.max(PVP.PRICE_MIN, math.floor(PVP.PRICE_FACTOR_TRAP * Economy.rebirthCost(6)))
		)
		expect(PvpRules.price("nope")).toBe(0)
	end)
	it("prices rise with the gate inside a line", function()
		for _, line in PvpRules.LINES do
			local last = 0
			for tier = 1, PvpRules.maxTier(line) do
				local tool = PvpRules.toolAt(line, tier)
				local price = PvpRules.price(tool and tool.id or "")
				expect(price > last).toBe(true)
				last = price
			end
		end
	end)
	it("isUnlocked follows the rank gate", function()
		expect(PvpRules.isUnlocked(data(0, 0), "KnockGlove1")).toBe(false)
		expect(PvpRules.isUnlocked(data(1, 0), "KnockGlove1")).toBe(true)
		expect(PvpRules.isUnlocked(data(19, 0), "KnockGlove5")).toBe(false)
		expect(PvpRules.isUnlocked(data(20, 0), "KnockGlove5")).toBe(true)
		expect(PvpRules.isUnlocked(data(50, 0), "nope")).toBe(false)
	end)
	it("canBuy refuses with the flag off, then by rank, cash, unknown id and ownership", function()
		local rich = data(1, 1e9)
		expect(select(2, PvpRules.canBuy(rich, "KnockGlove1", false))).toBe("PvP is not open yet")
		expect((PvpRules.canBuy(rich, "KnockGlove1", true))).toBe(true)
		expect(select(2, PvpRules.canBuy(rich, "KnockGlove2", true))).toBe("needs 5 rebirths")
		expect(select(2, PvpRules.canBuy(data(1, 10), "KnockGlove1", true))).toBe("not enough cash")
		expect(select(2, PvpRules.canBuy(rich, "Nope", true))).toBe("unknown item")
		expect(select(2, PvpRules.canBuy(rich, 5, true))).toBe("unknown item")
		PvpRules.buy(rich, "KnockGlove1", true)
		expect(select(2, PvpRules.canBuy(rich, "KnockGlove1", true))).toBe("already owned")
	end)
	it("buy charges the price and records the item", function()
		local d = data(5, 1e9)
		expect((PvpRules.buy(d, "KnockGlove2", true))).toBe(true)
		expect(d.cash).toBe(1e9 - PvpRules.price("KnockGlove2"))
		expect(PvpRules.bestTier(d, "Knockback")).toBe(2)
		expect((PvpRules.buy(d, "FunBouncePad", true))).toBe(true)
		expect(PvpRules.owns(d, "FunBouncePad")).toBe(true)
		local poor = data(5, 5)
		expect((PvpRules.buy(poor, "KnockGlove2", true))).toBe(false)
		expect(poor.cash).toBe(5)
		expect(PvpRules.owns(poor, "KnockGlove2")).toBe(false)
		local off = data(5, 1e9)
		expect((PvpRules.buy(off, "KnockGlove2", false))).toBe(false)
		expect(off.cash).toBe(1e9)
	end)
	it("a higher tier supersedes the lower ones of its line", function()
		local d = data(8, 1e12)
		PvpRules.buy(d, "KnockGlove1", true)
		PvpRules.buy(d, "KnockGlove3", true) -- skipping tier 2 is allowed
		expect(PvpRules.owns(d, "KnockGlove1")).toBe(true)
		expect(PvpRules.owns(d, "KnockGlove2")).toBe(true)
		expect(PvpRules.owns(d, "KnockGlove3")).toBe(true)
		expect(PvpRules.owns(d, "KnockGlove4")).toBe(false)
		local best = PvpRules.bestTool(d, "Knockback")
		expect(best ~= nil and best.id).toBe("KnockGlove3")
		expect(select(2, PvpRules.canBuy(d, "KnockGlove2", true))).toBe("already owned")
		expect(PvpRules.bestTool(d, "Trap")).toBe(nil)
		-- lines are independent
		expect(PvpRules.owns(d, "GooTrap1")).toBe(false)
	end)
	it("a trap buy adds one charge, up to TRAP_MAX_HELD per tier; a 6th is refused", function()
		local d = data(10, 1e12)
		for n = 1, PVP.TRAP_MAX_HELD do
			expect((PvpRules.buy(d, "GooTrap1", true))).toBe(true)
			expect(PvpRules.charges(d, "GooTrap1")).toBe(n)
		end
		local cash = d.cash
		expect(select(2, PvpRules.buy(d, "GooTrap1", true))).toBe(`you can only hold {PVP.TRAP_MAX_HELD}`)
		expect(d.cash).toBe(cash)
		expect(PvpRules.charges(d, "GooTrap1")).toBe(PVP.TRAP_MAX_HELD)
		-- every tier has its own stack; owning a higher tier does not own the lower one
		expect((PvpRules.buy(d, "GooTrap3", true))).toBe(true)
		expect(PvpRules.owns(d, "GooTrap2")).toBe(false)
		expect(PvpRules.bestTier(d, "Trap")).toBe(3)
	end)
	it("a used charge is gone; the last one ends ownership", function()
		local d = data(3, 1e12)
		PvpRules.buy(d, "GooTrap1", true)
		PvpRules.buy(d, "GooTrap1", true)
		expect(PvpRules.useCharge(d, "GooTrap1")).toBe(true)
		expect(PvpRules.owns(d, "GooTrap1")).toBe(true)
		expect(PvpRules.useCharge(d, "GooTrap1")).toBe(true)
		expect(PvpRules.owns(d, "GooTrap1")).toBe(false)
		expect(PvpRules.useCharge(d, "GooTrap1")).toBe(false)
		expect(PvpRules.bestTool(d, "Trap")).toBe(nil)
	end)
end)

describe("PvpRules control", function()
	it("clamps to 2 s, then 3 s immunity", function()
		local state = PvpRules.newState()
		expect(PvpRules.canControl(state, T0)).toBe(true)
		expect(PvpRules.applyControl(state, 10, T0)).toBe(2)
		expect(state.controlUntil).toBe(T0 + 2)
		expect(PvpRules.canControl(state, T0 + 1)).toBe(false) -- still controlled
		expect(PvpRules.canControl(state, T0 + 4.9)).toBe(false) -- immune (2 s control + 3 s)
		expect(PvpRules.applyControl(state, 1, T0 + 4.9)).toBe(0)
		expect(PvpRules.canControl(state, T0 + 5)).toBe(true)
		expect(PvpRules.applyControl(state, 1.2, T0 + 5)).toBe(1.2)
	end)
	it("ignores zero, negative and NaN durations", function()
		local state = PvpRules.newState()
		expect(PvpRules.applyControl(state, 0, T0)).toBe(0)
		expect(PvpRules.applyControl(state, -3, T0)).toBe(0)
		expect(PvpRules.applyControl(state, 0 / 0, T0)).toBe(0)
		expect(PvpRules.canControl(state, T0)).toBe(true)
	end)
	it("slows are capped at 3 s and share the immunity", function()
		local state = PvpRules.newState()
		expect(PvpRules.applySlow(state, 9, T0)).toBe(3)
		expect(PvpRules.canControl(state, T0 + 5.9)).toBe(false)
		expect(PvpRules.canControl(state, T0 + 6)).toBe(true)
	end)
	it("a stacking slow grows but never lasts past SLOW_MAX_SECONDS from its first hit", function()
		local state = PvpRules.newState()
		local ends = T0 + PvpRules.applySlow(state, 1, T0)
		ends = PvpRules.extendSlow(state, T0, ends, 1, T0 + 0.5)
		expect(ends).toBe(T0 + 2)
		ends = PvpRules.extendSlow(state, T0, ends, 5, T0 + 1)
		expect(ends).toBe(T0 + PVP.SLOW_MAX_SECONDS)
		expect(state.immuneUntil).toBe(T0 + PVP.SLOW_MAX_SECONDS + PVP.CONTROL_IMMUNITY_SECONDS)
		expect(PvpRules.extendSlow(state, T0, ends, 1, T0 + 10)).toBe(ends) -- over: nothing to extend
	end)
end)

describe("PvpRules cooldowns", function()
	it("a tool is ready until used, then after its cooldown (never below the minimum)", function()
		local state = PvpRules.newState()
		expect(PvpRules.ready(state, "GooBlaster3", T0)).toBe(true)
		PvpRules.markUsed(state, "GooBlaster3", T0)
		expect(PvpRules.ready(state, "GooBlaster3", T0 + 5.9)).toBe(false)
		expect(PvpRules.ready(state, "GooBlaster3", T0 + 6)).toBe(true)
		PvpRules.markUsed(state, "GooBlaster3", T0, 0.1) -- a handler-chosen length is still at least the minimum
		expect(PvpRules.ready(state, "GooBlaster3", T0 + 1.4)).toBe(false)
		PvpRules.markUsed(state, "KnockGlove1", T0)
		expect(PvpRules.ready(state, "KnockGlove1", T0 + 1.4)).toBe(false)
		expect(PvpRules.ready(state, "KnockGlove1", T0 + 1.5)).toBe(true)
		expect(PvpRules.ready(state, "FunBalloon", T0)).toBe(true) -- independent
		expect(PvpRules.ready(state, "Nope", T0)).toBe(false)
	end)
end)

describe("PvpRules.canTarget", function()
	local function ctx(toolId: string, extra: { [string]: any }?): any
		local c: any = { now = T0 + 1000, toolId = toolId, enabled = true }
		for k, v in extra or {} do
			c[k] = v
		end
		return c
	end
	it("refuses everything with the flag off", function()
		expect((PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1", { enabled = false })))).toBe(false)
		expect((PvpRules.canTarget(fighter(), nil, ctx("FunConfetti", { enabled = false })))).toBe(false)
	end)
	it("allows any tool on anyone, anywhere: there are no safe zones and no own-plot rule", function()
		expect((PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1")))).toBe(true)
		expect(
			(PvpRules.canTarget(fighter({ X = 0, Y = 3, Z = 0 }), fighter({ X = 1, Y = 3, Z = 1 }), ctx("KnockGlove1")))
		).toBe(true)
		local thief = fighter(nil, { carrying = true })
		expect((PvpRules.canTarget(fighter(), thief, ctx("GooBlaster1")))).toBe(true)
	end)
	it("a player who just joined may hit and be hit with any item", function()
		local fresh = fighter(nil, { state = PvpRules.newState(), rebirths = 0 })
		expect((PvpRules.canTarget(fighter(), fresh, ctx("KnockGlove1")))).toBe(true)
		expect((PvpRules.canTarget(fighter(), fresh, ctx("FunBalloon")))).toBe(true)
		expect((PvpRules.canTarget(fresh, fighter(), ctx("KnockGlove1")))).toBe(true)
	end)
	it("cosmetic items may have no target, tools need one", function()
		expect((PvpRules.canTarget(fighter(), nil, ctx("FunFireworks")))).toBe(true)
		expect(select(2, PvpRules.canTarget(fighter(), nil, ctx("KnockGlove1")))).toBe("no target")
	end)
	it("a control tool is refused on an immune target", function()
		local state = PvpRules.newState()
		PvpRules.applyControl(state, 1, T0 + 1000)
		expect((PvpRules.canTarget(fighter(), fighter(nil, { state = state }), ctx("GooTrap2")))).toBe(false)
		expect((PvpRules.canTarget(fighter(), fighter(nil, { state = state }), ctx("KnockGlove1")))).toBe(true)
	end)
	it("checks the attacker's cooldown, ownership and rank when given", function()
		local state = PvpRules.newState()
		PvpRules.markUsed(state, "KnockGlove1", T0 + 1000)
		expect(select(2, PvpRules.canTarget(fighter(nil, { state = state }), fighter(), ctx("KnockGlove1")))).toBe(
			"not ready"
		)
		local d = data(1, 1e9)
		expect(select(2, PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1", { data = d })))).toBe("not owned")
		PvpRules.buy(d, "KnockGlove1", true)
		expect((PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1", { data = d })))).toBe(true)
		d.rebirths = 0 -- rank lost: the gate is checked on every use
		expect((PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1", { data = d })))).toBe(false)
	end)
	it("refuses an unknown tool", function()
		expect(select(2, PvpRules.canTarget(fighter(), fighter(), ctx("Nope")))).toBe("unknown item")
	end)
end)

describe("PvpRules.clampKnockback", function()
	local origin = { X = 10, Y = 5, Z = 10 }
	it("moves by the push when it is small and inside the map", function()
		local landing, applied = PvpRules.clampKnockback(origin, { X = 3, Y = 1, Z = 0 })
		expect(landing.X).toBe(13)
		expect(landing.Z).toBe(10)
		expect(landing.Y).toBe(5)
		expect(applied.Y).toBe(1)
	end)
	it("caps the horizontal push and the arc", function()
		local landing, applied = PvpRules.clampKnockback(origin, { X = 300, Y = 90, Z = 400 })
		expect(math.abs(math.sqrt(applied.X ^ 2 + applied.Z ^ 2) - PVP.KNOCKBACK_MAX_PUSH) < 1e-9).toBe(true)
		expect(applied.Y).toBe(PVP.KNOCKBACK_ARC_HEIGHT)
		expect(landing.X > origin.X and landing.Z > origin.Z).toBe(true)
		expect(select(2, PvpRules.clampKnockback(origin, { X = 1, Y = -50, Z = 0 })).Y).toBe(0) -- never down
	end)
	it("keeps the landing point inside the map bounds, with a margin", function()
		local edge = { X = 319, Y = 2, Z = -319 }
		local landing = PvpRules.clampKnockback(edge, { X = 8, Y = 0, Z = -8 })
		expect(landing.X).toBe(PVP.MAP_BOUNDS.maxX - PVP.KNOCKBACK_BOUNDS_MARGIN)
		expect(landing.Z).toBe(PVP.MAP_BOUNDS.minZ + PVP.KNOCKBACK_BOUNDS_MARGIN)
		local custom = PvpRules.clampKnockback({ X = 0, Y = 0, Z = 0 }, { X = 8, Y = 0, Z = 0 }, {
			minX = -40,
			maxX = 40,
			minZ = -40,
			maxZ = 40,
		})
		expect(custom.X).toBe(math.min(8, 40 - PVP.KNOCKBACK_BOUNDS_MARGIN))
	end)
	it("pulls an origin that is already outside back in and survives NaN", function()
		local landing = PvpRules.clampKnockback({ X = 5000, Y = 0, Z = -5000 }, { X = 0 / 0, Y = 0 / 0, Z = 1 })
		expect(landing.X).toBe(PVP.MAP_BOUNDS.maxX - PVP.KNOCKBACK_BOUNDS_MARGIN)
		expect(landing.Z).toBe(PVP.MAP_BOUNDS.minZ + PVP.KNOCKBACK_BOUNDS_MARGIN)
	end)
end)

describe("PvpRules save field", function()
	it("round-trips through serialize -> JSON -> deserialize", function()
		local d = data(12, 1e12)
		PvpRules.buy(d, "KnockGlove4", true)
		PvpRules.buy(d, "GooTrap2", true)
		PvpRules.buy(d, "GooTrap2", true)
		PvpRules.buy(d, "FunConfetti", true)
		PvpRules.buy(d, "FunDanceBomb", true)
		local back = SaveData.deserialize(serde.decode("json", serde.encode("json", SaveData.serialize(d, 1700000000))))
		expect(back.pvp.tiers).toEqual({ Knockback = 4 })
		expect(back.pvp.traps).toEqual({ GooTrap2 = 2 })
		expect(back.pvp.fun).toEqual({ FunConfetti = true, FunDanceBomb = true })
		expect(PvpRules.owns(back, "KnockGlove2")).toBe(true)
		expect(PvpRules.charges(back, "GooTrap2")).toBe(2)
	end)
	it("an old save without pvp loads with nothing owned and keeps the version", function()
		local old = SaveData.serialize(Fixtures.data(nil, 50))
		old.pvp = nil
		local back = SaveData.deserialize(old)
		expect(back.pvp).toEqual({ tiers = {}, traps = {}, fun = {} })
		expect(back.version).toBe(Config.SAVE_VERSION)
		expect(SaveData.serialize(back).pvp).toEqual({ tiers = {}, traps = {}, fun = {} })
	end)
	it("clamps hostile values and ignores unknown ids", function()
		local raw = SaveData.serialize(Fixtures.data(nil, 50))
		raw.pvp = {
			tiers = { Knockback = 99, Trap = 2, Blaster = "x", Bogus = 3 },
			traps = { GooTrap1 = 99, GooTrap2 = -1, KnockGlove1 = 3, Nope = 2 },
			fun = { "FunBalloon", "FunBalloon", "KnockGlove1", "Nope", 7, true },
		}
		local back = SaveData.deserialize(raw)
		expect(back.pvp.tiers).toEqual({ Knockback = 5 })
		expect(back.pvp.traps).toEqual({ GooTrap1 = PVP.TRAP_MAX_HELD })
		expect(back.pvp.fun).toEqual({ FunBalloon = true })
		for _, junk in { 5, "x", true, {} } :: { any } do
			raw.pvp = junk
			expect(SaveData.deserialize(raw).pvp).toEqual({ tiers = {}, traps = {}, fun = {} })
		end
	end)
end)

describe("PvpService", function()
	local function setup(rebirths: number?, cash: number?)
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, cash or 1e12)
		session.data.rebirths = rebirths or 0
		return world, session
	end

	it("does nothing with the flag off: no state, refuses, no attribute value", function()
		local world, session = setup(5)
		PvpService.join(world, session, T0, false)
		expect(PvpService.state(session)).toBe(nil)
		local cash = session.data.cash
		local ok, reason = PvpService.buy(world, session, "KnockGlove2", false)
		expect(ok).toBe(false)
		expect(reason).toBe("PvP is not open yet")
		expect(session.data.cash).toBe(cash)
		expect(session.data.pvp.tiers).toEqual({})
		expect(#world.outbox).toBe(0)
	end)
	it("joining while the shipped flag is off creates no state", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 7)
		expect(PvpService.state(session) ~= nil).toBe(Config.FEATURES.PvP)
	end)
	it("buy charges, records and toasts when on", function()
		local world, session = setup(5)
		local price = PvpRules.price("KnockGlove2")
		local ok = PvpService.buy(world, session, "KnockGlove2", true)
		expect(ok).toBe(true)
		expect(session.data.cash).toBe(1e12 - price)
		expect(PvpRules.bestTier(session.data, "Knockback")).toBe(2)
		expect(session.dirty).toBe(true)
		expect(world.outbox[#world.outbox].text).toBe("Bounce Glove bought!")
		expect((PvpService.buy(world, session, "KnockGlove2", true))).toBe(false) -- already owned
	end)
	it("the BuyPvpItem action validates args, refuses with the flag off and buys with it on", function()
		local world, session = setup(1)
		local function act(name: any, flag: boolean?, at: number)
			return Actions.handle(world, 1, "BuyPvpItem", { name }, at, {
				distanceBetween = function()
					return math.huge
				end,
				positionOf = function()
					return nil
				end,
				features = { PvP = flag },
			})
		end
		expect(act("KnockGlove1", false, T0 + 10).ok).toBe(false)
		expect(act(5, true, T0 + 20).ok).toBe(false)
		expect(act("KnockGlove1", true, T0 + 30).ok).toBe(true)
		expect(PvpRules.owns(session.data, "KnockGlove1")).toBe(true)
		expect(act("KnockGlove1", true, T0 + 30.1).ok).toBe(false) -- rate limited / owned
	end)
	it("a player who just joined is a normal PvP target; leave drops the runtime state", function()
		local world, session = setup(0)
		local other = ServerFixtures.join(world, 2, nil, 1e12)
		PvpService.join(world, session, T0, true)
		PvpService.join(world, other, T0, true)
		local here = { X = 0, Y = 3, Z = 0 }
		local ok = PvpRules.canTarget(
			PvpService.fighterAt(here, other),
			PvpService.fighterAt(here, session),
			{ now = T0 + 1, toolId = "KnockGlove1", enabled = true }
		)
		expect(ok).toBe(true)
		PvpService.leave(world, session, T0 + 400)
		expect(PvpService.state(session)).toBe(nil)
	end)
	it("catchThief sends a stolen slime home with the Bat's toasts and returns its id", function()
		local world = ServerFixtures.world()
		local thief = ServerFixtures.join(world, 1)
		local owner = ServerFixtures.join(world, 2, { Fixtures.slime("gem", 3) })
		local hunter = ServerFixtures.join(world, 3)
		ServerFixtures.unlock(owner)
		ServerFixtures.unlock(thief)
		expect(PvpService.catchThief(world, thief, hunter, T0 + 100)).toBe(nil) -- carries nothing
		expect((StealService.steal(world, thief, "gem", 1, T0 + 101))).toBe(true)
		expect(PvpService.catchThief(world, thief, hunter, T0 + 102)).toBe("gem")
		expect(thief.carry).toBe(nil)
		expect(world.carriedBy.gem).toBe(nil)
		expect(world.escaping.gem ~= nil).toBe(true) -- bounces home
		local escaped = nil
		for _, event in world.outbox do
			if event.type == "Escaped" then
				escaped = event
			end
		end
		expect(escaped and escaped.reason).toBe("slap") -- the SlapHitAt StealAlerts FX
		expect(table.find(ServerFixtures.notifications(world, 3), "You caught P1! The slime went home.") ~= nil).toBe(
			true
		)
		expect(#ServerFixtures.notifications(world, 2) > 0).toBe(true) -- the owner hears it escaped
	end)
	it("leaving a never-joined session is harmless", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1)
		PvpService.leave(world, session, T0)
		expect(Sessions.leave(world, 1, T0 + 1) ~= nil).toBe(true)
	end)
end)
