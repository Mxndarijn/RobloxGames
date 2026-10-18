--!strict
-- Goo Trap line (CONTRACT.md §26 "Goo Trap line"): placement, thief-only trigger, freeze clamp + immunity,
-- re-arm, cleanup and zero parts. Server-side zones: nothing is ever created in Workspace.
local Config = require("../src/shared/Config")
local PvpRules = require("../src/shared/PvpRules")
local PvpService = require("../src/server/PvpService")
local PvpTrap = require("../src/server/PvpTrap")
local PvpTrapRules = require("../src/shared/PvpTrapRules")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local FAR = { X = 200, Y = 3, Z = -200 } -- clear of every safe zone
local SPAWN = { X = 0, Y = 3, Z = 0 }

local current: any = nil -- the world of the running test
local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end
local positions: { [number]: any } = {}
local onPlot = true
local joined: { any } = {}
local env = {
	positionOf = function(userId: number): any?
		return positions[userId]
	end,
	onOwnPlot = function(): boolean
		return true
	end,
	pointOnOwnPlot = function(): boolean
		return onPlot
	end,
}

local function setup(): (any, any, any)
	onPlot = true
	joined = {}
	positions = { [1] = FAR, [2] = FAR }
	PvpTrap.register()
	local world = ServerFixtures.world()
	current = world
	local owner = ServerFixtures.join(world, 1, nil, 1e12)
	local thief = ServerFixtures.join(world, 2, nil, 1e12)
	owner.data.rebirths, thief.data.rebirths = 10, 10
	PvpService.join(world, owner, T0, true)
	PvpService.join(world, thief, T0, true)
	joined = { owner, thief }
	return world, owner, thief
end

local function done()
	for _, session in joined do
		PvpTrap.clear(current, session) -- module state outlives the weak session keys
	end
	PvpService.registerLine("Trap", nil)
end

local function own(session: any, id: string)
	PvpRules.buy(session.data, id, true)
	session.data.cash = 1e12
	PvpService.equip(session, id, true)
end

local function place(world: any, owner: any, id: string, aim: any, now: number?): (boolean, string?)
	return PvpService.use(world, owner, id, nil, aim, now or T0, true, env)
end

local function makeThief(thief: any, ownerId: number)
	thief.carry = { slimeId = "s1", kind = "stolen", ownerUserId = ownerId }
end

local function kinds(): { string }
	local out = {}
	for _, e in events() do
		table.insert(out, e.payload.kind)
	end
	return out
end

describe("Goo Trap placement", function()
	it("places on the own plot, fires TrapPlaced and creates no Instance", function()
		local world, owner = setup()
		own(owner, "GooTrap3")
		local ok = place(world, owner, "GooTrap3", FAR)
		expect(ok).toBe(true)
		expect(PvpTrap.count(owner)).toBe(1)
		expect(PvpService.spawnedCount()).toBe(0)
		local placed
		for _, e in events() do
			if e.payload.kind == "TrapPlaced" then
				placed = e
			end
		end
		expect(placed ~= nil).toBe(true)
		expect(placed.target).toBeNil()
		expect(placed.payload.owner).toBe(1)
		expect(placed.payload.itemId).toBe("GooTrap3")
		expect(placed.payload.trapId).toBe(PvpTrap.list(owner)[1].id)
		done()
	end)
	it("refuses off the own plot, in a safe zone, with a bad aim, and starts no cooldown", function()
		local world, owner = setup()
		own(owner, "GooTrap1")
		onPlot = false
		local ok, reason = place(world, owner, "GooTrap1", FAR)
		expect(ok).toBe(false)
		expect(reason).toBe("only on your own plot")
		onPlot = true
		positions[1] = { X = 60, Y = 3, Z = 0 } -- just outside the fountain zone, in reach of its rim
		ok, reason = place(world, owner, "GooTrap1", { X = 40, Y = 3, Z = 0 })
		expect(ok).toBe(false)
		expect(reason).toBe("safe zone")
		ok, reason = place(world, owner, "GooTrap1", nil)
		expect(ok).toBe(false)
		expect(reason).toBe("no aim")
		ok = place(world, owner, "GooTrap1", { X = 0 / 0, Y = 0, Z = 0 })
		expect(ok).toBe(false)
		expect(PvpTrap.count(owner)).toBe(0)
		expect(PvpRules.ready(PvpService.state(owner) :: any, "GooTrap1", T0)).toBe(true)
		done()
	end)
	it("refuses an aim beyond TRAP_PLACE_RANGE of the owner's server position, whatever the client sends", function()
		local world, owner = setup()
		own(owner, "GooTrap1")
		local range = Config.PVP.TRAP_PLACE_RANGE
		local edge = { X = FAR.X + range, Y = FAR.Y, Z = FAR.Z }
		local past = { X = FAR.X + range + 1, Y = FAR.Y, Z = FAR.Z }
		local ok, reason = place(world, owner, "GooTrap1", past)
		expect(ok).toBe(false)
		expect(reason).toBe("too far away")
		expect(PvpTrap.count(owner)).toBe(0)
		expect(PvpRules.ready(PvpService.state(owner) :: any, "GooTrap1", T0)).toBe(true)
		expect(place(world, owner, "GooTrap1", edge)).toBe(true)
		done()
		world, owner = setup()
		own(owner, "GooTrap1")
		positions[1] = { X = FAR.X - 100, Y = FAR.Y, Z = FAR.Z } -- the owner walked away from the aim point
		ok, reason = place(world, owner, "GooTrap1", FAR)
		expect(ok).toBe(false)
		expect(reason).toBe("too far away")
		expect(place(world, owner, "GooTrap1", { X = FAR.X, Y = FAR.Y + range + 1, Z = FAR.Z })).toBe(false)
		done()
	end)
	it("refuses beyond the tier's trap count (does not replace the oldest)", function()
		local world, owner = setup()
		own(owner, "GooTrap1") -- 1 trap
		expect(place(world, owner, "GooTrap1", FAR)).toBe(true)
		local first = PvpTrap.list(owner)[1].id
		local ok, reason = place(world, owner, "GooTrap1", FAR, T0 + 100)
		expect(ok).toBe(false)
		expect(reason).toBe("too many traps")
		expect(PvpTrap.list(owner)[1].id).toBe(first)
		done()
		world, owner = setup()
		own(owner, "GooTrap2") -- 2 traps
		expect(place(world, owner, "GooTrap2", FAR, T0)).toBe(true)
		expect(place(world, owner, "GooTrap2", FAR, T0 + 100)).toBe(true)
		expect(place(world, owner, "GooTrap2", FAR, T0 + 200)).toBe(false)
		expect(PvpTrap.count(owner)).toBe(2)
		done()
	end)
	it("refuses with the flag off", function()
		local world, owner = setup()
		own(owner, "GooTrap1")
		local ok, reason = PvpService.use(world, owner, "GooTrap1", nil, FAR, T0, false, env)
		expect(ok).toBe(false)
		expect(reason).toBe("PvP is not open yet")
		expect(PvpTrapRules.canPlace(Config.PVP_TOOLS[1], 0, FAR, FAR, true, false)).toBe(false)
		expect(PvpTrap.count(owner)).toBe(0)
		done()
	end)
end)

describe("Goo Trap trigger", function()
	local function armed(id: string): (any, any, any)
		local world, owner, thief = setup()
		own(owner, id)
		place(world, owner, id, FAR)
		return world, owner, thief
	end
	it("freezes only a thief carrying the owner's slime, with Effect Freeze and no damage field", function()
		local _, owner, thief = armed("GooTrap3")
		expect(PvpTrap.tick(current, thief, FAR, T0)).toBe(0) -- empty-handed
		thief.carry = { slimeId = "w", kind = "wild" }
		expect(PvpTrap.tick(current, thief, FAR, T0)).toBe(0) -- wild slime
		makeThief(thief, 99)
		expect(PvpTrap.tick(current, thief, FAR, T0)).toBe(0) -- someone else's slime
		makeThief(thief, 1)
		expect(PvpTrap.tick(current, thief, { X = 200 + 5, Y = 3, Z = -200 }, T0)).toBe(0) -- outside radius 4
		expect(PvpTrap.tick(current, owner, FAR, T0)).toBe(0) -- the owner never triggers it
		expect(PvpTrap.frozen(thief, T0)).toBe(false)
		expect(PvpTrap.tick(current, thief, { X = 202, Y = 3, Z = -200 }, T0)).toBe(2)
		expect(PvpTrap.frozen(thief, T0 + 1.9)).toBe(true)
		expect(PvpTrap.frozen(thief, T0 + 2)).toBe(false)
		local effect
		for _, e in events() do
			if e.payload.kind == "Effect" then
				effect = e.payload
			end
		end
		expect(effect.effect).toBe("Freeze")
		expect(effect.target).toBe(2)
		expect(effect.attacker).toBe(1)
		expect(effect.duration).toBe(2)
		expect(effect.damage).toBeNil()
		done()
	end)
	it(
		"clamps the freeze to CONTROL_MAX_SECONDS, then 3 s immunity: an immune thief passes, the trap stays armed",
		function()
			local _, owner, thief = armed("GooTrap3")
			makeThief(thief, 1)
			local trap = PvpTrap.list(owner)[1]
			trap.control = 9 -- a bad value can never freeze longer than the cap
			trap.rearm = 1 -- re-arms before the immunity ends
			expect(PvpTrap.tick(current, thief, FAR, T0)).toBe(Config.PVP.CONTROL_MAX_SECONDS)
			expect(PvpTrap.tick(current, thief, FAR, T0 + 1.5)).toBe(0) -- still frozen / disarmed
			-- control over at +2, immune until +5; the trap is armed again at +1 but the thief passes through
			expect(PvpTrap.tick(current, thief, FAR, T0 + 3)).toBe(0)
			expect(PvpTrapRules.isArmed(trap, T0 + 3)).toBe(true)
			expect(PvpTrap.frozen(thief, T0 + 3)).toBe(false)
			expect(PvpTrap.tick(current, thief, FAR, T0 + 5)).toBe(2) -- immunity over: frozen again
			done()
		end
	)
	it("re-arms after `rearm` seconds and stays a zone", function()
		local _, owner, thief = armed("GooTrap3") -- rearm 20 s
		makeThief(thief, 1)
		local trap = PvpTrap.list(owner)[1]
		expect(PvpTrap.tick(current, thief, FAR, T0)).toBe(2)
		expect(PvpTrapRules.isArmed(trap, T0 + 19.9)).toBe(false)
		expect(PvpTrapRules.isArmed(trap, T0 + 20)).toBe(true)
		expect(PvpTrap.count(owner)).toBe(1)
		expect(PvpTrap.tick(current, thief, FAR, T0 + 20)).toBe(2)
		done()
	end)
	it("never triggers for a shielded new player", function()
		local _, _, thief = armed("GooTrap3")
		thief.data.rebirths = 0
		PvpService.join(current, thief, T0, true) -- fresh shield
		makeThief(thief, 1)
		expect(PvpService.isShielded(thief, T0)).toBe(true)
		expect(PvpTrap.tick(current, thief, FAR, T0)).toBe(0)
		done()
	end)
	it("does nothing without PvP state (flag off join)", function()
		local _, _, thief = armed("GooTrap3")
		makeThief(thief, 1)
		PvpService.join(current, thief, T0, false)
		expect(PvpTrap.tick(current, thief, FAR, T0)).toBe(0)
		done()
	end)
end)

describe("Goo Trap cleanup and parts", function()
	it("removes the owner's traps on leave and fires TrapCleared", function()
		local world, owner = setup()
		own(owner, "GooTrap2")
		place(world, owner, "GooTrap2", FAR)
		place(world, owner, "GooTrap2", FAR, T0 + 100)
		ServerFixtures.clearEvents(current)
		PvpService.leave(world, owner, T0 + 10)
		expect(PvpTrap.count(owner)).toBe(0)
		expect(kinds()).toEqual({ "TrapCleared", "TrapCleared" })
		expect(events()[1].payload.owner).toBe(1)
		done()
	end)
	it("clears a thief's freeze when they leave and keeps spawnedCount at 0 throughout", function()
		local world, owner, thief = setup()
		own(owner, "GooTrap1")
		expect(PvpService.spawnedCount()).toBe(0)
		place(world, owner, "GooTrap1", FAR)
		makeThief(thief, 1)
		PvpTrap.tick(current, thief, FAR, T0)
		expect(PvpTrap.frozen(thief, T0)).toBe(true)
		PvpService.leave(world, thief, T0 + 1)
		expect(PvpTrap.frozen(thief, T0 + 1)).toBe(false)
		expect(PvpService.spawnedCount()).toBe(0)
		PvpService.leave(world, owner, T0 + 2)
		expect(PvpService.spawnedCount()).toBe(0)
		done()
	end)
end)

describe("PvpTrapRules", function()
	it("keeps every tier's freeze within the control cap", function()
		for _, tool in Config.PVP_TOOLS do
			if tool.line == "Trap" then
				expect((tool.control or 0) <= Config.PVP.CONTROL_MAX_SECONDS).toBe(true)
				expect(tool.damage).toBeNil()
			end
		end
	end)
	it("rejects another floor", function()
		local trap = PvpTrapRules.new("t", 1, PvpRules.tool("GooTrap1") :: any, FAR, T0)
		expect(PvpTrapRules.inRadius(trap, { X = 200, Y = 3 + 20, Z = -200 })).toBe(false)
		expect(PvpTrapRules.inRadius(trap, { X = 200, Y = 3 + 4, Z = -200 })).toBe(true)
		expect(PvpTrapRules.canPlace(PvpRules.tool("KnockGlove1") :: any, 0, FAR, FAR, true, true)).toBe(false)
		expect(PvpRules.inSafeZone(SPAWN)).toBe(true)
	end)
end)
