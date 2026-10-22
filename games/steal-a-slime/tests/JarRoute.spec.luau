--!nocheck
-- JarRoute: the walk out of a goo jar tower from an upper floor, round the deck and down the spiral stair.
local JarRoute = require("../src/server/JarRoute")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function radius(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

local function angleOf(x: number, z: number): number
	return math.deg(math.atan2(z, x)) % 360
end

describe("JarRoute.down", function()
	local stair = WorldLayout.STAIR
	local walk = WorldLayout.RAMP.walk

	it("has nothing to do on the ground floor or outside the jar glass", function()
		expect(JarRoute.down(10, WorldLayout.floorTop(1), 5)).toBe(nil)
		expect(JarRoute.down(WorldLayout.jarRadius(2) + 1, WorldLayout.floorTop(2), 0)).toBe(nil)
	end)

	for floor = 2, #WorldLayout.JAR_RADII do
		it(
			"from a pad on floor " .. floor .. ": round the deck, down the spiral to the ground, off at its foot",
			function()
				local px, pz = WorldLayout.polar(WorldLayout.PAD_RINGS[floor], 200)
				local route = JarRoute.down(px, WorldLayout.floorTop(floor) + 1.2, pz)
				expect(route ~= nil).toBe(true)
				expect(#route % 2).toBe(0)
				local turned, last = 0, nil
				for i = 1, #route, 2 do
					local r = radius(route[i], route[i + 1])
					expect(r > stair.post + 1).toBe(true) -- never through the centre post
					expect(r < WorldLayout.jarRadius(floor)).toBe(true)
					if math.abs(r - walk) < 1e-6 then
						local a = angleOf(route[i], route[i + 1])
						if last then
							-- down the helix = the angle falls (it climbs as the angle grows), in small steps
							local step = (last - a) % 360
							expect(step > 0 and step <= JarRoute.ARC_STEP + 1e-6).toBe(true)
							turned += step
						end
						last = a
					else
						expect(r >= stair.hole - 1e-6).toBe(true) -- off the spiral, never over the stair hole
					end
				end
				expect(turned).toBeCloseTo((floor - 1) * 360 - JarRoute.ENTER - JarRoute.STEP_OFF, 1e-6)
				local ex, ez = route[#route - 1], route[#route]
				expect(radius(ex, ez)).toBeCloseTo(JarRoute.DECK_RADIUS, 1e-6)
				expect(angleOf(ex, ez)).toBeCloseTo((JarRoute.footAngle() + JarRoute.STEP_OFF) % 360, 1e-6)
			end
		)
	end

	it("steps on and off inside the rail's open ends", function()
		expect(JarRoute.ENTER < WorldLayout.RAMP.railEnd).toBe(true)
		expect(JarRoute.STEP_OFF < WorldLayout.RAMP.railStart).toBe(true)
	end)

	it("the spiral's foot is where every floor's stair starts: one unbroken helix", function()
		for f = 1, #WorldLayout.JAR_RADII - 1 do
			expect((WorldLayout.treadAngle(f, 1) - stair.angle) % 360).toBeCloseTo(JarRoute.footAngle() % 360, 1e-9)
		end
	end)

	it("the deck ring clears the stair hole and every upper floor's pad stands", function()
		expect(JarRoute.DECK_RADIUS > stair.hole).toBe(true)
		for f = 2, #WorldLayout.PAD_RINGS do
			expect(JarRoute.DECK_RADIUS < WorldLayout.PAD_RINGS[f] - WorldLayout.PAD_SIZE / 2 - 1).toBe(true)
		end
	end)
end)
