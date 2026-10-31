--!strict
-- The featured seats in the Exclusive Shop's claw shop (Visuals.ShopDisplay, contract/exclusive-shop.md §7): the seats
-- on the spots, the spots on the kit's pedestals inside the claw box, the turn rate and phases, the bob range and the
-- seat size.
local Config = require("../src/shared/Config")
local ExclusiveRotation = require("../src/shared/ExclusiveRotation")
local MeshAssets = require("../src/shared/MeshAssets")
local ShopDisplay = require("../src/visuals/shared/ShopDisplay")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SHOP = Config.EXCLUSIVE_SHOP
local LAYOUT = WorldLayout.EXCLUSIVE_CLAW
local TAU = 2 * math.pi
local PERIOD = 60 / SHOP.displayRpm -- seconds a turn takes
local T0 = 1_790_000_000 -- a server time in 2026

local function wrap(a: number): number
	return (a + math.pi) % TAU - math.pi
end

describe("display seats", function()
	it("shows the first featured seats of the week, one a spot, in order", function()
		expect(ShopDisplay.COUNT).toBe(3)
		expect(SHOP.featuredCount >= ShopDisplay.COUNT).toBe(true)
		local featured = ExclusiveRotation.featured(ExclusiveRotation.week(T0))
		local seats = ShopDisplay.seats(featured)
		expect(#seats).toBe(ShopDisplay.COUNT)
		for i, seat in seats do
			expect(seat).toBe(featured[i])
		end
	end)
	it("shows fewer seats when fewer are featured, and none for none", function()
		expect(#ShopDisplay.seats({ "leaf" })).toBe(1)
		expect(#ShopDisplay.seats({})).toBe(0)
	end)
end)

describe("display spots", function()
	it("are the kit's pedestal tops inside the claw box, behind the counter", function()
		local origin = WorldLayout.clawPoint(LAYOUT.glassOrigin) -- the glass box's bottom centre
		local glass = WorldLayout.meshSize(LAYOUT.glass, LAYOUT.scale)
		local counter = WorldLayout.clawPoint(LAYOUT.counter)
		local cloud = (MeshAssets.get("pet_cloud") :: any).size
		local cloudH = cloud[2] * ShopDisplay.scale(cloud) -- the plain cloud seat, shown at displayWidth
		local half = LAYOUT.displayWidth * LAYOUT.scale / 2
		for i = 1, ShopDisplay.COUNT do
			local p = ShopDisplay.spot(i)
			local kit = LAYOUT.displays[i]
			expect(p[1]).toBeCloseTo(-kit[1] * LAYOUT.scale, 6)
			expect(p[2]).toBeCloseTo((kit[3] - LAYOUT.groundZ) * LAYOUT.scale, 6)
			expect(p[3]).toBeCloseTo(kit[2] * LAYOUT.scale, 6)
			expect(math.abs(p[1] - origin[1]) + half < glass[1] / 2).toBe(true)
			expect(math.abs(p[3] - origin[3]) + half < glass[3] / 2 + 0.3).toBe(true)
			expect(p[2] > origin[2]).toBe(true)
			-- room for a seat and its bob under the box's ceiling
			expect(p[2] + SHOP.displayBob + cloudH < origin[2] + glass[2]).toBe(true)
			expect(p[3] > counter[3]).toBe(true)
		end
	end)
end)

describe("display motion", function()
	it("turns each seat once every 60 / displayRpm seconds on the server clock", function()
		expect(ShopDisplay.angle(1, 0)).toBe(0)
		expect(ShopDisplay.angle(1, PERIOD / 4)).toBeCloseTo(math.pi / 2, 6)
		expect(math.abs(wrap(ShopDisplay.angle(2, T0 + PERIOD) - ShopDisplay.angle(2, T0))) < 1e-5).toBe(true)
		for _, t in { 0, 1.5, 17, T0, T0 + 0.37 } do
			for i = 1, ShopDisplay.COUNT do
				local a = ShopDisplay.angle(i, t)
				expect(a >= 0 and a < TAU).toBe(true)
			end
		end
	end)
	it("keeps the spots a third of a cycle apart", function()
		for i = 2, ShopDisplay.COUNT do
			local step = wrap(ShopDisplay.angle(i, T0) - ShopDisplay.angle(i - 1, T0))
			expect(step).toBeCloseTo(wrap(TAU / ShopDisplay.COUNT), 5)
		end
	end)
	it("floats each seat 0..displayBob over its pedestal, one cycle every displayBobSeconds", function()
		local low, high = math.huge, -math.huge
		for k = 0, 200 do
			local t = T0 + k * SHOP.displayBobSeconds / 200
			local lift = ShopDisplay.lift(1, t)
			low, high = math.min(low, lift), math.max(high, lift)
		end
		expect(low).toBeCloseTo(0, 3)
		expect(high).toBeCloseTo(SHOP.displayBob, 3)
		expect(ShopDisplay.lift(2, T0 + SHOP.displayBobSeconds)).toBeCloseTo(ShopDisplay.lift(2, T0), 5)
	end)
	it("poses a seat at its spot plus the lift, turned by the angle", function()
		for i = 1, ShopDisplay.COUNT do
			local t = T0 + i * 0.7
			local pose, spot = ShopDisplay.pose(i, t), ShopDisplay.spot(i)
			expect(pose.x).toBe(spot[1])
			expect(pose.z).toBe(spot[3])
			expect(pose.y).toBeCloseTo(spot[2] + ShopDisplay.lift(i, t), 6)
			expect(pose.yaw).toBe(ShopDisplay.angle(i, t))
		end
	end)
end)

describe("display size", function()
	it("scales a seat's widest side to displayWidth", function()
		local width = LAYOUT.displayWidth * LAYOUT.scale
		expect(3.3 * ShopDisplay.scale({ 3.3, 1.2, 2.4 })).toBeCloseTo(width, 6)
		expect(4 * ShopDisplay.scale({ 2, 1, 4 })).toBeCloseTo(width, 6)
		expect(ShopDisplay.scale({ 0, 1, 0 })).toBe(1)
	end)
end)
