--!strict
-- The fighting boss's walk (src/shared/BossWander.luau, contract/boss-event.md): it starts at the boss spot, never
-- leaves the boss area (outside the landing ring, clear of the parade lane and the goo drain), and walks slowly.
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
		expect(BossWander.allowed(polar(spot, Fountain.LANDING_RING_OUTER - 1))).toBe(false)
		expect(BossWander.allowed(polar(spot, ParadeLane.LANE_RADIUS))).toBe(false)
		expect(BossWander.allowed(polar(spot + math.deg(BOSS.WANDER_ARC) + 5, BOSS.SPOT_RADIUS))).toBe(false)
		expect(BossWander.allowed(ParadeLane.DRAIN.x, ParadeLane.DRAIN.z)).toBe(false)
	end)
end)

describe("BossWander.plan", function()
	it("starts at the boss spot and covers the whole fight with legs back to back", function()
		local plan = BossWander.plan(BossWander.seed("boss-1"), T0, BOSS.FIGHT_SECONDS)
		expect(#plan.legs > 0).toBe(true)
		expect(dist(plan.legs[1].from, BossWander.home()) < 1e-9).toBe(true)
		expect(plan.legs[1].startAt).toBe(T0)
		for i, leg in plan.legs do
			expect(leg.moveAt - leg.startAt >= BOSS.WANDER_PAUSE[1] - 1e-9).toBe(true)
			expect(leg.moveAt - leg.startAt <= BOSS.WANDER_PAUSE[2] + 1e-9).toBe(true)
			if i > 1 then
				expect(leg.startAt).toBe(plan.legs[i - 1].endAt)
				expect(dist(leg.from, plan.legs[i - 1].to) < 1e-9).toBe(true)
			end
		end
		expect(plan.legs[#plan.legs].endAt >= T0 + BOSS.FIGHT_SECONDS).toBe(true)
	end)
	it("every leg of many plans stays in the area, at WANDER_SPEED", function()
		local walked = 0
		for n = 1, 40 do
			local plan = BossWander.plan(BossWander.seed(`boss-{n}`), T0, BOSS.FIGHT_SECONDS)
			for _, leg in plan.legs do
				expect(BossWander.clearPath(leg.from, leg.to)).toBe(true)
				local step = dist(leg.from, leg.to)
				if step > 0 then
					walked += 1
					expect(math.abs(step / (leg.endAt - leg.moveAt) - BOSS.WANDER_SPEED) < 1e-6).toBe(true)
				end
			end
		end
		expect(walked > 40).toBe(true) -- it really moves
	end)
	it("is the same for the same seed", function()
		local a = BossWander.plan(BossWander.seed("same"), T0, BOSS.FIGHT_SECONDS)
		local b = BossWander.plan(BossWander.seed("same"), T0, BOSS.FIGHT_SECONDS)
		expect(#a.legs).toBe(#b.legs)
		expect(dist(a.legs[#a.legs].to, b.legs[#b.legs].to)).toBe(0)
	end)
end)

describe("BossWander.pose", function()
	it("stands, then eases along the leg, and stays at the end after the plan", function()
		local plan = BossWander.plan(BossWander.seed("pose"), T0, BOSS.FIGHT_SECONDS)
		local leg = plan.legs[1]
		for _, l in plan.legs do
			if dist(l.from, l.to) > 0 then
				leg = l
				break
			end
		end
		local standing = BossWander.pose(plan, leg.startAt + 0.01)
		expect(dist(standing, leg.from) < 1e-9).toBe(true)
		local mid, face = BossWander.pose(plan, (leg.moveAt + leg.endAt) / 2)
		local half = { (leg.from[1] + leg.to[1]) / 2, (leg.from[2] + leg.to[2]) / 2 }
		expect(dist(mid, half) < 1e-6).toBe(true)
		expect(math.abs(math.sqrt(face[1] ^ 2 + face[2] ^ 2) - 1) < 1e-9).toBe(true)
		local after = BossWander.pose(plan, T0 + BOSS.FIGHT_SECONDS * 10)
		expect(dist(after, plan.legs[#plan.legs].to) < 1e-9).toBe(true)
	end)
end)
