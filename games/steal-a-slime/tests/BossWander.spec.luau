--!strict
-- The fighting boss's walk (src/shared/BossWander.luau, contract/boss-event.md): laps of a smooth racetrack through
-- the boss spot, walked without stopping, that never leave the boss area (outside the landing ring, clear of the
-- parade lane and the goo drain) and never turn sharply.
local BossWander = require("../src/shared/BossWander")
local Config = require("../src/shared/Config")
local Fountain = require("../src/shared/Fountain")
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOSS = Config.BOSS
local T0 = 1000

local function dist(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

local function angleOf(face: { number }): number
	return math.atan2(face[2], face[1])
end

local function gap(a: number, b: number): number
	return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
end

describe("BossWander area", function()
	it("the boss spot is in the area", function()
		local home = BossWander.home()
		expect(BossWander.allowed(home[1], home[2])).toBe(true)
	end)
	it("keeps out of the landing ring, the lane, the drain and anything past WANDER_ARC", function()
		local function polar(degrees: number, radius: number): (number, number)
			local a = math.rad(degrees)
			return math.cos(a) * radius, math.sin(a) * radius
		end
		local spot = math.deg(BOSS.SPOT_ANGLE)
		expect(BossWander.allowed(polar(spot, Fountain.LANDING_RING_OUTER + BossWander.BODY_RADIUS - 0.5))).toBe(false)
		expect(BossWander.allowed(polar(spot, ParadeLane.LANE_RADIUS))).toBe(false)
		expect(BossWander.allowed(polar(spot + math.deg(BOSS.WANDER_ARC) + 5, BOSS.SPOT_RADIUS))).toBe(false)
		expect(BossWander.allowed(ParadeLane.DRAIN.x, ParadeLane.DRAIN.z)).toBe(false)
	end)
end)

describe("BossWander.plan", function()
	it("starts on the track by the boss spot and is long enough to walk the whole fight", function()
		local directions = {}
		for n = 1, 40 do
			local plan = BossWander.plan(BossWander.seed(`boss-{n}`), T0, BOSS.FIGHT_SECONDS)
			expect(dist(plan.points[1], plan.home)).toBe(0)
			expect(dist(plan.home, BossWander.home()) <= BossWander.TRACK_HALF_WIDTH + BossWander.MARGIN).toBe(true)
			expect(plan.length >= BossWander.walked(BOSS.FIGHT_SECONDS)).toBe(true)
			local a, b = plan.points[1], plan.points[2]
			directions[(a[1] * b[2] - a[2] * b[1]) > 0] = true -- counter-clockwise or clockwise round the fountain
		end
		expect(directions[true] and directions[false]).toBe(true) -- both directions happen
	end)
	it("roams a good stretch of the plaza, not a corner of it", function()
		local plan = BossWander.plan(BossWander.seed("roam"), T0, BOSS.FIGHT_SECONDS)
		local lo, hi = math.huge, -math.huge
		for _, p in plan.points do
			local a = math.atan2(p[2], p[1])
			lo, hi = math.min(lo, a), math.max(hi, a)
		end
		expect(hi - lo > BOSS.WANDER_ARC).toBe(true)
	end)
	it("every point of many paths stays in the area, with no gap wider than a sample", function()
		for n = 1, 40 do
			local plan = BossWander.plan(BossWander.seed(`boss-{n}`), T0, BOSS.FIGHT_SECONDS)
			for i, p in plan.points do
				expect(BossWander.allowed(p[1], p[2])).toBe(true)
				if i > 1 then
					expect(dist(p, plan.points[i - 1]) <= BossWander.POINT_STEP * 2).toBe(true)
				end
			end
		end
	end)
	it("is the same for the same seed", function()
		local a = BossWander.plan(BossWander.seed("same"), T0, BOSS.FIGHT_SECONDS)
		local b = BossWander.plan(BossWander.seed("same"), T0, BOSS.FIGHT_SECONDS)
		expect(#a.points).toBe(#b.points)
		expect(dist(a.points[#a.points], b.points[#b.points])).toBe(0)
	end)
end)

describe("BossWander.pose", function()
	it("speeds up over EASE_SECONDS, then walks at WANDER_SPEED without stopping", function()
		local plan = BossWander.plan(BossWander.seed("pace"), T0, BOSS.FIGHT_SECONDS)
		expect(dist(BossWander.pose(plan, T0), plan.home) < 1e-9).toBe(true)
		local dt = 0.1
		local t = T0 + BossWander.EASE_SECONDS
		while t < T0 + BOSS.FIGHT_SECONDS - dt do
			local a = BossWander.pose(plan, t)
			local b = BossWander.pose(plan, t + dt)
			-- along a curve the chord is a little shorter than the arc, never longer, never near a stop
			local moved = dist(a, b)
			expect(moved <= BOSS.WANDER_SPEED * dt + 1e-6).toBe(true)
			expect(moved >= BOSS.WANDER_SPEED * dt * 0.8).toBe(true)
			t += dt
		end
	end)
	it("turns gradually: the heading never jumps from one frame to the next", function()
		local worst = 0
		for n = 1, 20 do
			local plan = BossWander.plan(BossWander.seed(`turn-{n}`), T0, BOSS.FIGHT_SECONDS)
			local frame = 1 / 60
			local _, last = BossWander.pose(plan, T0 + frame)
			local t = T0 + frame
			while t < T0 + BOSS.FIGHT_SECONDS do
				t += frame
				local _, face = BossWander.pose(plan, t)
				worst = math.max(worst, gap(angleOf(face), angleOf(last)))
				last = face
			end
		end
		expect(worst < math.rad(3)).toBe(true) -- at 60 fps: under 3 degrees a frame, even in the round ends
	end)
	it("stays at the end of the path after it", function()
		local plan = BossWander.plan(BossWander.seed("end"), T0, BOSS.FIGHT_SECONDS)
		local after = BossWander.pose(plan, T0 + BOSS.FIGHT_SECONDS * 10)
		expect(dist(after, plan.points[#plan.points]) < 1e-9).toBe(true)
	end)
end)
