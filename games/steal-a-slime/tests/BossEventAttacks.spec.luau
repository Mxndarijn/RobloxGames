--!strict
-- The boss's attacks over World (src/server/BossEvent.luau, contract/boss-event.md "Attacks"): it winds up from a
-- stop once an attack is due; a struck player is knocked back and stunned; dazed hits count more; guards hold it out
-- of reach; spit puddles slow; bringing it home spills a victory shower for every helper.
local BossChoreo = require("../src/shared/BossChoreo")
local BossEvent = require("../src/server/BossEvent")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local ServerFixtures = require("./ServerFixtures")
local Shop = require("../src/shared/Shop")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local BOSS = Config.BOSS

type Vec = { X: number, Y: number, Z: number }

-- A world with `players` joined, the boss of rotation slot `index` about to arrive, and a ctx whose players stand
-- where `at` says (plaza = world: origin 0).
local function fight(players: number, index: number?): (any, any, { [number]: Vec }, { number })
	local w = ServerFixtures.world()
	w.startedAt = T0 - Config.RAIN_FIRST_AT - Config.RAIN_DURATION - 600
	w.nextSpawnAt = math.huge
	for userId = 1, players do
		ServerFixtures.join(w, userId, nil, 0)
	end
	w.bossIndex = index or 1
	w.nextBossAt = T0 + BOSS.WARNING_SECONDS
	local at: { [number]: Vec } = {}
	local launched: { number } = {}
	local ctx = {
		pose = function(userId: number): (Vec?, Vec?)
			return at[userId], { X = 1, Y = 0, Z = 0 }
		end,
		plazaOrigin = function(): Vec
			return { X = 0, Y = 0, Z = 0 }
		end,
		airborne = function(_userId: number): boolean
			return false
		end,
		launch = function(userId: number, _push: Vec, _landing: Vec): boolean
			table.insert(launched, userId)
			return true
		end,
	}
	BossEvent.step(w, T0, ctx)
	BossEvent.step(w, T0 + BOSS.WARNING_SECONDS, ctx)
	return w, ctx, at, launched
end

local function bossOf(w: any): any
	return w.wild[BossEvent.bossId(w) :: string]
end

-- Puts the boss into move `kind` with attack `slot`, standing at its current spot, from `now`.
local function force(w: any, kind: string, slot: string, now: number, seconds: number): any
	local wild = bossOf(w)
	wild.move = BossChoreo.hold(kind :: any, wild.move, now, seconds, slot)
	return wild.move
end

describe("BossEvent attacks", function()
	it("winds up an attack from a stop once FIRST_ATTACK has passed", function()
		local w, ctx, at = fight(1)
		local hx, hz = bossOf(w).move.tx, bossOf(w).move.tz
		at[1] = { X = hx + 10, Y = 3, Z = hz }
		local t = T0 + BOSS.WARNING_SECONDS
		local seen = {}
		while t < T0 + BOSS.WARNING_SECONDS + BOSS.FIRST_ATTACK + 15 do
			t += 1 / 30
			BossEvent.step(w, t, ctx)
			local move = bossOf(w) and bossOf(w).move
			if move then
				seen[move.kind] = true
			end
		end
		expect(seen.windup).toBe(true)
		expect(seen.attack).toBe(true)
		expect(seen.dazed).toBe(true)
	end)

	it("a stomp's ring knocks a grounded player back and stuns their bat", function()
		local w, ctx, at, launched = fight(1)
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local move = force(w, "attack", "start.1", t, BOSS.RING_DELAY + 1.5)
		at[1] = { X = move.fx + 8, Y = 3, Z = move.fz }
		for i = 1, 60 do
			BossEvent.step(w, t + i / 30, ctx)
		end
		expect(launched[1]).toBe(1)
		local s = w.sessions[1]
		expect(BossEvent.stunned(s, t + 1)).toBe(true)
		local ok, reason = BossEvent.hit(w, s, t + 1, at[1], ctx)
		expect(ok).toBe(false)
		expect(reason).toBe("stunned")
		expect(BossEvent.stunned(s, t + 1 + BOSS.STUN_SECONDS + 1)).toBe(false)
	end)

	it("hits while it is dazed count DAZED_MULTIPLIER points", function()
		local w, ctx, at = fight(2)
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		force(w, "dazed", "", t, BOSS.DAZED_SECONDS)
		at[1] = { X = 0, Y = 3, Z = 0 }
		expect((BossEvent.hit(w, w.sessions[1], t + 0.1, at[1], ctx))).toBe(true)
		expect(w.boss.fight.contributions[1]).toBe(BOSS.DAZED_MULTIPLIER)
		expect(w.boss.lastHit.points).toBe(BOSS.DAZED_MULTIPLIER)
		local view = BossEvent.view(w, w.sessions[1], t + 0.2)
		expect(view.move).toBe("dazed")
		expect(view.multiplier).toBe(BOSS.DAZED_MULTIPLIER)
	end)

	it("Queen Jelly floats out of reach until every guard is popped, then lands dazed", function()
		local w, ctx = fight(2, 2) -- rotation slot 2: queen_jelly
		expect(w.boss.fight.species).toBe("queen_jelly")
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local wild = bossOf(w)
		wild.move = BossChoreo.hold("windup", wild.move, t, 0.05, "start.1")
		BossEvent.step(w, t + 0.1, ctx) -- the windup ends: it rises and calls its guards
		expect(wild.move.kind).toBe("rise")
		expect(#w.boss.guards).toBe(3)
		local s = w.sessions[1]
		local ok, reason = BossEvent.hit(w, s, t + 0.2, nil, ctx)
		expect(ok).toBe(false)
		expect(reason).toBe("it's out of reach")
		local before = w.boss.fight.points
		local now = t + 0.3
		for _, g in table.clone(w.boss.guards) do
			local from = { X = g.x - 3, Y = 3, Z = g.z }
			expect(BossEvent.hitGuard(w, s, now, from, { X = 1, Y = 0, Z = 0 }, ctx)).toBe(true)
			now += 0.5
		end
		expect(w.boss.fight.points).toBe(before + 3 * BOSS.GUARD_POINTS)
		expect(wild.move.kind).toBe("land")
		expect(wild.move.slot).toBe("daze")
		BossEvent.step(w, wild.move.at + wild.move.seconds + 0.01, ctx)
		expect(wild.move.kind).toBe("dazed")
	end)

	it("a spit's puddles slow the players standing in them", function()
		local w, ctx, at = fight(1)
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local wild = bossOf(w)
		at[1] = { X = wild.move.tx + 6, Y = 3, Z = wild.move.tz }
		wild.move = BossChoreo.hold("look", wild.move, t, 0.05)
		w.boss.nextAttackAt = t
		w.boss.attackIndex = 1 -- the second available attack: Goozilla's spit (its phase attack)
		w.boss.fight.points = BOSS.POINTS_PER_PLAYER * BOSS.PHASE_AT + 2 -- the phase is on (with room for the drain)
		w.boss.fight.shed = 2
		BossEvent.step(w, t + 0.1, ctx)
		expect(wild.move.kind).toBe("windup")
		expect(#w.boss.targets).toBe(3)
		local now = wild.move.at + wild.move.seconds + 0.01
		BossEvent.step(w, now, ctx) -- thrown
		expect(#w.boss.spits).toBe(3)
		BossEvent.step(w, now + BOSS.SPIT_FLIGHT + 0.05, ctx) -- landed
		expect(#w.boss.puddles).toBe(3)
		local s = w.sessions[1]
		local slowed = Carry.targetWalkSpeed(s, now + BOSS.SPIT_FLIGHT + 0.1)
		expect(slowed).toBeCloseTo(Shop.walkSpeed(s.data) * 0.5, 1e-6)
	end)

	it("bringing it home spills a victory shower slime for every helper", function()
		local w, ctx = fight(2)
		local t = T0 + BOSS.WARNING_SECONDS
		local i = 0
		while w.boss.fight.phase == "fight" do
			i += 1
			BossEvent.hit(w, w.sessions[1], t, nil, ctx)
			if i % 2 == 0 then
				BossEvent.hit(w, w.sessions[2], t, nil, ctx)
			end
			t += BOSS.HIT_GAP
		end
		local id = BossEvent.bossId(w) :: string
		t += BOSS.SHRINK_SECONDS
		expect((Carry.grab(w, 1, id, 1, t))).toBe(true)
		expect((Carry.deposit(w, 1, t + 1))).toBe(true)
		local before = 0
		for _ in w.wild do
			before += 1
		end
		BossEvent.step(w, t + 1.1, ctx)
		local after = 0
		for _ in w.wild do
			after += 1
		end
		expect(after - before).toBe(2 * BOSS.WIN_SHOWER)
	end)
end)
