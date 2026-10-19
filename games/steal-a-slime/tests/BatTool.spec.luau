--!strict
-- The default Bat (server/BatTool + shared/BatRules, CONTRACT.md §26 "Bat"): LIVE for everyone, not behind FEATURES.PvP.
-- A swing picks its own target from the swinger's pose, then runs the base slap (StealService.slap) plus a knockback.
-- Every swing passes the PvP flag explicitly so the specs hold in the forced-flag CI runs too.
local BatRules = require("../src/shared/BatRules")
local BatTool = require("../src/server/BatTool")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PvpKnockbackRules = require("../src/shared/PvpKnockbackRules")
local PvpService = require("../src/server/PvpService")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local ORIGIN = { X = 200, Y = 3, Z = -200 }
local LOOK = { X = 1, Y = 0, Z = 0 } -- facing +X (never reassigned)

local plot = true
local poses: { [number]: any } = {}
local moves: { { userId: number, push: any, landing: any } } = {}
local current: any = nil -- the world of the running test
local function events(): { ServerFixtures.PvpEvent }
	return ServerFixtures.pvpEvents(current)
end
local function record(userId: number, push: any, landing: any?): boolean
	table.insert(moves, { userId = userId, push = push, landing = landing })
	return true
end
local bat: PvpService.Context = {
	pose = function(userId: number)
		local at = poses[userId]
		return at, if at then LOOK else nil
	end,
	launch = record,
	pointOnOwnPlot = function(): boolean
		return plot
	end,
}

-- Owner 1 owns "gem"; thief 2 carries it `dx` studs in front of the owner (facing +X); bystander 3 holds nothing.
local function setup(dx: number?): (any, any, any, any)
	moves = {}
	bat.launch = record
	for userId = 1, 3 do
		BatTool.forget(userId)
	end
	poses = {
		[1] = ORIGIN,
		[2] = { X = ORIGIN.X + (dx or 4), Y = 3, Z = ORIGIN.Z },
		[3] = { X = ORIGIN.X + 2, Y = 3, Z = ORIGIN.Z + 1 },
	}
	plot = true
	local world = ServerFixtures.world()
	current = world
	local owner = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) })
	local thief = ServerFixtures.join(world, 2)
	local bystander = ServerFixtures.join(world, 3)
	ServerFixtures.unlock(owner)
	return world, owner, thief, bystander
end

local function done()
	for userId = 1, 3 do
		BatTool.forget(userId)
	end
end

describe("BatRules.pickTarget", function()
	local function at(x: number, z: number, userId: number, carrying: boolean)
		return { userId = userId, position = { X = x, Y = 3, Z = z }, carrying = carrying }
	end
	it("picks the nearest carrying thief in front within SLAP_REACH, never yourself or a non-carrier", function()
		local list = { at(205, -200, 1, true), at(207, -200, 2, true), at(204, -200, 3, true), at(203, -200, 4, false) }
		expect((BatRules.pickTarget(ORIGIN, LOOK, list, 1))).toBe(3)
		expect((BatRules.pickTarget(ORIGIN, LOOK, { at(203, -200, 4, false) }, 1))).toBeNil()
	end)
	it("enforces reach and facing, but not facing for a thief hugging you", function()
		expect((BatRules.pickTarget(ORIGIN, LOOK, { at(200 + Config.SLAP_REACH + 1, -200, 2, true) }, 1))).toBeNil()
		expect((BatRules.pickTarget(ORIGIN, LOOK, { at(200 + Config.SLAP_REACH - 1, -200, 2, true) }, 1))).toBe(2)
		expect((BatRules.pickTarget(ORIGIN, LOOK, { at(194, -200, 2, true) }, 1))).toBeNil() -- behind
		expect((BatRules.pickTarget(ORIGIN, LOOK, { at(200, -194, 2, true) }, 1))).toBeNil() -- 90 degrees off
		expect((BatRules.pickTarget(ORIGIN, LOOK, { at(198, -200, 2, true) }, 1))).toBe(2) -- close behind
		expect((BatRules.pickTarget(ORIGIN, { X = 0, Y = 0, Z = 0 }, { at(205, -200, 2, true) }, 1))).toBeNil()
	end)
end)

describe("BatTool.swing", function()
	it(
		"hits a carrying thief like the slap: slime dropped, bounces home, plus a knockback away from the owner",
		function()
			local world, owner, thief = setup()
			Carry.grab(world, 2, "gem", 1, T0 + 100)
			expect(thief.carry ~= nil).toBe(true)
			local hit, why = BatTool.swing(world, owner, T0 + 101, bat, false)
			expect(why).toBeNil()
			expect(hit).toBe(true)
			expect(thief.carry).toBeNil()
			expect(world.escaping.gem ~= nil).toBeTruthy()
			expect(owner.lastSlapAt).toBe(T0 + 101) -- the shared slap cooldown
			expect(#moves).toBe(1)
			expect(moves[1].userId).toBe(2)
			local pushed = PvpKnockbackRules.horizontal(moves[1].push)
			expect(pushed > 0 and pushed <= math.min(Config.BAT.PUSH, Config.PVP.KNOCKBACK_MAX_PUSH) + 1e-9).toBe(true)
			expect(moves[1].push.X > 0).toBe(true) -- away from the owner
			local fx = events()[#events()]
			expect(fx.payload.effect).toBe("Knockback")
			expect(fx.payload.itemId).toBe("Bat")
			expect(fx.payload.target).toBe(2)
			done()
		end
	)
	it("shares the slap cooldown and enforces reach", function()
		local world, owner, thief = setup()
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		owner.lastSlapAt = T0 + 100 -- e.g. a Squeaky Hammer hit a moment ago
		local hit, why = BatTool.swing(world, owner, T0 + 100 + Config.SLAP_COOLDOWN - 0.5, bat, false)
		expect(hit).toBe(false)
		expect(why).toBe("slap on cooldown")
		expect(thief.carry ~= nil).toBe(true)
		expect(#moves).toBe(0)
		expect((BatTool.swing(world, owner, T0 + 100 + Config.SLAP_COOLDOWN + 1, bat, false))).toBe(true)
		done()

		world, owner, thief = setup(Config.SLAP_REACH + 1)
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		local far, farWhy = BatTool.swing(world, owner, T0 + 101, bat, false)
		expect(far).toBe(false)
		expect(farWhy).toBe("nothing in reach")
		expect(thief.carry ~= nil).toBe(true)
		expect(owner.lastSlapAt < T0).toBe(true) -- a whiff never spends the cooldown
		done()
	end)
	it("a thief behind the swinger is not hit; a client cannot name a target", function()
		local world, owner, thief = setup(-6)
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		expect((BatTool.swing(world, owner, T0 + 101, bat, false))).toBe(false)
		expect(thief.carry ~= nil).toBe(true)
		done()
	end)
	it("swinging at nothing or at a non-thief does nothing (no error, no push, no cooldown)", function()
		local world, owner, thief, bystander = setup()
		local hit, why = BatTool.swing(world, owner, T0 + 101, bat, false)
		expect(hit).toBe(false)
		expect(why).toBe("nothing in reach")
		expect(#moves).toBe(0)
		expect(#events()).toBe(0)
		expect(owner.lastSlapAt < T0).toBe(true)
		expect(thief.carry).toBeNil()
		expect(bystander.carry).toBeNil()
		done()
	end)
	it("rate limits swing events but a miss does not block the next hit", function()
		local world, owner, thief = setup()
		expect(select(2, BatTool.swing(world, owner, T0 + 100, bat, false))).toBe("nothing in reach")
		expect(select(2, BatTool.swing(world, owner, T0 + 100 + Config.BAT.SWING_GAP / 2, bat, false))).toBe("too fast")
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		expect((BatTool.swing(world, owner, T0 + 100 + Config.BAT.SWING_GAP + 0.01, bat, false))).toBe(true)
		expect(thief.carry).toBeNil()
		done()
	end)
	it("still drops the slime when nothing can be pushed (no mover)", function()
		local world, owner, thief = setup()
		bat.launch = nil
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		expect((BatTool.swing(world, owner, T0 + 101, bat, false))).toBe(true)
		expect(thief.carry).toBeNil()
		done()
	end)
end)

-- FEATURES.PvP ON: a thief is still the slap / defense hit; a non-thief follows the PvP melee (glove) rules.
describe("BatTool.swing with PvP on", function()
	local function pvpSetup(dx: number?)
		local world, owner, thief, bystander = setup(dx)
		for _, s in { owner, thief, bystander } do
			PvpService.join(world, s, T0, true)
			local state = PvpService.state(s)
			if state then
				state.shieldUntil = 0 -- past the new-player shield unless a test wants it
			end
		end
		return world, owner, thief, bystander
	end
	it("a thief hit is still the slap: one drop, one push, one cooldown, bystander untouched", function()
		local world, owner, thief, bystander = pvpSetup()
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		expect((BatTool.swing(world, owner, T0 + 101, bat, true))).toBe(true)
		expect(thief.carry).toBeNil()
		expect(world.escaping.gem ~= nil).toBeTruthy()
		expect(owner.lastSlapAt).toBe(T0 + 101)
		expect(#moves).toBe(1)
		expect(moves[1].userId).toBe(2) -- the thief, not the closer non-thief on the owner's plot
		expect(bystander.carry).toBeNil()
		local knocks = 0
		for _, ev in events() do
			if ev.payload.effect == "Knockback" then
				knocks += 1
			end
		end
		expect(knocks).toBe(1)
		done()
	end)
	it("a non-thief on your own plot is pushed (no damage), sharing the slap cooldown", function()
		local world, owner = pvpSetup()
		local hit, why = BatTool.swing(world, owner, T0 + 101, bat, true)
		expect(why).toBeNil()
		expect(hit).toBe(true)
		expect(#moves).toBe(1)
		expect(moves[1].userId).toBe(3)
		expect(PvpKnockbackRules.horizontal(moves[1].push) <= Config.PVP.KNOCKBACK_MAX_PUSH + 1e-9).toBe(true)
		expect(owner.lastSlapAt).toBe(T0 + 101)
		-- immune for a moment after the control, and the shared cooldown holds anyway
		local again, againWhy = BatTool.swing(world, owner, T0 + 101 + Config.BAT.SWING_GAP + 0.1, bat, true)
		expect(again).toBe(false)
		expect(againWhy).toBe("slap on cooldown")
		expect(#moves).toBe(1)
		done()
	end)
	it("a non-thief off your plot, or with either player under the new-player shield, is not hit", function()
		local world, owner, _, bystander = pvpSetup()
		plot = false
		expect(select(2, BatTool.swing(world, owner, T0 + 101, bat, true))).toBe("not on your plot")
		plot = true
		local shield = PvpService.state(bystander).shieldUntil
		PvpService.state(bystander).shieldUntil = T0 + 1000
		expect(select(2, BatTool.swing(world, owner, T0 + 110, bat, true))).toBe("shielded")
		PvpService.state(bystander).shieldUntil = shield
		local mine = PvpService.state(owner).shieldUntil
		PvpService.state(owner).shieldUntil = T0 + 1000
		expect(select(2, BatTool.swing(world, owner, T0 + 120, bat, true))).toBe("shielded")
		PvpService.state(owner).shieldUntil = mine
		expect(#moves).toBe(0)
		expect(owner.lastSlapAt < T0).toBe(true)
		done()
	end)
	it("a controlled (immune) thief still drops the slime but is not pushed twice", function()
		local world, owner, thief = pvpSetup()
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		local state = PvpService.state(thief)
		state.controlUntil = T0 + 200
		expect((BatTool.swing(world, owner, T0 + 101, bat, true))).toBe(true)
		expect(thief.carry).toBeNil()
		expect(#moves).toBe(0)
		done()
	end)
	it("with the flag OFF the same non-thief on your plot is left alone", function()
		local world, owner = pvpSetup()
		expect(select(2, BatTool.swing(world, owner, T0 + 101, bat, false))).toBe("nothing in reach")
		expect(#moves).toBe(0)
		done()
	end)
end)

describe("BatTool.swing on the boss (contract/boss-event.md)", function()
	local BossEvent = require("../src/server/BossEvent")
	local BOSS = Config.BOSS
	local BOSS_AT = { X = ORIGIN.X + (Config.SLAP_REACH + BOSS.HIT_REACH) / 2, Y = 6, Z = ORIGIN.Z } -- in front, inside HIT_REACH, past SLAP_REACH

	-- Players 1 and 2 at ORIGIN and just beside it; the boss has arrived (phase "fight") at T0.
	local function fight(): (any, any, any, PvpService.Context)
		moves = {}
		poses = { [1] = ORIGIN, [2] = { X = ORIGIN.X + 3, Y = 3, Z = ORIGIN.Z } }
		for userId = 1, 2 do
			BatTool.forget(userId)
		end
		local world = ServerFixtures.world()
		current = world
		world.startedAt = T0 - Config.RAIN_FIRST_AT - Config.RAIN_DURATION - 600
		local a = ServerFixtures.join(world, 1)
		local b = ServerFixtures.join(world, 2)
		world.nextBossAt = T0
		BossEvent.step(world, T0 - BOSS.WARNING_SECONDS)
		BossEvent.step(world, T0)
		local ctx = table.clone(bat)
		ctx.slimePosition = function(id: string)
			return if id == BossEvent.bossId(world) then BOSS_AT else nil
		end
		return world, a, b, ctx
	end

	it("a swing at the fighting boss in reach and in front adds a meter point", function()
		local world, a, _, ctx = fight()
		expect((BatTool.swing(world, a, T0 + 1, ctx, false))).toBe(true)
		expect(world.boss.fight.contributions[1]).toBe(1)
		expect(#moves).toBe(0) -- the boss is never launched
		poses[1] = { X = BOSS_AT.X - BOSS.HIT_REACH - 2, Y = 3, Z = ORIGIN.Z }
		local hit = BatTool.swing(world, a, T0 + 2, ctx, false)
		expect(hit).toBe(false)
		expect(world.boss.fight.contributions[1]).toBe(1)
		done()
	end)
	it("a swing at the boss carrier drops the boss on the spot", function()
		local world, a, b, ctx = fight()
		local t = T0 + 1
		while world.boss.fight.phase == "fight" do
			BatTool.forget(1)
			BatTool.swing(world, a, t, ctx, false)
			t += BOSS.HIT_GAP
		end
		local id = BossEvent.bossId(world) :: string
		expect((Carry.grab(world, 1, id, 1, t))).toBe(true)
		poses[2] = { X = ORIGIN.X + 6, Y = 3, Z = ORIGIN.Z }
		expect((BatTool.swing(world, b, t + 1, ctx, false))).toBe(false) -- facing away (+X) from player 1
		poses[2] = { X = ORIGIN.X - 6, Y = 3, Z = ORIGIN.Z }
		BatTool.forget(2)
		expect((BatTool.swing(world, b, t + 2, ctx, false))).toBe(true)
		expect(a.carry).toBeNil()
		expect(world.wild[id].position).toBe(ORIGIN)
		expect(b.lastSlapAt).toBe(t + 2)
		done()
	end)
end)
