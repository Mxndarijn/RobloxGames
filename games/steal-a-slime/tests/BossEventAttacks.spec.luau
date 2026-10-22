--!strict
-- The boss's attacks over World (src/server/BossEvent.luau, contract/boss-event.md "Attacks"): it winds up from a
-- stop once an attack is due; a struck player is knocked back and stunned; dazed hits count more; guards hold it out
-- of reach; spit puddles slow; it drops no slimes, during the fight or on a win.
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
	w.fountainTier = BOSS.SECRET_FOUNTAIN_TIER -- the Secret bosses may come too
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
		w.boss.fight.stage = 2
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

	it("bringing it home spills no slimes either", function()
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
		expect(after).toBe(before)
	end)
end)

-- Steps the fight every 1/30 s for `seconds` from `t`; returns the moves it went through, in order, and the time.
local function run(w: any, ctx: any, t: number, seconds: number): ({ any }, number)
	local moves = {}
	local last = -1
	local stop = t + seconds
	while t < stop do
		t += 1 / 30
		BossEvent.step(w, t, ctx)
		local wild = bossOf(w)
		local move = wild and wild.move
		if move and move.n ~= last then
			last = move.n
			table.insert(moves, move)
		end
	end
	return moves, t
end

local function kinds(moves: { any }): string
	local out = {}
	for _, m in moves do
		table.insert(out, m.kind)
	end
	return table.concat(out, ",")
end

describe("BossEvent signature attacks: every boss has one of its own", function()
	it("Goozilla's double stomp hits a grounded player once per ring", function()
		local w, ctx, at, launched = fight(1)
		expect(w.boss.fight.species).toBe("goozilla")
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local move = force(w, "attack", "start.1", t, 3)
		at[1] = { X = move.fx + 9, Y = 3, Z = move.fz }
		run(w, ctx, t, 2.5)
		expect(#launched).toBe(2)
	end)

	it("Queen Jelly heals when her guards outlast the call", function()
		local w, ctx = fight(1, 2)
		expect(w.boss.fight.species).toBe("queen_jelly")
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		force(w, "windup", "start.1", t, 0.05)
		BossEvent.step(w, t + 0.1, ctx)
		expect(bossOf(w).move.kind).toBe("rise")
		w.boss.fight.points = 30
		w.boss.fight.lastAnyHitAt = math.huge -- no drain in this test
		BossEvent.step(w, t + 0.1 + BOSS.GUARD_SECONDS + 0.05, ctx)
		expect(bossOf(w).move.kind).toBe("land")
		expect(w.boss.fight.points).toBeCloseTo(30 - 0.15 * BOSS.POINTS_PER_PLAYER, 1e-6)
	end)

	it("Pumpking hops at you three times, a ring on every landing, then is dazed", function()
		local w, ctx, at, launched = fight(1, 4)
		expect(w.boss.fight.species).toBe("pumpking")
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local move = force(w, "windup", "start.1", t, 0.05)
		at[1] = { X = move.fx + 4, Y = 3, Z = move.fz + 4 }
		local moves = run(w, ctx, t, 4)
		expect(string.find(kinds(moves), "hop,hop,hop,dazed", 1, true) ~= nil).toBe(true)
		expect(#launched >= 1).toBe(true)
	end)

	it("Mecha Goo's ricochet charge winds up again and rams a second time", function()
		local w, ctx, at = fight(1, 5)
		expect(w.boss.fight.species).toBe("mecha_goo")
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local move = force(w, "windup", "start.1", t, 0.05)
		at[1] = { X = move.fx + 20, Y = 3, Z = move.fz }
		local moves = run(w, ctx, t, 6)
		expect(string.find(kinds(moves), "attack,windup,attack,dazed", 1, true) ~= nil).toBe(true)
	end)

	it("Klawdius scuttles sideways, back and forth three times", function()
		local w, ctx, at = fight(1, 3)
		expect(w.boss.fight.species).toBe("klawdius")
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local move = force(w, "windup", "start.2", t, 0.05)
		at[1] = { X = move.fx + 15, Y = 3, Z = move.fz }
		local moves = run(w, ctx, t, 8)
		local legs = {}
		for _, m in moves do
			if m.kind == "attack" then
				table.insert(legs, m)
			end
		end
		expect(#legs).toBe(3)
		for _, leg in legs do
			local ux, uz = leg.tx - leg.fx, leg.tz - leg.fz
			local len = math.sqrt(ux * ux + uz * uz)
			if len > 0.5 then
				expect(math.abs((ux * leg.hx + uz * leg.hz) / len) < 1e-6).toBe(true) -- sideways to its facing
			end
		end
		local a = { legs[1].tx - legs[1].fx, legs[1].tz - legs[1].fz }
		local b = { legs[2].tx - legs[2].fx, legs[2].tz - legs[2].fz }
		if math.sqrt(a[1] ^ 2 + a[2] ^ 2) > 0.5 and math.sqrt(b[1] ^ 2 + b[2] ^ 2) > 0.5 then
			expect(a[1] * b[1] + a[2] * b[2] < 0).toBe(true) -- the second leg runs back
		end
	end)

	it("Goomancer's rune puddles burst into a ring that knocks back whoever is near", function()
		local w, ctx, at, launched = fight(1, 10)
		expect(w.boss.fight.species).toBe("goomancer")
		local t = T0 + BOSS.WARNING_SECONDS + BOSS.ARRIVE_SECONDS
		BossEvent.step(w, t, ctx)
		local move = force(w, "look", "", t, 0.05)
		w.boss.nextAttackAt = t
		w.boss.attackIndex = 0 -- its first attack: the rune spit
		at[1] = { X = move.fx + 12, Y = 3, Z = move.fz }
		local burst = BOSS.MOVES.goomancer.start[1].burst
		local _, thrown = run(w, ctx, t, 0.1 + BOSS.WINDUP_SECONDS + BOSS.SPIT_FLIGHT + 0.1)
		expect(#w.boss.puddles >= 1).toBe(true)
		at[1] = { X = w.boss.puddles[1].x + 5, Y = 3, Z = w.boss.puddles[1].z } -- step out of the slow, not far enough
		local before = #launched
		run(w, ctx, thrown, burst.delay + burst.radius / burst.speed + 0.2)
		expect(#launched > before).toBe(true)
	end)
end)
