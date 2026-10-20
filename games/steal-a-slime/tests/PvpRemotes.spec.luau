--!strict
-- The PvP remote contract (CONTRACT.md §26.1): PvpEvent, EquipPvpItem / UsePvpItem, vector3 args, the line
-- handler registry, State.pvp. Every flag-dependent call passes the flag explicitly (forced-flag runs).
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local Remotes = require("../src/shared/Remotes")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local roblox = require("@lune/roblox")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local FAR = { X = 200, Y = 3, Z = -200 }

local current: any = nil -- the world of the running test
local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end
local positions: { [number]: any } = {}
local env = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
	onOwnPlot = function(): boolean
		return true
	end,
}
local ctx = {
	distanceBetween = function()
		return math.huge
	end,
	positionOf = env.positionOf,
	onOwnPlot = env.onOwnPlot,
	features = { PvP = true },
}

local function setup(): (any, any, any)
	positions = { [1] = FAR, [2] = FAR }
	local world = ServerFixtures.world()
	current = world
	local a = ServerFixtures.join(world, 1, nil, 1e12)
	local b = ServerFixtures.join(world, 2, nil, 1e12)
	a.data.rebirths, b.data.rebirths = 5, 5
	ServerFixtures.veteran(a)
	ServerFixtures.veteran(b)
	PvpService.join(world, a, T0, true)
	PvpService.join(world, b, T0, true)
	return world, a, b
end

local function done()
	PvpService.registerLine("Knockback", nil)
	PvpService.registerLine("Fun", nil)
end

local function kinds(): { string }
	local out = {}
	for _, e in events() do
		table.insert(out, e.payload.kind)
	end
	return out
end

describe("PvP remote definitions", function()
	it("declares PvpEvent as a server->client RemoteEvent", function()
		local def = Remotes.definition(Constants.PVP_EVENT)
		expect(def and def.class).toBe("RemoteEvent")
		expect(def and def.direction).toBe("ServerToClient")
	end)
	it("declares the action arguments and rate limits", function()
		expect(Remotes.ACTIONS.EquipPvpItem.args).toEqual({ "string?" })
		expect(Remotes.ACTIONS.UsePvpItem.args).toEqual({ "string", "number?", "vector3?", "boolean?" })
		expect(Validate.ACTIONS.BuyPvpItem).toBe(0.5)
		expect(Validate.ACTIONS.EquipPvpItem).toBe(0.5)
		expect(Validate.ACTIONS.UsePvpItem).toBe(0.2)
	end)
end)

describe("vector3 argument validation", function()
	local function parse(...: any)
		return Actions.parseArgs("UsePvpItem", { ... })
	end
	it("accepts nil target / aim and a finite Vector3", function()
		expect((parse("KnockGlove1"))).toEqual({ "KnockGlove1" })
		local v = roblox.Vector3.new(1, 2, 3)
		local args = parse("KnockGlove1", 7, v)
		expect(args and args[2]).toBe(7)
		expect(args and args[3] == v).toBe(true)
	end)
	it("rejects NaN, infinite and huge vectors, and non-vectors", function()
		for _, bad in
			{
				roblox.Vector3.new(0 / 0, 0, 0),
				roblox.Vector3.new(0, math.huge, 0),
				roblox.Vector3.new(0, 0, -math.huge),
				roblox.Vector3.new(1e9, 0, 0),
				{ X = 1, Y = 2, Z = 3 },
				"1,2,3",
				5,
				true,
			} :: { any }
		do
			local args, reason = parse("KnockGlove1", 7, bad)
			expect(args).toBeNil()
			expect(reason).toBe("bad argument")
		end
	end)
	it("rejects a bad target number", function()
		expect((parse("KnockGlove1", "x"))).toBeNil()
		expect((parse("KnockGlove1", 0 / 0))).toBeNil()
	end)
	it("accepts an optional charged flag and rejects a non-boolean one", function()
		local args = parse("KnockGlove1", 7, nil, true)
		expect(args and args[4]).toBe(true)
		expect((parse("KnockGlove1", 7, nil, "yes"))).toBeNil()
	end)
end)

describe("PvP equip / use with the flag off", function()
	it("refuses, creates no state, fires nothing and sends no State.pvp", function()
		local world = ServerFixtures.world()
		current = world
		local s = ServerFixtures.join(world, 1, nil, 1e12)
		PvpService.join(world, s, T0, false)
		local ok, reason = PvpService.equip(s, "KnockGlove1", false)
		expect(ok).toBe(false)
		expect(reason).toBe("PvP is not open yet")
		ok, reason = PvpService.use(world, s, "KnockGlove1", nil, nil, T0, false, env)
		expect(ok).toBe(false)
		expect(reason).toBe("PvP is not open yet")
		PvpService.tick(world, s, FAR, T0)
		PvpService.fireEffect(current, { attacker = 1, itemId = "KnockGlove1", effect = "Knockback" }, T0, false)
		PvpService.fireTrap(current, "TrapPlaced", { owner = 1 }, T0, false)
		expect(PvpService.state(s)).toBeNil()
		expect(PvpService.equipped(s)).toBeNil()
		expect(PvpService.view(s, T0)).toBeNil()
		expect(PvpService.spawnedCount(s)).toBe(0)
		expect(#events()).toBe(0)
		local r = Actions.handle(world, 1, "UsePvpItem", { "KnockGlove1" }, T0 + 5, {
			distanceBetween = ctx.distanceBetween,
			positionOf = ctx.positionOf,
			features = { PvP = false },
		})
		expect(r.ok).toBe(false)
		expect(r.message).toBe("PvP is not open yet")
		r = Actions.handle(world, 1, "EquipPvpItem", { "KnockGlove1" }, T0 + 6, {
			distanceBetween = ctx.distanceBetween,
			positionOf = ctx.positionOf,
			features = { PvP = false },
		})
		expect(r.message).toBe("PvP is not open yet")
	end)
end)

describe("PvpService.equip", function()
	it("needs an owned, known item; one equipped; nil unequips", function()
		local _, a = setup()
		expect(select(2, PvpService.equip(a, "Nope", true))).toBe("unknown item")
		expect(select(2, PvpService.equip(a, "KnockGlove1", true))).toBe("not owned")
		expect((PvpService.buy(ServerFixtures.world(), a, "KnockGlove1", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove1", true))).toBe(true)
		expect(PvpService.equipped(a)).toBe("KnockGlove1")
		expect((PvpService.buy(ServerFixtures.world(), a, "KnockGlove2", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove2", true))).toBe(true)
		expect(PvpService.equipped(a)).toBe("KnockGlove2")
		expect((PvpService.equip(a, nil, true))).toBe(true)
		expect(PvpService.equipped(a)).toBeNil()
		expect(PvpService.spawnedCount(a)).toBe(0)
		done()
	end)
end)

describe("PvpService.use", function()
	local function armed(): (any, any, any)
		local world, a, b = setup()
		expect((PvpService.buy(world, a, "KnockGlove1", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove1", true))).toBe(true)
		return world, a, b
	end
	local function use(world: any, a: any, target: number?, at: number): (boolean, string?)
		return PvpService.use(world, a, "KnockGlove1", target, nil, at, true, env)
	end

	it("must be equipped", function()
		local world, a = setup()
		expect((PvpService.buy(world, a, "KnockGlove1", true))).toBe(true)
		local ok, reason = use(world, a, 2, T0)
		expect(ok).toBe(false)
		expect(reason).toBe("not equipped")
		done()
	end)
	it("answers Coming soon for a line without a handler and starts no cooldown", function()
		local world, a = armed()
		ServerFixtures.clearEvents(current)
		local ok, reason = use(world, a, 2, T0 + 1)
		expect(ok).toBe(false)
		expect(reason).toBe("Coming soon")
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		expect(#events()).toBe(0)
		done()
	end)
	it("dispatches to the line handler, then marks the cooldown and fires the Cooldown event", function()
		local world, a = armed()
		local calls = 0
		PvpService.registerLine("Knockback", function(call)
			calls += 1
			expect(call.tool.id).toBe("KnockGlove1")
			expect(call.target and call.target.userId).toBe(2)
			return true, nil
		end)
		ServerFixtures.clearEvents(current)
		local ok = use(world, a, 2, T0 + 1)
		expect(ok).toBe(true)
		expect(calls).toBe(1)
		local cooldown = (PvpRules.tool("KnockGlove1") :: any).cooldown
		expect(#events()).toBe(1)
		expect(events()[1].target).toBe(1)
		expect(events()[1].payload).toEqual({
			kind = "Cooldown",
			itemId = "KnockGlove1",
			duration = math.max(cooldown, Config.PVP.MIN_COOLDOWN),
			startedAt = T0 + 1,
			serverTime = T0 + 1,
		})
		local again, reason = use(world, a, 2, T0 + 1.1)
		expect(again).toBe(false)
		expect(reason).toBe("not ready")
		expect(calls).toBe(1)
		expect((use(world, a, 2, T0 + 1 + cooldown + 1))).toBe(true)
		expect(calls).toBe(2)
		done()
	end)
	it("a refusing handler starts no cooldown and sends nothing", function()
		local world, a = armed()
		PvpService.registerLine("Knockback", function()
			return false, "out of reach"
		end)
		ServerFixtures.clearEvents(current)
		local ok, reason = use(world, a, 2, T0 + 1)
		expect(ok).toBe(false)
		expect(reason).toBe("out of reach")
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		expect(#events()).toBe(0)
		done()
	end)
	it("applies the shield and unknown-target rules before the handler, anywhere on the map", function()
		local world, a, b = armed()
		local calls = 0
		PvpService.registerLine("Knockback", function(call)
			calls += 1
			expect(call.charged).toBe(false)
			return true, nil
		end)
		expect(select(2, use(world, a, 99, T0 + 1))).toBe("no such player")
		expect(select(2, use(world, a, 1, T0 + 1))).toBe("can't target yourself")
		b.data.pvp.played = 0
		PvpService.join(world, b, T0, true)
		expect(select(2, use(world, a, 2, T0 + 1))).toBe("target is shielded")
		expect(calls).toBe(0)
		ServerFixtures.veteran(b)
		PvpService.join(world, b, T0, true)
		positions[1], positions[2] = { X = 0, Y = 3, Z = 0 }, { X = 1, Y = 3, Z = 1 } -- the old fountain zone
		expect((PvpService.use(world, a, "KnockGlove1", 2, nil, T0 + 1, true, { positionOf = env.positionOf }))).toBe(
			true
		)
		expect(calls).toBe(1)
		done()
	end)
	it("a handler may choose the cooldown, or start none", function()
		local world, a = armed()
		local length: number? = 0
		PvpService.registerLine("Knockback", function(call)
			expect(call.charged).toBe(true)
			return true, nil, length
		end)
		ServerFixtures.clearEvents(current)
		expect((PvpService.use(world, a, "KnockGlove1", 2, nil, T0 + 1, true, env, true))).toBe(true)
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		expect(#events()).toBe(0)
		length = 4
		expect((PvpService.use(world, a, "KnockGlove1", 2, nil, T0 + 2, true, env, true))).toBe(true)
		expect(PvpService.state(a).cooldowns.KnockGlove1).toBe(T0 + 6)
		done()
	end)
	it("the UsePvpItem / EquipPvpItem actions reach the service", function()
		local world, a = armed()
		PvpService.registerLine("Knockback", function()
			return true, nil
		end)
		expect(Actions.handle(world, 1, "EquipPvpItem", { "KnockGlove1" }, T0 + 10, ctx).ok).toBe(true)
		local r =
			Actions.handle(world, 1, "UsePvpItem", { "KnockGlove1", 2, roblox.Vector3.new(1, 2, 3) }, T0 + 11, ctx)
		expect(r.ok).toBe(true)
		r = Actions.handle(world, 1, "UsePvpItem", { "KnockGlove1", 2 }, T0 + 11.05, ctx)
		expect(r.message).toBe("too fast") -- 0.2 s rate limit
		r = Actions.handle(world, 1, "UsePvpItem", { "KnockGlove1", 2, roblox.Vector3.new(0 / 0, 0, 0) }, T0 + 12, ctx)
		expect(r.message).toBe("bad argument")
		expect(a.dirty).toBe(true)
		done()
	end)
end)

describe("PvpService events", function()
	it("sends Shield changes from the per-player tick", function()
		local _, a = setup()
		a.data.pvp.played = 0
		PvpService.join(current, a, T0, true) -- a fresh player: shielded
		PvpService.tick(current, a, FAR, T0 + 1)
		expect(kinds()).toEqual({ "Shield" })
		expect(events()[1].payload.endsAt).toBe(T0 + Config.PVP.NEW_PLAYER_SHIELD_SECONDS)
		expect(events()[1].target).toBe(1)
		PvpService.tick(current, a, { X = 1, Y = 3, Z = 1 }, T0 + 2)
		expect(#events()).toBe(1) -- unchanged: nothing re-sent, and no zone events exist
		PvpService.tick(current, a, FAR, T0 + Config.PVP.NEW_PLAYER_SHIELD_SECONDS)
		expect(events()[2].payload.kind).toBe("Shield")
		expect(events()[2].payload.endsAt).toBeNil()
		expect(events()[2].payload.serverTime).toBe(T0 + Config.PVP.NEW_PLAYER_SHIELD_SECONDS)
		done()
	end)
	it("fireEffect and fireTrap go to every client with serverTime", function()
		setup()
		PvpService.fireEffect(
			current,
			{ attacker = 1, target = 2, itemId = "KnockGlove1", effect = "Knockback", push = 8 },
			T0 + 3,
			true
		)
		PvpService.fireTrap(
			current,
			"TrapPlaced",
			{ owner = 1, trapId = "t1", itemId = "GooTrap1", position = FAR },
			T0 + 4,
			true
		)
		PvpService.fireTrap(
			current,
			"TrapCleared",
			{ owner = 1, trapId = "t1", itemId = "GooTrap1", position = FAR },
			T0 + 5,
			true
		)
		expect(kinds()).toEqual({ "Effect", "TrapPlaced", "TrapCleared" })
		for _, e in events() do
			expect(e.target).toBeNil()
		end
		expect(events()[1].payload.effect).toBe("Knockback")
		expect(events()[1].payload.serverTime).toBe(T0 + 3)
		expect(events()[2].payload.trapId).toBe("t1")
		done()
	end)
end)

describe("State.pvp", function()
	it("is absent with the flag off", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		PvpService.join(world, s, T0, false)
		expect((Snapshot.build(world, s, T0) :: any).pvp).toBeNil()
	end)
	it("has the contract shape when on", function()
		local world, a = setup()
		expect((PvpService.buy(world, a, "KnockGlove2", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove2", true))).toBe(true)
		PvpService.registerLine("Knockback", function()
			return true, nil
		end)
		expect(PvpService.use(world, a, "KnockGlove2", 2, nil, T0 + 1, true, env)).toBe(true)
		PvpService.tick(current, a, FAR, T0 + 2)
		expect((PvpService.buy(world, a, "GooTrap1", true))).toBe(true) -- one trap charge
		local pvp = (Snapshot.build(world, a, T0 + 2) :: any).pvp
		expect(pvp.rank).toBe(5)
		expect(pvp.owned.KnockGlove2).toBe(true)
		expect(pvp.owned.KnockGlove1).toBe(true) -- superseded tiers count as owned
		expect(pvp.best).toEqual({ Knockback = "KnockGlove2", Trap = "GooTrap1" })
		expect(pvp.equipped).toBe("KnockGlove2")
		expect(pvp.cooldowns.KnockGlove2).toBe(PvpService.state(a).cooldowns.KnockGlove2)
		expect(pvp.shieldUntil).toBe(nil) -- a veteran has no shield
		expect(pvp.charges).toEqual({ GooTrap1 = 1 })
		expect(pvp.owned.GooTrap1).toBe(true)
		expect(PvpRules.tool("KnockGlove2") ~= nil).toBe(true)
		done()
	end)
	it("drops spawned parts on leave", function()
		local _, a = setup()
		local destroyed = 0
		PvpService.track(a, {
			Destroy = function()
				destroyed += 1
			end,
		})
		expect(PvpService.spawnedCount(a)).toBe(1)
		PvpService.leave(current, a, T0 + 5)
		expect(destroyed).toBe(1)
		expect(PvpService.spawnedCount(a)).toBe(0)
		done()
	end)
end)
