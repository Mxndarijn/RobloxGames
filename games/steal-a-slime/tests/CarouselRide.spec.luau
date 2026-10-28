--!strict
-- The Exclusive Shop carousel's motion (Visuals.CarouselRide, contract/exclusive-shop.md §7): the turn rate, the
-- riders on their circle, the bob range and phases, the seats on the poles and the rider size.
local CarouselRide = require("../src/visuals/shared/CarouselRide")
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SHOP = Config.EXCLUSIVE_SHOP
local LAYOUT = WorldLayout.EXCLUSIVE_CAROUSEL
local TAU = 2 * math.pi
local PERIOD = 60 / SHOP.spinRpm -- seconds a turn takes
local T0 = 1_790_000_000 -- a server time in 2026

local function radius(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

local function wrap(a: number): number
	return (a + math.pi) % TAU - math.pi
end

describe("carousel turn", function()
	it("turns once every 60 / spinRpm seconds, and stays in 0..2pi on the server clock", function()
		expect(CarouselRide.angle(0)).toBe(0)
		expect(CarouselRide.angle(PERIOD / 4)).toBeCloseTo(math.pi / 2, 6)
		expect(math.abs(wrap(CarouselRide.angle(T0 + PERIOD) - CarouselRide.angle(T0))) < 1e-5).toBe(true)
		for _, t in { 0, 1.5, 17, T0, T0 + 0.37 } do
			local a = CarouselRide.angle(t)
			expect(a >= 0 and a < TAU).toBe(true)
		end
	end)
end)

describe("carousel riders", function()
	it("puts the 8 riders on one circle round the axis, 45 degrees apart, at the saddle heights", function()
		expect(CarouselRide.RIDERS).toBe(8)
		local k = LAYOUT.scale
		local r0: number? = nil
		for i = 1, CarouselRide.RIDERS do
			local p = CarouselRide.spot(i)
			local r = radius(p[1], p[3])
			r0 = r0 or r
			expect(r).toBeCloseTo(r0 :: number, 3)
			expect(p[2]).toBeCloseTo(LAYOUT.riders[i][3] * k, 6)
			-- inside the deck
			expect(r < LAYOUT.deckRadius * k).toBe(true)
			local nextSpot = CarouselRide.spot(i % CarouselRide.RIDERS + 1)
			local gap = wrap(math.atan2(nextSpot[1], nextSpot[3]) - math.atan2(p[1], p[3]))
			expect(math.abs(math.abs(gap) - math.pi / 4) < 1e-3).toBe(true)
		end
	end)
	it("keeps each rider on its circle while it turns and carries it with the deck", function()
		for i = 1, CarouselRide.RIDERS do
			local spot = CarouselRide.spot(i)
			for _, t in { 0, 3, PERIOD / 3, T0 } do
				local pose = CarouselRide.pose(i, t)
				expect(radius(pose.x, pose.z)).toBeCloseTo(radius(spot[1], spot[3]), 4)
				-- the rider's bearing moved by the turn's angle (CFrame.Angles(0, a, 0) turns +X towards -Z)
				local moved = wrap(math.atan2(pose.x, pose.z) - math.atan2(spot[1], spot[3]))
				expect(math.abs(wrap(moved - CarouselRide.angle(t))) < 1e-4).toBe(true)
			end
		end
	end)
	it("faces each rider along the turn: its front (-Z) points where it moves next", function()
		for i = 1, CarouselRide.RIDERS do
			local a, b = CarouselRide.pose(i, 10), CarouselRide.pose(i, 10.01)
			local dx, dz = b.x - a.x, b.z - a.z
			local len = radius(dx, dz)
			local fx, fz = -math.sin(a.yaw), -math.cos(a.yaw)
			expect((fx * dx + fz * dz) / len > 0.999).toBe(true)
		end
	end)
	it("bobs each rider within +-riderBob, one cycle every riderBobSeconds", function()
		for i = 1, CarouselRide.RIDERS do
			local low, high = math.huge, -math.huge
			for step = 0, 200 do
				local b = CarouselRide.bob(i, step * SHOP.riderBobSeconds / 200)
				low, high = math.min(low, b), math.max(high, b)
			end
			expect(high).toBeCloseTo(SHOP.riderBob, 2)
			expect(low).toBeCloseTo(-SHOP.riderBob, 2)
			expect(CarouselRide.bob(i, 5)).toBeCloseTo(CarouselRide.bob(i, 5 + SHOP.riderBobSeconds), 6)
			expect(CarouselRide.pose(i, 5).y).toBeCloseTo(CarouselRide.spot(i)[2] + CarouselRide.bob(i, 5), 6)
		end
	end)
	it("bobs the riders out of phase: neighbours apart, opposite twins half a cycle apart", function()
		for i = 1, CarouselRide.RIDERS do
			local nextPhase = CarouselRide.phase(i % CarouselRide.RIDERS + 1)
			expect(math.abs(wrap(nextPhase - CarouselRide.phase(i))) > math.pi / 2).toBe(true)
		end
		for i = 1, 4 do
			expect(math.abs(math.abs(wrap(CarouselRide.phase(i + 4) - CarouselRide.phase(i))) - math.pi) < 1e-6).toBe(
				true
			)
			expect(CarouselRide.bob(i, 1.3)).toBeCloseTo(-CarouselRide.bob(i + 4, 1.3), 6)
		end
	end)
	it("seats the featured seats each twice, the two copies on opposite poles", function()
		local seats = CarouselRide.riderSeats({ "leaf", "ufo", "bubble", "clam_shell" })
		expect(seats).toEqual({ "leaf", "ufo", "bubble", "clam_shell", "leaf", "ufo", "bubble", "clam_shell" })
		expect(CarouselRide.riderSeats({})).toEqual({})
	end)
	it("scales a rider so its widest side is riderWidth", function()
		expect(CarouselRide.riderScale({ 4.8, 1, 2 }) * 4.8).toBeCloseTo(LAYOUT.riderWidth, 6)
		expect(CarouselRide.riderScale({ 1, 3, 1.2 }) * 1.2).toBeCloseTo(LAYOUT.riderWidth, 6)
		expect(CarouselRide.riderScale({ 0, 0, 0 })).toBe(1)
	end)
end)
