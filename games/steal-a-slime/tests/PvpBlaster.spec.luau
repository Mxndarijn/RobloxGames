--!strict
-- The Goo Blasters (FEATURES.PvP, CONTRACT.md §26.6): the blob arc, hit / miss / range, the Squirter tank and its
-- stacking slow, the Blaster fan, the Cannon splash and pool, the missed blob's splat, caught thieves,
-- walk speed restore, flag-off refusal, nothing spawned. Every flag-dependent call passes the flag explicitly so the
-- specs hold in the forced-flag runs too.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PvpBlaster = require("../src/server/PvpBlaster")
local PvpBlasterRules = require("../src/shared/PvpBlasterRules")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local PvpSlow = require("../src/server/PvpSlow")
local ServerFixtures = require("./ServerFixtures")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local PVP = Config.PVP
local ORIGIN = { X = 200, Y = 3, Z = -200 }
local TIERS = { "GooBlaster1", "GooBlaster2", "GooBlaster3" }

local current: any = nil -- the world of the running test
local joined: { any } = {}
local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end
local positions: { [number]: any } = {}
local env: PvpService.Context = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
}

local function setup(tier: string?): (any, any, any, any)
	positions = {
		[1] = ORIGIN,
		[2] = { X = 220, Y = 3, Z = -200 },
		[3] = { X = 230, Y = 3, Z = -200 },
	}
	PvpBlaster.register()
	local world = ServerFixtures.world()
	current = world
	local a = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) }, 1e12)
	local b = ServerFixtures.join(world, 2, nil, 1e12)
	local c = ServerFixtures.join(world, 3, nil, 1e12)
	a.data.rebirths, b.data.rebirths, c.data.rebirths = 20, 20, 20
	for _, s in { a, b, c } do
		ServerFixtures.unlock(s)
		PvpService.join(world, s, T0, true)
	end
	joined = { a, b, c }
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
	for _, s in joined do
		PvpBlaster.clear(current, s)
		PvpSlow.clear(s)
	end
	PvpService.registerLine("Blaster", nil)
end

local function fire(world: any, a: any, aim: any, at: number, id: string?): (boolean, string?)
	return PvpService.use(world, a, id or "GooBlaster1", nil, aim, at, true, env)
end

local function shots(): { { [string]: any } }
	local out = {}
	for _, e in events() do
		if e.payload.kind == "Effect" and e.payload.effect == "Slow" and e.payload.from ~= nil then
			table.insert(out, e.payload)
		end
	end
	return out
end

local function kinds(): { string }
	local out = {}
	for _, e in events() do
		table.insert(out, e.payload.kind)
	end
	return out
end

describe("Blaster geometry", function()
	it("the arc starts at the shooter, ends at the aim and takes distance / speed seconds", function()
		local tool = PvpRules.tool("GooBlaster2") :: any
		local arc = PvpBlasterRules.arc(tool, ORIGIN, { X = 235, Y = 3, Z = -200 }) :: any
		expect(math.abs(arc.flight - 35 / tool.speed) < 1e-9).toBe(true)
		local land = PvpBlasterRules.pointAt(arc, arc.flight)
		expect(math.abs(land.X - 235) < 1e-6 and math.abs(land.Y - 3) < 1e-6).toBe(true)
		local mid = PvpBlasterRules.pointAt(arc, arc.flight / 2)
		expect(mid.Y > 3).toBe(true) -- it arcs up
		expect(PvpBlasterRules.arc(tool, ORIGIN, ORIGIN)).toBeNil()
		expect(PvpBlasterRules.arc(tool, ORIGIN, { X = 0 / 0, Y = 0, Z = 0 })).toBeNil()
	end)
	it("a far aim is clamped to the tier's range", function()
		for _, id in TIERS do
			local tool = PvpRules.tool(id) :: any
			local arc = PvpBlasterRules.arc(tool, ORIGIN, { X = 1000, Y = 3, Z = -200 }) :: any
			expect(math.abs(arc.to.X - (200 + tool.range)) < 1e-6).toBe(true)
		end
	end)
	it("hits the first player along the arc within the hit radius", function()
		local tool = PvpRules.tool("GooBlaster1") :: any
		local arc = PvpBlasterRules.arc(tool, ORIGIN, { X = 235, Y = 3, Z = -200 }) :: any
		local near = { id = 2, position = { X = 220, Y = 3, Z = -200 } }
		local far = { id = 3, position = { X = 233, Y = 3, Z = -200 } }
		local off = { id = 4, position = { X = 220, Y = 3, Z = -190 } }
		expect((PvpBlasterRules.firstHit(arc, { far, near, off }) :: any).id).toBe(2)
		expect(PvpBlasterRules.firstHit(arc, { off })).toBeNil()
	end)
	it("the Blaster fans 3 blobs, the middle one on the aim", function()
		local tool = PvpRules.tool("GooBlaster2") :: any
		local aims = PvpBlasterRules.fan(tool, ORIGIN, { X = 230, Y = 3, Z = -200 })
		expect(#aims).toBe(3)
		expect(aims[2].X).toBe(230)
		expect(aims[1].Z < -200 or aims[1].Z > -200).toBe(true)
		expect(#PvpBlasterRules.fan(PvpRules.tool("GooBlaster3") :: any, ORIGIN, ORIGIN)).toBe(1)
	end)
end)

describe("Blaster use", function()
	it("a blob hits the clicked player, slows them, and fires its arc to everyone", function()
		local world, a, b = setup("GooBlaster3")
		expect(fire(world, a, positions[2], T0 + 1, "GooBlaster3")).toBe(true)
		local shot = shots()[1]
		expect(shot.target).toBe(2)
		expect(shot.attacker).toBe(1)
		expect(shot.itemId).toBe("GooBlaster3")
		expect(shot.from).toEqual(ORIGIN)
		expect(shot.flight > 0).toBe(true)
		expect(events()[1].target).toBeNil() -- every client
		expect(PvpSlow.walkFactor(b, T0 + 2)).toBe(0.5)
		expect(PvpSlow.walkFactor(b, T0 + 4.1)).toBe(1)
		expect(kinds()[#kinds()]).toBe("Cooldown")
		expect(PvpService.spawnedCount()).toBe(0)
		done()
	end)
	it("the slow multiplies into the enforced walk speed and restores by itself", function()
		local world, a, b = setup("GooBlaster2")
		local normal = Carry.targetWalkSpeed(b, T0)
		expect(fire(world, a, positions[2], T0 + 1, "GooBlaster2")).toBe(true)
		expect(math.abs(Carry.targetWalkSpeed(b, T0 + 2) - normal * 0.6) < 1e-9).toBe(true)
		expect(Carry.targetWalkSpeed(b, T0 + 3.1)).toBe(normal)
		done()
	end)
	it("a missed blob leaves a slippery splat that slows whoever walks in, not the shooter", function()
		local world, a, b = setup("GooBlaster3")
		positions[2], positions[3] = { X = 500, Y = 3, Z = 0 }, { X = 500, Y = 3, Z = 10 }
		local miss = { X = 200, Y = 3, Z = -230 }
		ServerFixtures.clearEvents(current)
		expect(fire(world, a, miss, T0 + 1, "GooBlaster3")).toBe(true)
		local shot = shots()[1]
		expect(shot.target).toBeNil()
		expect(shot.splat ~= nil).toBe(true)
		expect(#PvpBlaster.zones(a)).toBe(1)
		expect(PvpBlaster.tick(world, a, miss, T0 + 1.5, env)).toBe(0) -- the shooter's own pool
		expect(PvpBlaster.tick(world, b, miss, T0 + 1.5, env) > 0).toBe(true)
		expect(PvpSlow.walkFactor(b, T0 + 1.6) < 1).toBe(true)
		-- gone after its time
		expect(#PvpBlaster.zones(a)).toBe(1)
		PvpBlaster.tick(world, b, { X = 500, Y = 3, Z = 0 }, T0 + 1 + 10, env)
		expect(#PvpBlaster.zones(a)).toBe(0)
		done()
	end)
	it("a plain miss with the Blaster leaves a 5 s splat", function()
		local world, a, b = setup("GooBlaster2")
		positions[2], positions[3] = { X = 500, Y = 3, Z = 0 }, { X = 500, Y = 3, Z = 10 }
		expect(fire(world, a, { X = 230, Y = 3, Z = -200 }, T0 + 1, "GooBlaster2")).toBe(true)
		expect(#PvpBlaster.zones(a)).toBe(3) -- one splat per blob
		local splat = (shots()[1] :: any).splat
		expect(splat.seconds).toBe(PVP.SPLAT_SECONDS)
		local _ = b
		done()
	end)
	it("Squirter: 6 shots per tank, then the refill cooldown; the gap between shots is enforced", function()
		local world, a = setup("GooBlaster1")
		local t = T0 + 1
		for _ = 1, 5 do
			expect(fire(world, a, positions[2], t)).toBe(true)
			expect(PvpRules.ready(PvpService.state(a) :: any, "GooBlaster1", t)).toBe(true) -- no cooldown yet
			t += 0.3
		end
		local last = t - 0.3
		expect(select(2, fire(world, a, positions[2], last + 0.1))).toBe("too fast")
		expect(fire(world, a, positions[2], last + 0.3)).toBe(true) -- the 6th
		expect(select(2, fire(world, a, positions[2], last + 0.6))).toBe("not ready")
		expect(fire(world, a, positions[2], last + 0.3 + 3)).toBe(true) -- refilled
		done()
	end)
	it("Squirter hits stack a little slow, capped at SLOW_MAX_SECONDS from the first hit", function()
		local world, a, b = setup("GooBlaster1")
		expect(fire(world, a, positions[2], T0 + 1)).toBe(true)
		expect(math.abs(PvpSlow.walkFactor(b, T0 + 1.1) - 0.85) < 1e-9).toBe(true)
		expect(fire(world, a, positions[2], T0 + 1.3)).toBe(true)
		expect(math.abs(PvpSlow.walkFactor(b, T0 + 1.4) - 0.7) < 1e-9).toBe(true)
		local t = T0 + 1.6
		for _ = 1, 4 do
			fire(world, a, positions[2], t)
			t += 0.3
		end
		expect(math.abs(PvpSlow.walkFactor(b, t) - 0.55) < 1e-9).toBe(true) -- capped at 45 %
		expect(PvpSlow.walkFactor(b, T0 + 1 + PVP.SLOW_MAX_SECONDS)).toBe(1)
		done()
	end)
	it("every blaster tier catches a thief it hits: the slime goes home with one toast", function()
		for _, id in TIERS do
			local world, a, b = setup(id)
			expect((StealService.steal(world, b, "gem", 1, T0))).toBe(true)
			expect(fire(world, a, positions[2], T0 + 1, id)).toBe(true)
			expect(b.carry).toBeNil()
			expect(world.escaping.gem ~= nil).toBe(true)
			local toasts = 0
			for _, text in ServerFixtures.notifications(world, 1) do
				if text == `You caught {b.name}! The slime went home.` then
					toasts += 1
				end
			end
			expect(toasts).toBe(1)
			done()
		end
	end)
	it("a thief walking into a splat is caught, also while immune to its slow", function()
		local world, a, b = setup("GooBlaster2")
		positions[2], positions[3] = { X = 500, Y = 3, Z = 0 }, { X = 500, Y = 3, Z = 10 }
		local miss = { X = 230, Y = 3, Z = -200 }
		expect(fire(world, a, miss, T0 + 1, "GooBlaster2")).toBe(true)
		expect((StealService.steal(world, b, "gem", 1, T0 + 2))).toBe(true)
		PvpRules.applyControl(PvpService.state(b) :: any, 1, T0 + 2) -- under control: immune to the slip
		local spot = PvpBlaster.zones(a)[1].position
		expect(PvpBlaster.tick(world, b, spot, T0 + 2.1, env)).toBe(0)
		expect(b.carry).toBeNil()
		expect(world.escaping.gem ~= nil).toBe(true)
		done()
	end)
	it("the Cannon splashes everyone within 6 studs and leaves a pool", function()
		local world, a, b, c = setup("GooBlaster3")
		positions[3] = { X = 224, Y = 3, Z = -200 } -- 4 studs from the impact
		expect(fire(world, a, positions[2], T0 + 1, "GooBlaster3")).toBe(true)
		expect(PvpSlow.walkFactor(b, T0 + 1.5) < 1).toBe(true)
		expect(PvpSlow.walkFactor(c, T0 + 1.5) < 1).toBe(true)
		expect(#PvpBlaster.zones(a)).toBe(1)
		expect((shots()[1] :: any).splat.seconds).toBe(4)
		done()
	end)
	it("immunity after the slow: a second hit lands but slows nothing", function()
		local world, a, b = setup("GooBlaster2")
		expect(fire(world, a, positions[2], T0 + 1, "GooBlaster2")).toBe(true)
		expect(fire(world, a, positions[2], T0 + 4.5, "GooBlaster2")).toBe(true) -- slow over, immunity running
		expect(PvpSlow.walkFactor(b, T0 + 4.6)).toBe(1)
		done()
	end)
	it("refusals start no cooldown: no aim, bad aim, not equipped, flag off", function()
		local world, a = setup("GooBlaster3")
		expect(select(2, fire(world, a, nil, T0 + 1, "GooBlaster3"))).toBe("no aim")
		expect(select(2, fire(world, a, ORIGIN, T0 + 1, "GooBlaster3"))).toBe("bad aim")
		expect(select(2, fire(world, a, positions[2], T0 + 1, "GooBlaster2"))).toBe("not equipped")
		expect(select(2, PvpService.use(world, a, "GooBlaster3", nil, positions[2], T0 + 1, false, env))).toBe(
			"PvP is not open yet"
		)
		expect(next((PvpService.state(a) :: any).cooldowns)).toBeNil()
		done()
	end)
	it("a target given by id is aimed at from the server's positions", function()
		local world, a, b = setup("GooBlaster3")
		expect(PvpService.use(world, a, "GooBlaster3", 2, nil, T0 + 1, true, env)).toBe(true)
		expect(shots()[1].target).toBe(2)
		positions[2] = { X = 400, Y = 3, Z = -200 } -- beyond the range: the blob falls short
		expect(PvpService.use(world, a, "GooBlaster3", 2, nil, T0 + 10, true, env)).toBe(true)
		expect(shots()[2].target).toBeNil()
		local _ = b
		done()
	end)
end)
