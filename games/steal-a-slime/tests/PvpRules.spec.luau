--!strict
-- PvpRules, PvpService, the pvp save field and Config.PVP_TOOLS validation (FEATURES.PvP, CONTRACT.md §26).
-- Every flag-dependent call passes the flag explicitly, so the specs hold in the forced-flag runs too.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local Fountain = require("../src/shared/Fountain")
local PlayerData = require("../src/shared/PlayerData")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local serde = require("@lune/serde")
local PVP = Config.PVP
local T0 = ServerFixtures.T0

local function data(rebirths: number, cash: number): PlayerData.Data
	local d = Fixtures.data(nil, cash)
	d.rebirths = rebirths
	return d
end

local FAR = { X = 200, Y = 3, Z = -200 } -- clear of every safe zone
local function fighter(position: any?, extra: { [string]: any }?): any
	local f: any = { position = position or FAR }
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

describe("PvpRules config", function()
	it("is on by default (Merijn 2026-10-17: PvP ships on)", function()
		expect(Config.FEATURES.PvP).toBe(true)
	end)
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
	it("matches the documented numbers", function()
		expect(PVP.NEW_PLAYER_SHIELD_SECONDS).toBe(600)
		expect(PVP.CONTROL_MAX_SECONDS).toBe(2)
		expect(PVP.CONTROL_IMMUNITY_SECONDS).toBe(3)
		expect(PVP.MIN_COOLDOWN).toBe(1.5)
		expect(PVP.PRICE_FACTOR_TOOL).toBe(0.03)
		expect(PVP.PRICE_FACTOR_FUN).toBe(0.01)
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
	end)
	it("every control is within the cap and no tool has a damage field", function()
		for _, tool in Config.PVP_TOOLS do
			expect((tool :: any).damage).toBe(nil)
			expect(tool.cooldown >= PVP.MIN_COOLDOWN).toBe(true)
			expect((tool.control or 0) <= PVP.CONTROL_MAX_SECONDS).toBe(true)
			expect((tool.slowSeconds or 0) <= PVP.SLOW_MAX_SECONDS).toBe(true)
		end
	end)
	it("top knockback is at most 2x the base push and within the cap", function()
		local top = PvpRules.toolAt("Knockback", PvpRules.maxTier("Knockback"))
		expect(top ~= nil and top.push or 0).toBe(8)
		expect(PVP.KNOCKBACK_MAX_PUSH).toBe(8)
	end)
	it("safe zones sit where the world puts the spawn, the shop and the fountain", function()
		local zones = {}
		for _, zone in PVP.SAFE_ZONES do
			zones[zone.id] = zone
		end
		local shop = WorldLayout.PROP_SPOTS.ItemShopStand.pos
		expect(math.abs(zones.shop.x - shop[1]) < 0.01 and math.abs(zones.shop.z - shop[3]) < 0.01).toBe(true)
		expect(zones.fountain.radius).toBe(Fountain.LANDING_RING_OUTER)
		-- the hub spawn is on the same bearing as the shop, scripts/StaticWorld SPAWN_YAW 67.5 / SPAWN_RADIUS 64
		expect(math.abs(math.atan2(zones.spawn.x, zones.spawn.z) - math.rad(67.5)) < 1e-6).toBe(true)
		expect(math.abs(math.sqrt(zones.spawn.x ^ 2 + zones.spawn.z ^ 2) - 64) < 1e-6).toBe(true)
	end)
end)

describe("PvpRules pricing and gating", function()
	it("price = factor x rebirthCost(gate), at least PRICE_MIN", function()
		expect(PvpRules.price("KnockGlove1")).toBe(math.floor(0.03 * Economy.rebirthCost(1)))
		expect(PvpRules.price("KnockGlove5")).toBe(math.floor(0.03 * Economy.rebirthCost(20)))
		expect(PvpRules.price("FunBalloon")).toBe(math.floor(0.01 * Economy.rebirthCost(1)))
		expect(PvpRules.price("FunConfetti")).toBe(PVP.PRICE_MIN) -- gate 0: 50 -> the minimum
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
end)

describe("PvpRules shield", function()
	it("lasts the full 10 minutes for a new player and ends with a rebirth", function()
		local state = PvpRules.newState()
		state.shieldUntil = PvpRules.shieldEnd(0, 0, T0)
		expect(state.shieldUntil).toBe(T0 + 600)
		expect(PvpRules.isShielded(state, T0, 0)).toBe(true)
		expect(PvpRules.isShielded(state, T0 + 599.9, 0)).toBe(true)
		expect(PvpRules.isShielded(state, T0 + 600, 0)).toBe(false)
		expect(PvpRules.isShielded(state, T0 + 10, 1)).toBe(false) -- first rebirth
		expect(PvpRules.isShielded(nil, T0, 0)).toBe(false)
	end)
	it("counts earlier play time and never starts for a veteran", function()
		expect(PvpRules.shieldEnd(400, 0, T0)).toBe(T0 + 200)
		expect(PvpRules.shieldEnd(600, 0, T0)).toBe(0)
		expect(PvpRules.shieldEnd(0, 1, T0)).toBe(0)
	end)
end)

describe("PvpRules safe zones", function()
	it("is true inside every zone, ignores height and false outside", function()
		for _, zone in PVP.SAFE_ZONES do
			expect(PvpRules.inSafeZone({ X = zone.x, Y = 0, Z = zone.z })).toBe(true)
			expect(PvpRules.inSafeZone({ X = zone.x, Y = 500, Z = zone.z })).toBe(true)
			expect(PvpRules.inSafeZone({ X = zone.x + zone.radius - 0.1, Y = 0, Z = zone.z })).toBe(true)
			expect(PvpRules.inSafeZone({ X = zone.x + zone.radius + 1000, Y = 0, Z = zone.z })).toBe(false)
		end
		expect(PvpRules.inSafeZone(FAR)).toBe(false)
		expect(PvpRules.inSafeZone({ X = 0, Y = 0, Z = 44 })).toBe(true) -- fountain curb
		expect(PvpRules.inSafeZone({ X = 0, Y = 0, Z = 45 })).toBe(false)
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
end)

describe("PvpRules cooldowns", function()
	it("a tool is ready until used, then after its cooldown (never below the minimum)", function()
		local state = PvpRules.newState()
		expect(PvpRules.ready(state, "GooBlaster1", T0)).toBe(true)
		PvpRules.markUsed(state, "GooBlaster1", T0)
		expect(PvpRules.ready(state, "GooBlaster1", T0 + 11.9)).toBe(false)
		expect(PvpRules.ready(state, "GooBlaster1", T0 + 12)).toBe(true)
		PvpRules.markUsed(state, "KnockGlove1", T0)
		expect(PvpRules.ready(state, "KnockGlove1", T0 + 1.4)).toBe(false)
		expect(PvpRules.ready(state, "KnockGlove1", T0 + 1.5)).toBe(true)
		expect(PvpRules.ready(state, "FunBalloon", T0)).toBe(true) -- independent
		expect(PvpRules.ready(state, "Nope", T0)).toBe(false)
	end)
end)

describe("PvpRules.canTarget", function()
	local function ctx(toolId: string, extra: { [string]: any }?): any
		local c: any = { now = T0 + 1000, toolId = toolId, onAttackerPlot = true, enabled = true }
		for k, v in extra or {} do
			c[k] = v
		end
		return c
	end
	local function shielded(): any
		local state = PvpRules.newState()
		state.shieldUntil = T0 + 2000
		return state
	end
	local inShop = { X = Config.PVP.SAFE_ZONES[2].x, Y = 3, Z = Config.PVP.SAFE_ZONES[2].z }

	it("refuses everything with the flag off", function()
		expect((PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1", { enabled = false })))).toBe(false)
		expect((PvpRules.canTarget(fighter(), nil, ctx("FunConfetti", { enabled = false })))).toBe(false)
	end)
	it("allows a tool on your own plot and refuses a stranger away from it", function()
		expect((PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1")))).toBe(true)
		local ok, reason = PvpRules.canTarget(fighter(), fighter(), ctx("KnockGlove1", { onAttackerPlot = false }))
		expect(ok).toBe(false)
		expect(reason).toBe("only on your plot or against a thief")
	end)
	it("allows a tool anywhere against a thief carrying a slime", function()
		local thief = fighter(nil, { carrying = true })
		expect((PvpRules.canTarget(fighter(), thief, ctx("GooBlaster1", { onAttackerPlot = false })))).toBe(true)
	end)
	it("refuses when either side is in a safe zone", function()
		expect(select(2, PvpRules.canTarget(fighter(inShop), fighter(), ctx("KnockGlove1")))).toBe("safe zone")
		expect(select(2, PvpRules.canTarget(fighter(), fighter(inShop), ctx("KnockGlove1")))).toBe(
			"target is in a safe zone"
		)
		-- cosmetic fun items too
		expect((PvpRules.canTarget(fighter(inShop), nil, ctx("FunBalloon")))).toBe(false)
		expect((PvpRules.canTarget(fighter(), fighter(inShop), ctx("FunBalloon")))).toBe(false)
	end)
	it("lets the Confetti Popper work in a safe zone (no target)", function()
		expect((PvpRules.canTarget(fighter(inShop), nil, ctx("FunConfetti")))).toBe(true)
		expect((PvpRules.canTarget(fighter(inShop), fighter(inShop), ctx("FunConfetti")))).toBe(false)
	end)
	it("refuses a shielded target, ends with the shield or a rebirth", function()
		local target = fighter(nil, { state = shielded(), rebirths = 0 })
		expect(select(2, PvpRules.canTarget(fighter(), target, ctx("KnockGlove1")))).toBe("target is shielded")
		expect((PvpRules.canTarget(fighter(), target, ctx("FunBalloon")))).toBe(false) -- cosmetic too
		expect((PvpRules.canTarget(fighter(), target, ctx("KnockGlove1", { now = T0 + 2000 })))).toBe(true)
		target.rebirths = 1
		expect((PvpRules.canTarget(fighter(), target, ctx("KnockGlove1")))).toBe(true)
	end)
	it("cosmetic items are exempt from the own-plot / thief rule and may have no target", function()
		expect((PvpRules.canTarget(fighter(), fighter(), ctx("FunBalloon", { onAttackerPlot = false })))).toBe(true)
		expect((PvpRules.canTarget(fighter(), nil, ctx("FunFireworks", { onAttackerPlot = false })))).toBe(true)
		expect(select(2, PvpRules.canTarget(fighter(), nil, ctx("KnockGlove1")))).toBe("no target")
	end)
	it("a control tool is refused on an immune target", function()
		local state = PvpRules.newState()
		PvpRules.applyControl(state, 1, T0 + 1000)
		expect((PvpRules.canTarget(fighter(), fighter(nil, { state = state }), ctx("GooTrap1")))).toBe(false)
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
			minX = -10,
			maxX = 10,
			minZ = -10,
			maxZ = 10,
		})
		expect(custom.X).toBe(10 - PVP.KNOCKBACK_BOUNDS_MARGIN)
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
		PvpRules.buy(d, "FunConfetti", true)
		PvpRules.buy(d, "FunDanceBomb", true)
		d.pvp.played = 123
		local back = SaveData.deserialize(serde.decode("json", serde.encode("json", SaveData.serialize(d, 1700000000))))
		expect(back.pvp.tiers).toEqual({ Knockback = 4, Trap = 2 })
		expect(back.pvp.fun).toEqual({ FunConfetti = true, FunDanceBomb = true })
		expect(back.pvp.played).toBe(123)
		expect(PvpRules.owns(back, "KnockGlove2")).toBe(true)
	end)
	it("an old save without pvp loads with nothing owned and keeps the version", function()
		local old = SaveData.serialize(Fixtures.data(nil, 50))
		old.pvp = nil
		local back = SaveData.deserialize(old)
		expect(back.pvp).toEqual({ tiers = {}, fun = {}, played = 0 })
		expect(back.version).toBe(Config.SAVE_VERSION)
		expect(SaveData.serialize(back).pvp).toEqual({ tiers = {}, fun = {}, played = 0 })
	end)
	it("clamps hostile values and ignores unknown ids", function()
		local raw = SaveData.serialize(Fixtures.data(nil, 50))
		raw.pvp = {
			tiers = { Knockback = 99, Trap = -4, Blaster = "x", Bogus = 3 },
			fun = { "FunBalloon", "FunBalloon", "KnockGlove1", "Nope", 7, true },
			played = 1e12,
		}
		local back = SaveData.deserialize(raw)
		expect(back.pvp.tiers).toEqual({ Knockback = 5 })
		expect(back.pvp.fun).toEqual({ FunBalloon = true })
		expect(back.pvp.played).toBe(PVP.NEW_PLAYER_SHIELD_SECONDS)
		for _, junk in { 5, "x", true, {} } :: { any } do
			raw.pvp = junk
			expect(SaveData.deserialize(raw).pvp).toEqual({ tiers = {}, fun = {}, played = 0 })
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
		expect(PvpService.shieldUntil(session, T0)).toBe(nil)
		expect(PvpService.isShielded(session, T0)).toBe(false)
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
	it("a new player is shielded for 10 minutes, covering the join lock", function()
		local world, session = setup(0)
		PvpService.join(world, session, T0, true)
		expect(PvpService.isShielded(session, T0 + 1)).toBe(true)
		expect(PvpService.shieldUntil(session, T0 + 1)).toBe(T0 + 600)
		expect(session.lockUntil < T0 + 600).toBe(true)
		expect(PvpService.isShielded(session, T0 + 600)).toBe(false)
		expect(PvpService.shieldUntil(session, T0 + 600)).toBe(nil)
	end)
	it("rebirthed players are never shielded and a rebirth ends the shield", function()
		local world, vet = setup(2)
		PvpService.join(world, vet, T0, true)
		expect(PvpService.isShielded(vet, T0 + 1)).toBe(false)
		local freshWorld, fresh = setup(0)
		PvpService.join(freshWorld, fresh, T0, true)
		fresh.data.rebirths = 1
		expect(PvpService.isShielded(fresh, T0 + 1)).toBe(false)
		expect(PvpService.shieldUntil(fresh, T0 + 1)).toBe(nil)
	end)
	it("play time carries over between sessions", function()
		local world, session = setup(0)
		PvpService.join(world, session, T0, true)
		PvpService.leave(world, session, T0 + 400)
		expect(session.data.pvp.played).toBe(400)
		expect(PvpService.state(session)).toBe(nil)
		session.lockUntil = 0
		PvpService.join(world, session, T0 + 1000, true)
		expect(PvpService.shieldUntil(session, T0 + 1000)).toBe(T0 + 1200)
		PvpService.leave(world, session, T0 + 1300)
		expect(session.data.pvp.played).toBe(600) -- capped
		PvpService.join(world, session, T0 + 2000, true)
		expect(PvpService.isShielded(session, T0 + 2000)).toBe(false)
	end)
	it("a steal ends the shield for good (and is saved as played time)", function()
		local world = ServerFixtures.world()
		local thief = ServerFixtures.join(world, 1)
		local owner = ServerFixtures.join(world, 2, { Fixtures.slime("gem", 3) })
		ServerFixtures.unlock(owner)
		ServerFixtures.unlock(thief)
		PvpService.join(world, thief, T0 + 100, true)
		expect(PvpService.isShielded(thief, T0 + 101)).toBe(true)
		expect((StealService.steal(world, thief, "gem", 1, T0 + 101))).toBe(true)
		expect(PvpService.isShielded(thief, T0 + 102)).toBe(false)
		expect(thief.data.pvp.played).toBe(PVP.NEW_PLAYER_SHIELD_SECONDS)
		PvpService.leave(world, thief, T0 + 110)
		PvpService.join(world, thief, T0 + 200, true)
		expect(PvpService.isShielded(thief, T0 + 201)).toBe(false)
	end)
	it("a steal with the flag off touches nothing", function()
		local world = ServerFixtures.world()
		local thief = ServerFixtures.join(world, 1)
		local owner = ServerFixtures.join(world, 2, { Fixtures.slime("gem", 3) })
		ServerFixtures.unlock(owner)
		ServerFixtures.unlock(thief)
		PvpService.join(world, thief, T0 + 100, false)
		expect((StealService.steal(world, thief, "gem", 1, T0 + 101))).toBe(true)
		expect(thief.data.pvp.played).toBe(0)
	end)
	it("leaving a never-joined session is harmless", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1)
		PvpService.leave(world, session, T0)
		expect(Sessions.leave(world, 1, T0 + 1) ~= nil).toBe(true)
	end)
end)
