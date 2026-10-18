--!strict
-- The Knockback glove line (FEATURES.PvP, CONTRACT.md §26): reach, canTarget matrix, cooldown, control immunity,
-- push clamp / map bounds per tier, thief drop, flag-off refusal, nothing spawned. Every flag-dependent call passes the
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
local ATTACKER = { X = 200, Y = 3, Z = -200 } -- clear of every safe zone
local FOUNTAIN = { X = 1, Y = 3, Z = 1 }
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

local function use(world: any, a: any, id: string?, at: number): (boolean, string?)
	return PvpService.use(world, a, id or "KnockGlove1", 2, nil, at, true, env)
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
	it("pushes away from the attacker by the tier's push, with a small arc", function()
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
	it("applies the canTarget matrix", function()
		local world, a, b = setup()
		positions[2] = FOUNTAIN
		positions[1] = { X = 3, Y = 3, Z = 1 }
		expect(select(2, use(world, a, nil, T0 + 1))).toBe("safe zone")
		positions[1] = ATTACKER
		expect(select(2, use(world, a, nil, T0 + 1))).toBe("target is in a safe zone")
		positions[2] = { X = 205, Y = 3, Z = -200 }
		b.data.rebirths = 0
		PvpService.join(world, b, T0, true) -- a fresh player: shielded
		expect(select(2, use(world, a, nil, T0 + 1))).toBe("target is shielded")
		b.data.rebirths = 20
		plot = false
		expect(select(2, use(world, a, nil, T0 + 1))).toBe("only on your plot or against a thief")
		plot = true
		expect(#moves).toBe(0)
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		expect(use(world, a, nil, T0 + 2)).toBe(true) -- all clear
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
	it("makes a thief drop the stolen slime like the base slap", function()
		local world = ServerFixtures.world()
		current = world
		moves, plot = {}, false
		env.launch = record
		positions = { [1] = ATTACKER, [2] = { X = 205, Y = 3, Z = -200 } }
		PvpKnockback.register()
		local a = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) }, 1e12)
		local thief = ServerFixtures.join(world, 2, nil, 1e12)
		a.data.rebirths, thief.data.rebirths = 20, 20
		ServerFixtures.unlock(a)
		ServerFixtures.unlock(thief)
		PvpService.join(world, a, T0, true)
		PvpService.join(world, thief, T0, true)
		expect((PvpService.buy(world, a, "KnockGlove1", true))).toBe(true)
		expect((PvpService.equip(a, "KnockGlove1", true))).toBe(true)
		expect((StealService.steal(world, thief, "gem", 1, T0 + 101))).toBe(true)
		expect(thief.carry ~= nil).toBe(true)
		expect(use(world, a, nil, T0 + 102)).toBe(true) -- not on the plot, but a thief carrying a slime
		expect(thief.carry).toBeNil()
		expect(world.carriedBy.gem).toBeNil()
		expect(world.escaping.gem ~= nil).toBe(true)
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
