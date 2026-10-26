--!strict
-- Boss attacks as geometry (src/shared/BossAttacks.luau, contract/boss-event.md "Attacks"): which attacks each boss
-- has, who a ring / cone / charge strikes, what a bat hit counts, and where guards stand.
local BossAttacks = require("../src/shared/BossAttacks")
local BossChoreo = require("../src/shared/BossChoreo")
local Config = require("../src/shared/Config")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOSS = Config.BOSS
local T0 = 1000

local function attackMove(
	kind: string,
	fx: number,
	fz: number,
	tx: number,
	tz: number,
	seconds: number
): BossChoreo.Move
	return {
		n = 5,
		kind = kind :: any,
		slot = "start.1",
		at = T0,
		seconds = seconds,
		fx = fx,
		fz = fz,
		tx = tx,
		tz = tz,
		hx = 1,
		hz = 0,
		ox = 0,
		oz = 0,
	}
end

describe("BossAttacks config", function()
	it("every boss species in the roster has a start attack, and every attack has a known kind", function()
		local known = { ring = true, spit = true, guards = true, cone = true, charge = true, vent = true, hops = true }
		for _, entry in SlimeRoster.ofKind("boss") do
			do
				local moves = (BOSS.MOVES :: any)[entry.id]
				assert(moves, `{entry.id} has moves`)
				expect(#BossAttacks.available(entry.id, 0) >= 1).toBe(true)
				for _, name in { "start", "phase" } do
					for _, attack in moves[name] or {} do
						expect(known[attack.kind]).toBe(true)
					end
				end
			end
		end
	end)
	it("every boss has at least two real attacks from the start, and more from PHASE_AT", function()
		for species in BOSS.MOVES do
			local early = BossAttacks.available(species, 0)
			expect(`{species}: {#early >= 2}`).toBe(`{species}: true`)
			expect(`{species}: {#BossAttacks.available(species, BOSS.PHASE_AT) > #early}`).toBe(`{species}: true`)
		end
	end)
	it("adds the phase attacks from PHASE_AT, never a passive vent", function()
		expect(table.concat(BossAttacks.available("goozilla", 0), ",")).toBe("start.1,start.2")
		expect(table.concat(BossAttacks.available("goozilla", BOSS.PHASE_AT), ",")).toBe(
			"start.1,start.2,phase.1,phase.2"
		)
		expect(table.concat(BossAttacks.available("mecha_goo", 1), ",")).toBe("start.1,start.2,phase.1,phase.2")
		expect(BossAttacks.vent("mecha_goo", 0)).toBeNil()
		expect(BossAttacks.vent("mecha_goo", BOSS.PHASE_AT) ~= nil).toBe(true)
		expect(BossAttacks.get("goozilla", "nope")).toBeNil()
	end)
end)

describe("BossAttacks.strikes", function()
	local ring = { kind = "ring", radius = 20, speed = 20, push = 40 }
	it("a ring hits a grounded player as it passes them, never a jumping one", function()
		local move = attackMove("attack", 0, 0, 0, 0, BOSS.RING_DELAY + 1)
		local at10 = T0 + BOSS.RING_DELAY + 10 / 20 -- the ring reaches 10 studs here
		local player = { x = 10, z = 0, airborne = false }
		expect(BossAttacks.strikes(move, ring, T0, at10 - 0.2, player)).toBe(false) -- not there yet
		expect(BossAttacks.strikes(move, ring, at10 - 0.02, at10 + 0.02, player)).toBe(true)
		expect(BossAttacks.strikes(move, ring, at10 - 0.02, at10 + 0.02, { x = 10, z = 0, airborne = true })).toBe(
			false
		)
		expect(BossAttacks.strikes(move, ring, at10 + 0.3, at10 + 0.35, player)).toBe(false) -- it has passed
		expect(BossAttacks.strikes(move, ring, T0, T0 + 5, { x = 30, z = 0 })).toBe(false) -- past its radius
	end)
	it("a cone pushes once, inside its radius and angle", function()
		local cone = { kind = "cone", radius = 18, angle = 90, push = 45 }
		local move = attackMove("attack", 0, 0, 0, 0, BOSS.STRIKE_SECONDS)
		local t0, t1 = T0, T0 + BOSS.CONE_HIT_AT + 0.01
		expect(BossAttacks.strikes(move, cone, t0, t1, { x = 10, z = 5 })).toBe(true) -- in front
		expect(BossAttacks.strikes(move, cone, t0, t1, { x = -10, z = 0 })).toBe(false) -- behind
		expect(BossAttacks.strikes(move, cone, t0, t1, { x = 25, z = 0 })).toBe(false) -- too far
		expect(BossAttacks.strikes(move, cone, t1, t1 + 0.1, { x = 10, z = 0 })).toBe(false) -- only at the push
	end)
	it("a charge hits whoever its body runs over", function()
		local charge = { kind = "charge", distance = 30, speed = 30, width = 8, push = 50 }
		local move = attackMove("attack", 0, 0, 30, 0, 1)
		local mid = T0 + 0.5
		local x = BossChoreo.pose(move, mid)
		expect(BossAttacks.strikes(move, charge, mid - 0.02, mid, { x = x, z = 3 })).toBe(true)
		expect(BossAttacks.strikes(move, charge, mid - 0.02, mid, { x = x, z = 20 })).toBe(false)
	end)
end)

describe("BossAttacks.hitValue", function()
	it("counts 1 normally, DAZED_MULTIPLIER while dazed, the vent's from behind, nothing while it floats", function()
		local dazed = attackMove("dazed", 0, 0, 0, 0, BOSS.DAZED_SECONDS)
		expect(BossAttacks.hitValue("goozilla", 0, attackMove("look", 0, 0, 0, 0, 1), T0, nil)).toBe(1)
		expect(BossAttacks.hitValue("goozilla", 0, dazed, T0, { 5, 0 })).toBe(BOSS.DAZED_MULTIPLIER)
		local vent = BossAttacks.vent("mecha_goo", 1) :: any
		expect(BossAttacks.hitValue("mecha_goo", 1, dazed, T0, { -5, 0 })).toBe(vent.multiplier) -- from behind
		expect(BossAttacks.hitValue("mecha_goo", 1, dazed, T0, { 5, 0 })).toBe(BOSS.DAZED_MULTIPLIER) -- in front
		local points, why = BossAttacks.hitValue("queen_jelly", 0, attackMove("rise", 0, 0, 0, 0, 5), T0, nil)
		expect(points).toBeNil()
		expect(why).toBe("it's out of reach")
	end)
end)

describe("BossAttacks.guardSpots", function()
	it("puts the guards GUARD_RADIUS round the boss, the first in front", function()
		local spots = BossAttacks.guardSpots(10, 0, 1, 0, 3)
		expect(#spots).toBe(3)
		expect(spots[1][1]).toBeCloseTo(10 + BOSS.GUARD_RADIUS, 1e-9)
		for _, s in spots do
			expect(math.sqrt((s[1] - 10) ^ 2 + s[2] ^ 2)).toBeCloseTo(BOSS.GUARD_RADIUS, 1e-9)
		end
	end)
end)
