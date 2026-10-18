--!strict
-- The Goo Blaster line (FEATURES.PvP, CONTRACT.md §26): hitscan hit / miss / range / first hit, canTarget, slow clamp +
-- immunity + walk speed restore, cooldown on a miss vs a refusal, flag-off refusal, nothing spawned. Every
-- flag-dependent call passes the flag explicitly so the specs hold in the forced-flag runs too.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local PvpBlaster = require("../src/server/PvpBlaster")
local PvpBlasterRules = require("../src/shared/PvpBlasterRules")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local ORIGIN = { X = 200, Y = 3, Z = -200 } -- clear of every safe zone
local FOUNTAIN = { X = 1, Y = 3, Z = 1 }
local TIERS = { "GooBlaster1", "GooBlaster2", "GooBlaster3" }

local current: any = nil -- the world of the running test
local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end
local positions: { [number]: any } = {}
local plot = true
local env = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
	onOwnPlot = function(): boolean
		return plot
	end,
}

local function setup(tier: string?): (any, any, any, any)
	plot = true
	positions = {
		[1] = ORIGIN,
		[2] = { X = 220, Y = 3, Z = -200 },
		[3] = { X = 230, Y = 3, Z = -200 },
	}
	PvpBlaster.register()
	local world = ServerFixtures.world()
	current = world
	local a = ServerFixtures.join(world, 1, nil, 1e12)
	local b = ServerFixtures.join(world, 2, nil, 1e12)
	local c = ServerFixtures.join(world, 3, nil, 1e12)
	a.data.rebirths, b.data.rebirths, c.data.rebirths = 20, 20, 20
	for _, s in { a, b, c } do
		PvpService.join(world, s, T0, true)
	end
	for _, id in TIERS do
		expect((PvpService.buy(world, a, id, true))).toBe(true)
		if id == (tier or "GooBlaster1") then
			break
		end
	end
	expect((PvpService.equip(a, tier or "GooBlaster1", true))).toBe(true)
	return world, a, b, c
end

local function done()
	PvpService.registerLine("Blaster", nil)
end

local function fire(world: any, a: any, aim: any, at: number, id: string?): (boolean, string?)
	return PvpService.use(world, a, id or "GooBlaster1", nil, aim, at, true, env)
end

local EAST = { X = 300, Y = 3, Z = -200 }

describe("Blaster geometry", function()
	it("ranges per tier and unit direction", function()
		expect(PvpBlasterRules.range(PvpRules.tool("GooBlaster1") :: any)).toBe(40)
		expect(PvpBlasterRules.range(PvpRules.tool("GooBlaster2") :: any)).toBe(45)
		expect(PvpBlasterRules.range(PvpRules.tool("GooBlaster3") :: any)).toBe(50)
		local dir = PvpBlasterRules.direction(ORIGIN, EAST) :: any
		expect(dir.X).toBe(1)
		expect(PvpBlasterRules.direction(ORIGIN, ORIGIN)).toBeNil()
		expect(PvpBlasterRules.direction(ORIGIN, { X = 0 / 0, Y = 0, Z = 0 })).toBeNil()
	end)
	it("hits within the radius of the segment, misses outside it", function()
		local dir = PvpBlasterRules.direction(ORIGIN, EAST) :: any
		local function hit(p: any): boolean
			return PvpBlasterRules.firstHit(ORIGIN, dir, 40, { { id = 9, position = p } }) ~= nil
		end
		expect(hit({ X = 220, Y = 3, Z = -200 })).toBe(true)
		expect(hit({ X = 220, Y = 3, Z = -197.5 })).toBe(true)
		expect(hit({ X = 220, Y = 3, Z = -196 })).toBe(false)
		expect(hit({ X = 220, Y = 7, Z = -200 })).toBe(false)
		expect(hit({ X = 180, Y = 3, Z = -200 })).toBe(false) -- behind the attacker
	end)
	it("range is a hard limit and the nearest player along the ray wins", function()
		local dir = PvpBlasterRules.direction(ORIGIN, EAST) :: any
		expect(PvpBlasterRules.firstHit(ORIGIN, dir, 40, { { id = 1, position = { X = 245, Y = 3, Z = -200 } } })).toBeNil()
		local first = PvpBlasterRules.firstHit(ORIGIN, dir, 50, {
			{ id = 5, position = { X = 235, Y = 3, Z = -200 } },
			{ id = 6, position = { X = 215, Y = 3, Z = -201 } },
		}) :: any
		expect(first.id).toBe(6)
		local e = PvpBlasterRules.endPoint(ORIGIN, dir, 40)
		expect(e.X).toBe(240)
	end)
	it("slow factor per tier is 1 - slow, clamped", function()
		expect(math.abs(PvpBlasterRules.slowFactor(PvpRules.tool("GooBlaster3") :: any) - 0.5) < 1e-9).toBe(true)
		expect(PvpBlasterRules.slowFactor({ slow = 5 } :: any) > 0).toBe(true)
		expect(PvpBlasterRules.slowFactor({ slow = -1 } :: any)).toBe(1)
		expect(PvpBlasterRules.factorAt(0.5, 10, 11)).toBe(1)
	end)
end)

describe("Blaster use", function()
	it("slows the first player hit, fires Effect to everyone and Cooldown to the attacker", function()
		local world, a, b, c = setup()
		expect(fire(world, a, EAST, T0 + 1)).toBe(true)
		local e = events()[1].payload
		expect(events()[1].target).toBeNil()
		expect(e.kind).toBe("Effect")
		expect(e.effect).toBe("Slow")
		expect(e.attacker).toBe(1)
		expect(e.target).toBe(2) -- player 2 stands in front of player 3
		expect(e.itemId).toBe("GooBlaster1")
		expect(e.duration).toBe(2)
		expect(e.position).toEqual(positions[2])
		expect(events()[2].payload.kind).toBe("Cooldown")
		expect(events()[2].target).toBe(1)
		expect(Carry.targetWalkSpeed(b, T0 + 1.5) < Config.BASE_WALK_SPEED).toBe(true)
		expect(Carry.targetWalkSpeed(c, T0 + 1.5)).toBe(Config.BASE_WALK_SPEED)
		expect(PvpService.spawnedCount(a)).toBe(0)
		expect(PvpService.spawnedCount(b)).toBe(0)
		done()
	end)
	it("every tier slows by its percent for its seconds (clamped to SLOW_MAX_SECONDS) and then restores", function()
		for _, id in TIERS do
			local world, a, b = setup(id)
			local tool = PvpRules.tool(id) :: any
			expect(fire(world, a, EAST, T0 + 1, id)).toBe(true)
			local base = Config.BASE_WALK_SPEED
			local slowed = Carry.targetWalkSpeed(b, T0 + 1.01)
			expect(math.abs(slowed - Config.BASE_WALK_SPEED * (1 - tool.slow)) < 1e-9).toBe(true)
			local seconds = math.min(tool.slowSeconds, Config.PVP.SLOW_MAX_SECONDS)
			expect(events()[1].payload.duration).toBe(seconds)
			expect(Carry.targetWalkSpeed(b, T0 + 1 + seconds - 0.01) < base).toBe(true)
			expect(Carry.targetWalkSpeed(b, T0 + 1 + seconds)).toBe(base)
			expect(Carry.targetWalkSpeed(b, T0 + 1.5)).toBe(base) -- expired for good
			done()
		end
	end)
	it("the slow stacks on the carry slowdown and never stuns or damages", function()
		local world, a, b = setup()
		expect(fire(world, a, EAST, T0 + 1)).toBe(true)
		expect(Carry.targetWalkSpeed(b, T0 + 1.5) > 0).toBe(true)
		for _, id in TIERS do
			local tool = PvpRules.tool(id) :: any
			expect(tool.damage).toBeNil()
			expect(tool.control).toBeNil()
		end
		done()
	end)
	it("immunity after the slow: a second hit is a spent miss, no new slow", function()
		local world, a, b = setup()
		expect(fire(world, a, EAST, T0 + 1)).toBe(true)
		local immuneUntil = (PvpService.state(b) :: any).immuneUntil
		expect(immuneUntil).toBe(T0 + 1 + 2 + Config.PVP.CONTROL_IMMUNITY_SECONDS)
		-- cooldown over (12 s) and immunity over: slowable again
		expect(fire(world, a, EAST, T0 + 1 + 12)).toBe(true)
		expect(events()[#events() - 1].payload.target).toBe(2)
		done()
	end)
	it("a miss spends the cooldown and fires Effect with no target at the end of the ray", function()
		local world, a = setup()
		positions[2] = { X = 220, Y = 3, Z = -150 }
		positions[3] = { X = 250, Y = 3, Z = -200 } -- beyond the 40 stud range
		expect(fire(world, a, EAST, T0 + 1)).toBe(true)
		local e = events()[1].payload
		expect(e.effect).toBe("Slow")
		expect(e.target).toBeNil()
		expect(e.position).toEqual({ X = 240, Y = 3, Z = -200 })
		expect(e.duration).toBe(PvpBlasterRules.MISS_FX_SECONDS)
		local ok, reason = fire(world, a, EAST, T0 + 2)
		expect(ok).toBe(false)
		expect(reason).toBe("not ready")
		expect(fire(world, a, EAST, T0 + 1 + 12)).toBe(true)
		done()
	end)
	it("range is measured from the attacker's server position: a far target given by id is a miss", function()
		local world, a = setup()
		positions[2] = { X = 220, Y = 3, Z = -150 } -- off the line
		-- on the line, 1 stud past the 40 stud range plus the hit radius (the shot is a capsule)
		positions[3] = { X = 200 + 40 + PvpBlasterRules.HIT_RADIUS + 1, Y = 3, Z = -200 }
		expect(PvpService.use(world, a, "GooBlaster1", 3, nil, T0 + 1, true, env)).toBe(true)
		local e = events()[1].payload
		expect(e.target).toBeNil()
		expect(e.position).toEqual({ X = 240, Y = 3, Z = -200 })
		expect(PvpBlaster.walkFactor(world.sessions[3], T0 + 1)).toBe(1)
		done()
	end)
	it("a far aim point never extends the shot past the tier's range", function()
		local world, a = setup()
		positions[2] = { X = 220, Y = 3, Z = -150 }
		positions[3] = { X = 260, Y = 3, Z = -200 }
		expect(fire(world, a, { X = 99999, Y = 3, Z = -200 }, T0 + 1)).toBe(true)
		expect(events()[1].payload.target).toBeNil()
		expect(events()[1].payload.position).toEqual({ X = 240, Y = 3, Z = -200 })
		done()
	end)
	it("a target may be given instead of an aim", function()
		local world, a = setup()
		expect(PvpService.use(world, a, "GooBlaster1", 3, nil, T0 + 1, true, env)).toBe(true)
		expect(events()[1].payload.target).toBe(2) -- still the first hit on the way to player 3
		done()
	end)
	it("refusals start no cooldown: no aim, bad aim, not equipped, safe zone, flag off", function()
		local world, a = setup()
		expect(select(2, fire(world, a, nil, T0 + 1))).toBe("no aim")
		expect(select(2, fire(world, a, ORIGIN, T0 + 1))).toBe("bad aim")
		expect(select(2, PvpService.use(world, a, "GooBlaster2", nil, EAST, T0 + 1, true, env))).toBe("not equipped")
		positions[1] = FOUNTAIN
		expect(select(2, fire(world, a, EAST, T0 + 1))).toBe("safe zone")
		positions[1] = ORIGIN
		expect(select(2, PvpService.use(world, a, "GooBlaster1", nil, EAST, T0 + 1, false, env))).toBe(
			"PvP is not open yet"
		)
		expect(#events()).toBe(0)
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		expect(fire(world, a, EAST, T0 + 1)).toBe(true)
		done()
	end)
	it("players that fail canTarget are shot through: shielded, safe zone, other plot without a thief", function()
		local world, a, b, c = setup()
		b.data.rebirths = 0
		PvpService.join(world, b, T0, true) -- fresh and shielded
		expect(fire(world, a, EAST, T0 + 1)).toBe(true)
		expect(events()[1].payload.target).toBe(3)
		b.data.rebirths = 20
		PvpService.join(world, b, T0, true)
		plot = false
		ServerFixtures.clearEvents(current)
		expect(fire(world, a, EAST, T0 + 13)).toBe(true)
		expect(events()[1].payload.target).toBeNil() -- not on your plot, nobody carrying
		c.carry = { kind = "stolen", slimeId = "x" } :: any
		expect(fire(world, a, EAST, T0 + 30)).toBe(true)
		expect(events()[#events() - 1].payload.target).toBe(3) -- the thief, past player 2
		positions[3] = FOUNTAIN
		ServerFixtures.clearEvents(current)
		expect(fire(world, a, { X = 1, Y = 3, Z = 1 }, T0 + 50)).toBe(true)
		expect(events()[1].payload.target).toBeNil()
		done()
	end)
	it("flag off: no handler path, no events, no slow", function()
		local world, a, b = setup()
		expect(select(2, PvpService.use(world, a, "GooBlaster1", nil, EAST, T0 + 1, false, env))).toBe(
			"PvP is not open yet"
		)
		expect(#events()).toBe(0)
		expect(Carry.targetWalkSpeed(b, T0 + 1.5)).toBe(Config.BASE_WALK_SPEED)
		done()
	end)
end)
