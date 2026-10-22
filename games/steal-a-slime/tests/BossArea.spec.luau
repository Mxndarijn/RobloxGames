--!strict
-- Where the fighting boss may stand (src/shared/BossArea.luau, contract/boss-event.md): the plaza inside the parade
-- lane round the boss spot, clear of the landing ring, the lane and the goo drain; stroll targets with clear walks.
local BossArea = require("../src/shared/BossArea")
local Config = require("../src/shared/Config")
local Fountain = require("../src/shared/Fountain")
local ParadeLane = require("../src/shared/ParadeLane")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOSS = Config.BOSS

local function polar(degrees: number, radius: number): (number, number)
	local a = math.rad(degrees)
	return math.cos(a) * radius, math.sin(a) * radius
end

describe("BossArea.allowed", function()
	it("the boss spot is in the area", function()
		local x, z = BossArea.home()
		expect(BossArea.allowed(x, z)).toBe(true)
	end)
	it("keeps out of the landing ring, the lane, the drain and anything past WANDER_ARC", function()
		local spot = math.deg(BOSS.SPOT_ANGLE)
		expect(BossArea.allowed(polar(spot, Fountain.LANDING_RING_OUTER + BossArea.BODY_RADIUS - 0.5))).toBe(false)
		expect(BossArea.allowed(polar(spot, ParadeLane.LANE_RADIUS))).toBe(false)
		expect(BossArea.allowed(polar(spot + math.deg(BOSS.WANDER_ARC) + 5, BOSS.SPOT_RADIUS))).toBe(false)
		expect(BossArea.allowed(ParadeLane.DRAIN.x, ParadeLane.DRAIN.z)).toBe(false)
		expect(BossArea.allowed(0 / 0, 0)).toBe(false)
	end)
end)

describe("BossArea.pick", function()
	it("finds stroll targets STROLL_MIN..STROLL_MAX away with a clear walk", function()
		local rng = Rng.new(7)
		local x, z = BossArea.home()
		for _ = 1, 60 do
			local tx, tz = BossArea.pick(rng, x, z, nil)
			assert(tx and tz, "a target fits round the boss spot")
			local d = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
			expect(d >= BOSS.STROLL_MIN - 1e-6 and d <= BOSS.STROLL_MAX + 1e-6).toBe(true)
			expect(BossArea.clear(x, z, tx, tz)).toBe(true)
			x, z = tx, tz -- walk on from there: it never leaves the area
		end
	end)
	it("heads for `toward` when it is given", function()
		local x, z = BossArea.home()
		local toward =
			{ x + 40 * math.cos(BOSS.SPOT_ANGLE + math.pi / 2), z + 40 * math.sin(BOSS.SPOT_ANGLE + math.pi / 2) }
		local before = (x - toward[1]) ^ 2 + (z - toward[2]) ^ 2
		local tx, tz = BossArea.pick(Rng.new(3), x, z, toward)
		assert(tx and tz, "target")
		expect((tx - toward[1]) ^ 2 + (tz - toward[2]) ^ 2 < before).toBe(true)
	end)
end)

describe("BossArea.reach", function()
	it("stops at the edge of the area", function()
		local x, z = BossArea.home()
		local ux, uz = math.cos(BOSS.SPOT_ANGLE), math.sin(BOSS.SPOT_ANGLE) -- straight out toward the lane
		local ex, ez, full = BossArea.reach(x, z, ux, uz, 200)
		expect(full).toBe(false)
		expect(BossArea.allowed(ex, ez)).toBe(true)
		expect(BossArea.allowed(ex + ux * BossArea.PATH_STEP, ez + uz * BossArea.PATH_STEP)).toBe(false)
	end)
end)
