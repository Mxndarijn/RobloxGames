--!strict
-- The Knockback glove line (FEATURES.PvP, CONTRACT.md §26.4): reach, the shield rules, cooldown, control immunity,
-- push clamp / map bounds per tier, the power punch, the specials, caught thieves, flag-off refusal, nothing spawned. Every flag-dependent call passes the
-- flag explicitly so the specs hold in the forced-flag runs too.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PvpKnockback = require("../src/server/PvpKnockback")
local PvpKnockbackRules = require("../src/shared/PvpKnockbackRules")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local ServerFixtures = require("./ServerFixtures")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local ATTACKER = { X = 200, Y = 3, Z = -200 }
local TIERS = { "KnockGlove1", "KnockGlove2", "KnockGlove3", "KnockGlove4", "KnockGlove5" }

local current: any = nil -- the world of the running test
local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end
local positions: { [number]: any } = {}
local moves: { { userId: number, push: any, landing: any } } = {}
local plot = true
local function record(userId: number, push: any, landing: any?): boolean
	table.insert(moves, { userId = userId, push = push, landing = landing })
	return true
end
local env: PvpService.Context = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
	onOwnPlot = function(): boolean
		return plot
	end,
	launch = record,
}

local function setup(tier: string?): (any, any, any)
	moves, plot = {}, true
	env.launch = record
	positions = { [1] = ATTACKER, [2] = { X = 205, Y = 3, Z = -200 } }
	PvpKnockback.register()
	local world = ServerFixtures.world()
	current = world
	local a = ServerFixtures.join(world, 1, nil, 1e12)
	local b = ServerFixtures.join(world, 2, nil, 1e12)
	a.data.rebirths, b.data.rebirths = 20, 20
	ServerFixtures.veteran(a)
	ServerFixtures.veteran(b)
	PvpService.join(world, a, T0, true)
	PvpService.join(world, b, T0, true)
	for _, id in TIERS do
		expect((PvpService.buy(world, a, id, true))).toBe(true)
		if id == (tier or "KnockGlove1") then
			break
		end
	end
	expect((PvpService.equip(a, tier or "KnockGlove1", true))).toBe(true)
	return world, a, b
end

local function done()
	PvpService.registerLine("Knockback", nil)
end

local function use(world: any, a: any, id: string?, at: number, charged: boolean?, target: number?): (boolean, string?)
	return PvpService.use(world, a, id or "KnockGlove1", target or 2, nil, at, true, env, charged)
end

-- A third player at `position` (a veteran, so not shielded).
local function third(world: any, position: any): any
	local c = ServerFixtures.join(world, 3, nil, 0)
	ServerFixtures.veteran(c)
	PvpService.join(world, c, T0, true)
	positions[3] = position
	return c
end

local function knockEffects(): { { [string]: any } }
	local out = {}
	for _, e in events() do
		if e.payload.kind == "Effect" and e.payload.effect == "Knockback" then
			table.insert(out, e.payload)
		end
	end
	return out
end

describe("Knockback geometry", function()
	it("reach defaults to the slap reach and checks 3D distance", function()
		local tool = PvpRules.tool("KnockGlove1") :: any
		expect(PvpKnockbackRules.reach(tool)).toBe(10)
		expect(PvpKnockbackRules.reach({ id = "x" } :: any)).toBe(Config.SLAP_REACH)
		expect(PvpKnockbackRules.inReach(tool, ATTACKER, { X = 210, Y = 3, Z = -200 })).toBe(true)
		expect(PvpKnockbackRules.inReach(tool, ATTACKER, { X = 210.1, Y = 3, Z = -200 })).toBe(false)
		expect(PvpKnockbackRules.inReach(tool, ATTACKER, { X = 200, Y = 14, Z = -200 })).toBe(false)
	end)
	it("pushes away from the attacker by the tier's push, with the tier's arc", function()
		for _, id in TIERS do
			local tool = PvpRules.tool(id) :: any
			local landing, push = PvpKnockbackRules.plan(tool, ATTACKER, { X = 205, Y = 3, Z = -200 })
			expect(
				math.abs(PvpKnockbackRules.horizontal(push) - math.min(tool.push, Config.PVP.KNOCKBACK_MAX_PUSH)) < 1e-9
			).toBe(true)
			expect(push.X > 0).toBe(true)
			expect(math.abs(push.Z) < 1e-9).toBe(true)
			expect(push.Y >= 0 and push.Y <= Config.PVP.KNOCKBACK_ARC_HEIGHT).toBe(true)
			expect(math.abs(landing.X - (205 + tool.push)) < 1e-9).toBe(true)
		end
	end)
	it("keeps the landing inside the map minus the margin, per tier", function()
		local box = Config.PVP.MAP_BOUNDS
		local limit = box.maxX - Config.PVP.KNOCKBACK_BOUNDS_MARGIN
		for _, id in TIERS do
			local tool = PvpRules.tool(id) :: any
			local landing, push = PvpKnockbackRules.plan(tool, { X = 300, Y = 3, Z = 0 }, { X = 310, Y = 3, Z = 0 })
			expect(landing.X <= limit).toBe(true)
			expect(landing.X >= box.minX + Config.PVP.KNOCKBACK_BOUNDS_MARGIN).toBe(true)
			expect(math.abs(landing.X - 310 - push.X) < 1e-9).toBe(true) -- the applied push matches the landing
			local corner = PvpKnockbackRules.plan(tool, { X = 300, Y = 3, Z = 300 }, { X = 310, Y = 3, Z = 310 })
			expect(corner.X <= limit and corner.Z <= limit).toBe(true)
		end
	end)
	it("a coincident target is pushed along +Z; the launch velocity covers the push in KNOCKBACK_SECONDS", function()
		local tool = PvpRules.tool("KnockGlove3") :: any
		local _, push = PvpKnockbackRules.plan(tool, ATTACKER, ATTACKER)
		expect(math.abs(push.Z - 7) < 1e-9 and math.abs(push.X) < 1e-9).toBe(true)
		local v = PvpKnockbackRules.velocity(push, 196.2)
		expect(math.abs(v.Z * Config.PVP.KNOCKBACK_SECONDS / Config.PVP.KNOCKBACK_FRICTION_BOOST - push.Z) < 1e-9).toBe(
			true
		)
		expect(v.Y > 0).toBe(true)
	end)
end)

describe("Knockback use", function()
	it("pushes the target, fires the Effect event to everyone and the Cooldown to the attacker", function()
		local world, a, b = setup()
		expect(use(world, a, nil, T0 + 1)).toBe(true)
		expect(#moves).toBe(1)
		expect(moves[1].userId).toBe(2)
		expect(math.abs(moves[1].push.X - 5) < 1e-9).toBe(true)
		expect(events()[1].target).toBeNil()
		local e = events()[1].payload
		expect(e.kind).toBe("Effect")
		expect(e.effect).toBe("Knockback")
		expect(e.attacker).toBe(1)
		expect(e.target).toBe(2)
		expect(e.itemId).toBe("KnockGlove1")
		expect(math.abs(e.push - 5) < 1e-9).toBe(true)
		expect(e.duration).toBe(Config.PVP.FX_SECONDS)
		expect(e.velocity).toEqual(PvpKnockbackRules.velocity(moves[1].push)) -- the victim's client applies the same push
		expect(e.position).toEqual(positions[2])
		expect(events()[2].payload.kind).toBe("Cooldown")
		expect(events()[2].target).toBe(1)
		-- control bookkeeping, no health, nothing spawned
		expect((PvpService.state(b) :: any).controlUntil).toBe(T0 + 1 + Config.PVP.KNOCKBACK_CONTROL_SECONDS)
		expect(PvpService.spawnedCount(a)).toBe(0)
		expect(PvpService.spawnedCount(b)).toBe(0)
		done()
	end)
	it("every tier pushes its own distance", function()
		for _, id in TIERS do
			local world, a = setup(id)
			expect(use(world, a, id, T0 + 1)).toBe(true)
			local tool = PvpRules.tool(id) :: any
			expect(math.abs(PvpKnockbackRules.horizontal(moves[1].push) - tool.push) < 1e-9).toBe(true)
			done()
		end
	end)
	it("refuses out of reach without a cooldown, a push or an event", function()
		local world, a = setup()
		positions[2] = { X = 212, Y = 3, Z = -200 }
		local ok, reason = use(world, a, nil, T0 + 1)
		expect(ok).toBe(false)
		expect(reason).toBe("too far away")
		expect(#moves).toBe(0)
		expect(#events()).toBe(0)
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		done()
	end)
	it("works on anyone anywhere, but never on or by a shielded player", function()
		local world, a, b = setup()
		plot = false -- off the attacker's plot, a player who carries nothing
		positions[1], positions[2] = { X = 0, Y = 3, Z = 0 }, { X = 3, Y = 3, Z = 1 } -- by the fountain
		expect(use(world, a, nil, T0 + 1)).toBe(true)
		b.data.pvp.played = 0
		PvpService.join(world, b, T0, true) -- a fresh player: shielded
		expect(select(2, use(world, a, nil, T0 + 5))).toBe("target is shielded")
		ServerFixtures.veteran(b)
		PvpService.join(world, b, T0, true)
		a.data.pvp.played = 0
		PvpService.join(world, a, T0, true)
		expect((PvpService.equip(a, "KnockGlove1", true))).toBe(true)
		expect(select(2, use(world, a, nil, T0 + 5))).toBe("your new-player shield is on")
		expect(#moves).toBe(1)
		done()
	end)
	it("a power punch pushes 1.5x and doubles the cooldown", function()
		local world, a = setup()
		expect(use(world, a, nil, T0 + 1, true)).toBe(true)
		expect(math.abs(PvpKnockbackRules.horizontal(moves[1].push) - 5 * Config.PVP.CHARGE_PUSH) < 1e-9).toBe(true)
		expect(knockEffects()[1].charged).toBe(true)
		expect(PvpService.state(a).cooldowns.KnockGlove1).toBe(T0 + 1 + 1.5 * Config.PVP.CHARGE_COOLDOWN)
		done()
	end)
	it("the Royal power punch stays inside the push and arc caps", function()
		local world, a = setup("KnockGlove5")
		expect(use(world, a, "KnockGlove5", T0 + 1, true)).toBe(true)
		local push = moves[1].push
		expect(PvpKnockbackRules.horizontal(push) <= Config.PVP.KNOCKBACK_MAX_PUSH + 1e-9).toBe(true)
		expect(push.Y).toBe(6)
		expect(knockEffects()[1].special).toBe("royal")
		done()
	end)
	it("Bounce: the effect carries the pogo heights and the first bounce is the arc", function()
		local world, a = setup("KnockGlove2")
		expect(use(world, a, "KnockGlove2", T0 + 1)).toBe(true)
		local e = knockEffects()[1]
		expect(e.special).toBe("bounce")
		expect(e.pogo).toEqual({ 6, 4, 2 })
		expect(moves[1].push.Y).toBe(6)
		done()
	end)
	it("Boom: the blast also pushes everyone within 5 studs of the target, away from it", function()
		local world, a = setup("KnockGlove3")
		third(world, { X = 208, Y = 3, Z = -200 }) -- 3 studs past the target
		expect(use(world, a, "KnockGlove3", T0 + 1)).toBe(true)
		expect(#moves).toBe(2)
		expect(moves[2].userId).toBe(3)
		expect(moves[2].push.X > 0).toBe(true)
		local chained = knockEffects()[2]
		expect(chained.chained).toBe(true)
		expect(chained.target).toBe(3)
		positions[3] = { X = 220, Y = 3, Z = -200 } -- too far for the blast
		done()
	end)
	it("Thunder: lightning chains to at most 2 nearby players at half push", function()
		local world, a = setup("KnockGlove4")
		third(world, { X = 210, Y = 3, Z = -200 })
		local d = ServerFixtures.join(world, 4, nil, 0)
		ServerFixtures.veteran(d)
		PvpService.join(world, d, T0, true)
		positions[4] = { X = 205, Y = 3, Z = -195 }
		local e = ServerFixtures.join(world, 5, nil, 0)
		ServerFixtures.veteran(e)
		PvpService.join(world, e, T0, true)
		positions[5] = { X = 205, Y = 3, Z = -190 }
		expect(use(world, a, "KnockGlove4", T0 + 1)).toBe(true)
		expect(#moves).toBe(3) -- the target + 2 chained
		for i = 2, 3 do
			expect(math.abs(PvpKnockbackRules.horizontal(moves[i].push) - 7.5 * 0.5) < 1e-9).toBe(true)
		end
		done()
	end)
	it("honours the cooldown and starts none on a refusal", function()
		local world, a = setup()
		expect(use(world, a, nil, T0 + 1)).toBe(true)
		local ok, reason = use(world, a, nil, T0 + 1.2)
		expect(ok).toBe(false)
		expect(reason).toBe("not ready")
		expect(#moves).toBe(1)
		expect(use(world, a, nil, T0 + 1 + Config.PVP.MIN_COOLDOWN + 0.1)).toBe(false) -- target still immune
		done()
	end)
	it("a target under control or immunity gets no push and the use starts no cooldown", function()
		local world, a, b = setup()
		expect(use(world, a, nil, T0 + 1)).toBe(true)
		local lastPush = #moves
		local readyAt = T0 + 1 + 2
		local ok, reason = use(world, a, nil, readyAt) -- cooldown over, immunity still running
		expect(ok).toBe(false)
		expect(reason).toBe("target is immune")
		expect(#moves).toBe(lastPush)
		expect(PvpService.state(a).cooldowns.KnockGlove1 <= T0 + 1 + 1.5 + 1e-9).toBe(true)
		local immuneEnd = (PvpService.state(b) :: any).immuneUntil
		expect(immuneEnd - (T0 + 1) <= Config.PVP.CONTROL_MAX_SECONDS + Config.PVP.CONTROL_IMMUNITY_SECONDS).toBe(true)
		expect(use(world, a, nil, immuneEnd + 0.01)).toBe(true)
		expect(#moves).toBe(lastPush + 1)
		done()
	end)
	it("a missing mover or a mover failure refuses without a cooldown", function()
		local world, a = setup()
		env.launch = nil
		expect(select(2, use(world, a, nil, T0 + 1))).toBe("can't push right now")
		env.launch = function()
			return false
		end
		expect(use(world, a, nil, T0 + 1)).toBe(false)
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		expect(#events()).toBe(0)
		done()
	end)
	it("a punched thief always sends the slime home, also when immune to the push", function()
		local world = ServerFixtures.world()
		current = world
		moves, plot = {}, false
		env.launch = record
		positions = { [1] = ATTACKER, [2] = { X = 205, Y = 3, Z = -200 } }
		PvpKnockback.register()
		local a = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3), Fixtures.slime("ruby", 3) }, 1e12)
		local thief = ServerFixtures.join(world, 2, nil, 1e12)
		a.data.rebirths, thief.data.rebirths = 20, 20
		ServerFixtures.unlock(a)
		ServerFixtures.unlock(thief)
		ServerFixtures.veteran(a)
		PvpService.join(world, a, T0, true)
		PvpService.join(world, thief, T0, true)
		expect((PvpService.buy(world, a, "KnockGlove1", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove1", true))).toBe(true)
		expect((StealService.steal(world, thief, "gem", 1, T0 + 101))).toBe(true)
		PvpService.onSteal(thief, T0 + 101)
		expect(use(world, a, nil, T0 + 102)).toBe(true)
		expect(thief.carry).toBeNil()
		expect(world.carriedBy.gem).toBeNil()
		expect(world.escaping.gem ~= nil).toBe(true)
		expect(#moves).toBe(1)
		-- immune now: a second steal and punch still sends the slime home, without a push
		world.escaping.gem = nil
		expect((StealService.steal(world, thief, "ruby", 1, T0 + 103.6))).toBe(true)
		expect(use(world, a, nil, T0 + 103.6)).toBe(true)
		expect(thief.carry).toBeNil()
		expect(#moves).toBe(1)
		done()
	end)
	it("is refused with the flag off: no push, no event, no state", function()
		local world, a = setup()
		ServerFixtures.clearEvents(current)
		local ok, reason = PvpService.use(world, a, "KnockGlove1", 2, nil, T0 + 1, false, env)
		expect(ok).toBe(false)
		expect(reason).toBe("PvP is not open yet")
		expect(#moves).toBe(0)
		expect(#events()).toBe(0)
		done()
	end)
end)
