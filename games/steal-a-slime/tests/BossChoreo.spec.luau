--!strict
-- The fighting boss's moves (src/shared/BossChoreo.luau, contract/boss-event.md "Moves"): it lands, strolls between
-- stops and looks at players, all inside the boss area; poses are smooth and the same on server and clients.
local BossArea = require("../src/shared/BossArea")
local BossChoreo = require("../src/shared/BossChoreo")
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOSS = Config.BOSS
local T0 = 1000

local function none(_slot: string): BossChoreo.Attack?
	return nil
end

local function input(now: number, rng: any, players: { { number } }?): BossChoreo.Input
	return { now = now, rng = rng, players = players or {}, target = nil, speed = 1, attack = nil, resolve = none }
end

-- Runs the boss for `seconds` of moves; returns them in order.
local function run(seconds: number, players: { { number } }?, seed: number?): { BossChoreo.Move }
	local rng = Rng.new(seed or 11)
	local move = BossChoreo.first(T0, 0, 0)
	local moves = { move }
	while move.at < T0 + seconds do
		move = BossChoreo.after(move, input(move.at + move.seconds, rng, players))
		table.insert(moves, move)
	end
	return moves
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

describe("BossChoreo moves", function()
	it("lands on the boss spot, then strolls and stops to look", function()
		local moves = run(120)
		local hx, hz = BossArea.home()
		expect(moves[1].kind).toBe("arrive")
		expect(math.abs(moves[1].tx - hx) < 1e-9 and math.abs(moves[1].tz - hz) < 1e-9).toBe(true)
		local kinds = {}
		for _, m in moves do
			kinds[m.kind] = (kinds[m.kind] or 0) + 1
		end
		expect((kinds.stroll or 0) >= 4).toBe(true)
		expect((kinds.look or 0) >= 4).toBe(true)
	end)

	it("never leaves the boss area and never jumps between moves", function()
		for seed = 1, 6 do
			local moves = run(BOSS.FIGHT_SECONDS, nil, seed)
			for i, m in moves do
				for k = 0, 10 do
					local x, z = BossChoreo.pose(m, m.at + m.seconds * k / 10)
					expect(BossArea.allowed(x, z)).toBe(true)
				end
				if i > 1 then
					local prev = moves[i - 1]
					local ax, az = BossChoreo.pose(prev, prev.at + prev.seconds)
					local bx, bz = BossChoreo.pose(m, m.at)
					expect(math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) < 1e-6).toBe(true)
					expect(m.at).toBe(prev.at + prev.seconds) -- no gap in time either
				end
			end
		end
	end)

	it("eases in and out of every stroll and never walks faster than STROLL_SPEED", function()
		for _, m in run(BOSS.FIGHT_SECONDS) do
			if m.kind == "stroll" then
				local dt = 1 / 60
				local fastest = 0
				local t = m.at
				local x0, z0 = BossChoreo.pose(m, t)
				local x1, z1 = BossChoreo.pose(m, t + dt)
				expect(math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) / dt < 0.5).toBe(true) -- sets off from a stand
				while t < m.at + m.seconds do
					local ax, az = BossChoreo.pose(m, t)
					local bx, bz = BossChoreo.pose(m, t + dt)
					fastest = math.max(fastest, math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) / dt)
					t += dt
				end
				expect(fastest <= BOSS.STROLL_SPEED * 1.25).toBe(true)
			end
		end
	end)

	it("turns to look at the nearest player", function()
		local x, z = BossArea.home()
		local player = { x + 10, z - 4 }
		local rng = Rng.new(2)
		local first = BossChoreo.first(T0, 0, 0)
		local look = BossChoreo.after(first, input(first.at + first.seconds, rng, { player, { x - 60, z } }))
		expect(look.kind).toBe("look")
		local want = math.atan2(player[2] - z, player[1] - x)
		expect(math.abs(wrap(math.atan2(look.hz, look.hx) - want)) < 1e-6).toBe(true)
	end)

	it("winds up an attack from a stop when one is due, aimed at the target", function()
		local rng = Rng.new(5)
		local first = BossChoreo.first(T0, 0, 0)
		local look = BossChoreo.after(first, input(first.at + first.seconds, rng))
		local attack: BossChoreo.Attack = { kind = "charge", distance = 30, speed = 30 }
		local x, z = BossArea.home()
		local due = input(look.at + look.seconds, rng)
		due.attack = "start.1"
		due.target = { x - 10, z }
		due.resolve = function(slot: string): BossChoreo.Attack?
			return if slot == "start.1" then attack else nil
		end
		local windup = BossChoreo.after(look, due)
		expect(windup.kind).toBe("windup")
		expect(windup.slot).toBe("start.1")
		expect(windup.hx < -0.99).toBe(true)
		local charge = BossChoreo.after(windup, due)
		expect(charge.kind).toBe("attack")
		local dazed = BossChoreo.after(charge, due)
		expect(dazed.kind).toBe("dazed")
		expect(dazed.seconds).toBe(BOSS.DAZED_SECONDS)
	end)

	it("arrives from the sky and floats up while its guards are out", function()
		local first = BossChoreo.first(T0, 0, 0)
		local _, _, _, _, high = BossChoreo.pose(first, T0)
		local _, _, _, _, landed = BossChoreo.pose(first, T0 + BOSS.ARRIVE_FALL)
		expect(high).toBe(BOSS.ARRIVE_HEIGHT)
		expect(landed < 1e-6).toBe(true)
		local rise = BossChoreo.hold("rise", first, T0 + 5, BOSS.GUARD_SECONDS)
		local _, _, _, _, up = BossChoreo.pose(rise, T0 + 5 + BOSS.RISE_SECONDS)
		expect(math.abs(up - BOSS.RISE_HEIGHT) < 1e-6).toBe(true)
	end)
end)

describe("BossChoreo encoding", function()
	it("round-trips a move through its attribute string, in world studs", function()
		local move = BossChoreo.first(T0 + 0.25, 120.5, -33.25)
		local back = BossChoreo.decode(BossChoreo.encode(move))
		assert(back, "decoded")
		expect(back.kind).toBe("arrive")
		expect(back.n).toBe(move.n)
		local ax, az = BossChoreo.world(move, T0 + 1)
		local bx, bz = BossChoreo.world(back, T0 + 1)
		expect(math.abs(ax - bx) < 1e-2 and math.abs(az - bz) < 1e-2).toBe(true)
		local px = BossChoreo.pose(move, T0 + 1)
		expect(math.abs(ax - (px + 120.5)) < 1e-9).toBe(true)
	end)
	it("refuses junk", function()
		expect(BossChoreo.decode(nil)).toBeNil()
		expect(BossChoreo.decode("1|fly|x|1|1|1|1|1|1|1|1|1|1")).toBeNil()
		expect(BossChoreo.decode("1|look||nan|1|1|1|1|1|1|1|1|1")).toBeNil()
		expect(BossChoreo.decode("1|look")).toBeNil()
	end)
end)
