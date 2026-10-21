--!strict
-- Goo Traps (CONTRACT.md §26.5): charges (buy / held cap / use / save), placing anywhere in range, the live cap
-- (a 6th removes the oldest), the replay to a late joiner, the lifetime, who springs a trap and what each tier does, caught thieves, cleanup and
-- zero parts. Server-side zones: nothing is ever created in Workspace.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local PvpSlow = require("../src/server/PvpSlow")
local PvpTrap = require("../src/server/PvpTrap")
local PvpTrapRules = require("../src/shared/PvpTrapRules")
local ServerFixtures = require("./ServerFixtures")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local PVP = Config.PVP
local FAR = { X = 200, Y = 3, Z = -200 }

local current: any = nil -- the world of the running test
local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end
local positions: { [number]: any } = {}
local launches: { { userId: number, push: any } } = {}
local joined: { any } = {}
local env: PvpService.Context = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
	launch = function(userId: number, push: any): boolean
		table.insert(launches, { userId = userId, push = push })
		return true
	end,
}

local function setup(): (any, any, any)
	joined = {}
	launches = {}
	positions = { [1] = FAR, [2] = FAR }
	PvpTrap.register()
	local world = ServerFixtures.world()
	current = world
	local owner = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) }, 1e12)
	local victim = ServerFixtures.join(world, 2, nil, 1e12)
	owner.data.rebirths, victim.data.rebirths = 10, 10
	ServerFixtures.unlock(owner)
	ServerFixtures.unlock(victim)
	PvpService.join(world, owner, T0, true)
	PvpService.join(world, victim, T0, true)
	joined = { owner, victim }
	return world, owner, victim
end

local function done()
	for _, session in joined do
		PvpTrap.clear(current, session) -- module state outlives the weak session keys
		PvpSlow.clear(session)
	end
	PvpService.registerLine("Trap", nil)
end

-- Buys `n` charges of `id` and equips it.
local function own(world: any, session: any, id: string, n: number?)
	for _ = 1, n or 1 do
		expect((PvpService.buy(world, session, id, true))).toBe(true)
	end
	expect((PvpService.equip(session, id, true))).toBe(true)
end

local function place(world: any, owner: any, id: string, aim: any, now: number?): (boolean, string?)
	return PvpService.use(world, owner, id, nil, aim, now or T0, true, env)
end

local function kinds(): { string }
	local out = {}
	for _, e in events() do
		table.insert(out, e.payload.kind)
	end
	return out
end

local function effects(name: string): { { [string]: any } }
	local out = {}
	for _, e in events() do
		if e.payload.kind == "Effect" and e.payload.effect == name then
			table.insert(out, e.payload)
		end
	end
	return out
end

describe("Goo Trap charges", function()
	it("each buy adds one charge; a 6th charge of a tier is refused and costs nothing", function()
		local world, owner = setup()
		own(world, owner, "GooTrap1", PVP.TRAP_MAX_HELD)
		expect(PvpRules.charges(owner.data, "GooTrap1")).toBe(5)
		local cash = owner.data.cash
		local ok, reason = PvpService.buy(world, owner, "GooTrap1", true)
		expect(ok).toBe(false)
		expect(reason).toBe("you can only hold 5")
		expect(owner.data.cash).toBe(cash)
		expect((PvpService.view(owner, T0) :: any).charges).toEqual({ GooTrap1 = 5 })
		done()
	end)
	it("placing uses one charge; the last one unequips the item", function()
		local world, owner = setup()
		own(world, owner, "GooTrap1", 2)
		expect(place(world, owner, "GooTrap1", FAR)).toBe(true)
		expect(PvpRules.charges(owner.data, "GooTrap1")).toBe(1)
		expect(PvpService.equipped(owner)).toBe("GooTrap1")
		expect(place(world, owner, "GooTrap1", FAR, T0 + PVP.MIN_COOLDOWN + 1)).toBe(true)
		expect(PvpRules.charges(owner.data, "GooTrap1")).toBe(0)
		expect(PvpService.equipped(owner)).toBe(nil)
		expect(select(2, place(world, owner, "GooTrap1", FAR, T0 + 10))).toBe("not equipped")
		done()
	end)
end)

describe("Goo Trap placement", function()
	it("places anywhere within range, fires TrapPlaced and creates no Instance", function()
		local world, owner = setup()
		own(world, owner, "GooTrap2")
		positions[1] = { X = 0, Y = 3, Z = 0 } -- the fountain: no safe zones
		expect(place(world, owner, "GooTrap2", { X = 3, Y = 3, Z = 0 })).toBe(true)
		expect(PvpTrap.count(owner)).toBe(1)
		expect(kinds()).toEqual({ "TrapPlaced", "Cooldown" })
		local placed = events()[1]
		expect(placed.target).toBeNil()
		expect(placed.payload.owner).toBe(1)
		expect(placed.payload.itemId).toBe("GooTrap2")
		expect(PvpService.spawnedCount()).toBe(0)
		done()
	end)
	it("refuses an aim out of range or junk, with no charge used and no cooldown", function()
		local world, owner = setup()
		own(world, owner, "GooTrap1")
		local far = { X = FAR.X + PVP.TRAP_PLACE_RANGE + 1, Y = 3, Z = FAR.Z }
		expect(select(2, place(world, owner, "GooTrap1", far))).toBe("too far away")
		expect(select(2, place(world, owner, "GooTrap1", nil))).toBe("no aim")
		expect(select(2, place(world, owner, "GooTrap1", { X = 0 / 0, Y = 0, Z = 0 }))).toBe("no aim")
		expect(PvpRules.charges(owner.data, "GooTrap1")).toBe(1)
		expect(next((PvpService.state(owner) :: any).cooldowns)).toBeNil()
		done()
	end)
	it("keeps at most 5 live traps: the 6th removes the oldest", function()
		local world, owner = setup()
		own(world, owner, "GooTrap1", 5)
		PvpService.buy(world, owner, "GooTrap2", true)
		local now = T0
		for _ = 1, 5 do
			expect(place(world, owner, "GooTrap1", FAR, now)).toBe(true)
			now += PVP.MIN_COOLDOWN + 0.5
		end
		local oldest = PvpTrap.list(owner)[1].id
		expect((PvpService.equip(owner, "GooTrap2", true))).toBe(true)
		ServerFixtures.clearEvents(current)
		expect(place(world, owner, "GooTrap2", FAR, now)).toBe(true)
		expect(PvpTrap.count(owner)).toBe(PVP.TRAP_MAX_LIVE)
		expect(PvpTrap.list(owner)[1].id ~= oldest).toBe(true)
		expect(kinds()[1]).toBe("TrapCleared")
		expect(events()[1].payload.trapId).toBe(oldest)
		done()
	end)
	it("a player who joins later gets every live trap, to them only, as a replay", function()
		local world, owner = setup()
		own(world, owner, "GooTrap2", 2)
		local aim = { X = FAR.X + 3, Y = 3, Z = FAR.Z }
		expect(place(world, owner, "GooTrap2", aim)).toBe(true)
		expect(place(world, owner, "GooTrap2", FAR, T0 + 100)).toBe(true)
		local first = PvpTrap.list(owner)[1].id
		local late = ServerFixtures.join(world, 3, nil, 1e12)
		ServerFixtures.clearEvents(current) -- the fixture's join may already have replayed (flag on)
		PvpService.join(world, late, T0 + 110, true)
		table.insert(joined, late)
		expect(kinds()).toEqual({ "TrapPlaced", "TrapPlaced" })
		for _, e in events() do
			expect(e.target).toBe(3)
			expect(e.payload.replay).toBe(true)
			expect(e.payload.owner).toBe(1)
		end
		local again = events()[1].payload.trapId == first and events()[1] or events()[2]
		expect(again.payload.trapId).toBe(first)
		expect(again.payload.position).toEqual(aim)
		-- a cleared trap is not replayed
		PvpService.leave(world, owner, T0 + 120)
		local later = ServerFixtures.join(world, 4, nil, 1e12)
		ServerFixtures.clearEvents(current)
		PvpService.join(world, later, T0 + 130, true)
		table.insert(joined, later)
		expect(kinds()).toEqual({})
		done()
	end)
	it("a trap that caught nobody is gone after its lifetime", function()
		local world, owner, victim = setup()
		own(world, owner, "GooTrap1")
		place(world, owner, "GooTrap1", FAR)
		positions[2] = { X = 500, Y = 3, Z = 0 }
		ServerFixtures.clearEvents(current)
		PvpTrap.tick(world, victim, positions[2], T0 + PVP.TRAP_LIFETIME_SECONDS - 1, env)
		expect(PvpTrap.count(owner)).toBe(1)
		PvpTrap.tick(world, victim, positions[2], T0 + PVP.TRAP_LIFETIME_SECONDS, env)
		expect(PvpTrap.count(owner)).toBe(0)
		expect(kinds()).toEqual({ "TrapCleared" })
		done()
	end)
end)

describe("Goo Trap springing", function()
	it("Puddle: anyone but the owner is slowed 50 % for 2 s, then the trap is gone", function()
		local world, owner, victim = setup()
		own(world, owner, "GooTrap1")
		place(world, owner, "GooTrap1", FAR)
		ServerFixtures.clearEvents(current)
		expect(PvpTrap.tick(world, owner, FAR, T0, env)).toBe(false) -- the owner never springs it
		expect(PvpTrap.tick(world, victim, { X = 210, Y = 3, Z = -200 }, T0, env)).toBe(false) -- outside the radius
		expect(PvpTrap.tick(world, victim, FAR, T0, env)).toBe(true)
		expect(PvpSlow.walkFactor(victim, T0 + 1)).toBe(0.5)
		expect(PvpSlow.walkFactor(victim, T0 + 2)).toBe(1)
		expect(PvpTrap.count(owner)).toBe(0)
		local e = effects("Freeze")[1]
		expect(e.attacker).toBe(1)
		expect(e.target).toBe(2)
		expect(e.hold).toBe(0)
		expect(e.duration).toBe(2)
		expect(e.damage).toBeNil()
		expect(kinds()[#kinds()]).toBe("TrapCleared")
		done()
	end)
	it("Sticky: held 1.5 s, then slowed", function()
		local world, owner, victim = setup()
		own(world, owner, "GooTrap2")
		place(world, owner, "GooTrap2", FAR)
		expect(PvpTrap.tick(world, victim, FAR, T0, env)).toBe(true)
		expect(PvpSlow.walkFactor(victim, T0 + 1)).toBe(0)
		expect(PvpSlow.walkFactor(victim, T0 + 2)).toBe(0.5)
		expect(PvpSlow.walkFactor(victim, T0 + 3.1)).toBe(1)
		expect(effects("Freeze")[1].hold).toBe(1.5)
		done()
	end)
	it("Mega: holds 2 s, pulls in a player within 4 studs, then spits both out with a bounce", function()
		local world, owner, victim = setup()
		local other = ServerFixtures.join(world, 3, nil, 0)
		PvpService.join(world, other, T0, true)
		table.insert(joined, other)
		positions[3] = { X = 206, Y = 3, Z = -200 } -- 6 studs off: inside radius 4 + pull 4
		own(world, owner, "GooTrap3")
		place(world, owner, "GooTrap3", FAR)
		expect(PvpTrap.tick(world, victim, FAR, T0, env)).toBe(true)
		expect(PvpSlow.walkFactor(victim, T0 + 1)).toBe(0)
		expect(PvpSlow.walkFactor(other, T0 + 1)).toBe(0) -- pulled in and held too
		expect(#launches).toBe(1) -- the pull
		expect(launches[1].userId).toBe(3)
		expect(launches[1].push.X < 0).toBe(true) -- toward the trap
		PvpTrap.tick(world, victim, FAR, T0 + 1.9, env)
		expect(#launches).toBe(1) -- still held
		PvpTrap.tick(world, victim, FAR, T0 + 2, env)
		expect(#launches).toBe(2) -- spat out
		expect(launches[2].push.Y > 0).toBe(true)
		local spits = effects("Knockback")
		expect(#spits).toBe(1)
		expect(spits[1].itemId).toBe("GooTrap3")
		done()
	end)
	it("any tier sends a caught thief's slime home, even when the thief is immune", function()
		for _, id in { "GooTrap1", "GooTrap2", "GooTrap3" } do
			local world, owner, victim = setup()
			own(world, owner, id)
			place(world, owner, id, FAR)
			expect((StealService.steal(world, victim, "gem", 1, T0))).toBe(true)
			PvpRules.applyControl(PvpService.state(victim) :: any, 1, T0) -- immune: no hold, still caught
			expect(PvpTrap.tick(world, victim, FAR, T0 + 0.5, env)).toBe(true)
			expect(victim.carry).toBeNil()
			expect(world.escaping.gem ~= nil).toBe(true)
			expect(PvpTrap.count(owner)).toBe(0)
			done()
		end
	end)
	it("an immune player who carries nothing passes and the trap stays", function()
		local world, owner, victim = setup()
		own(world, owner, "GooTrap2")
		place(world, owner, "GooTrap2", FAR)
		PvpRules.applyControl(PvpService.state(victim) :: any, 1, T0)
		expect(PvpTrap.tick(world, victim, FAR, T0 + 0.5, env)).toBe(false)
		expect(PvpTrap.count(owner)).toBe(1)
		done()
	end)
	it("never springs without PvP state", function()
		local world, owner, victim = setup()
		own(world, owner, "GooTrap1")
		place(world, owner, "GooTrap1", FAR)
		PvpService.join(world, victim, T0, false) -- flag off: no state
		expect(PvpTrap.tick(world, victim, FAR, T0 + 1, env)).toBe(false)
		expect(PvpTrap.count(owner)).toBe(1)
		done()
	end)
end)

describe("Goo Trap cleanup and parts", function()
	it("removes the owner's traps on leave and fires TrapCleared", function()
		local world, owner = setup()
		own(world, owner, "GooTrap2", 2)
		place(world, owner, "GooTrap2", FAR)
		place(world, owner, "GooTrap2", FAR, T0 + 100)
		ServerFixtures.clearEvents(current)
		PvpService.leave(world, owner, T0 + 110)
		expect(PvpTrap.count(owner)).toBe(0)
		expect(kinds()).toEqual({ "TrapCleared", "TrapCleared" })
		expect(events()[1].payload.owner).toBe(1)
		done()
	end)
	it("clears a held player's hold when they leave and keeps spawnedCount at 0 throughout", function()
		local world, owner, victim = setup()
		own(world, owner, "GooTrap2")
		expect(PvpService.spawnedCount()).toBe(0)
		place(world, owner, "GooTrap2", FAR)
		PvpTrap.tick(world, victim, FAR, T0, env)
		expect(PvpSlow.held(victim, T0)).toBe(true)
		PvpService.leave(world, victim, T0 + 1)
		expect(PvpSlow.held(victim, T0 + 1)).toBe(false)
		expect(PvpService.spawnedCount()).toBe(0)
		PvpService.leave(world, owner, T0 + 2)
		expect(PvpService.spawnedCount()).toBe(0)
		done()
	end)
end)

describe("PvpTrapRules", function()
	it("rejects another floor and a non-trap tool", function()
		local trap = PvpTrapRules.new("t", 1, PvpRules.tool("GooTrap1") :: any, FAR, T0)
		expect(PvpTrapRules.inRadius(trap, { X = 200, Y = 3 + 20, Z = -200 })).toBe(false)
		expect(PvpTrapRules.inRadius(trap, { X = 200, Y = 3 + 4, Z = -200 })).toBe(true)
		expect((PvpTrapRules.canPlace(PvpRules.tool("KnockGlove1") :: any, 1, FAR, FAR, true))).toBe(false)
		expect(PvpTrapRules.overflow(4)).toBe(0)
		expect(PvpTrapRules.overflow(5)).toBe(1)
	end)
end)
