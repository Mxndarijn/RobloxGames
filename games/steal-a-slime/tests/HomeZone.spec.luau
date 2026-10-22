--!strict
local HomeZone = require("../src/shared/HomeZone")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SIZE = { WorldLayout.PLOT_SIZE, 14, WorldLayout.PLOT_SIZE }
local R = WorldLayout.PLOT_FLOOR_RADIUS

describe("HomeZone", function()
	it("is the round plot floor when the zone has a Radius", function()
		expect(HomeZone.contains(0, 0, 0, SIZE, R, nil)).toBe(true)
		expect(HomeZone.contains(R - 0.5, 0, 0, SIZE, R, nil)).toBe(true)
		-- the square's corner, outside the round jar: no one's home
		expect(HomeZone.contains(R - 2, 0, R - 2, SIZE, R, nil)).toBe(false)
		expect(HomeZone.contains(R - 2, 0, R - 2, SIZE, nil, nil)).toBe(true) -- a zone without Radius is its box
	end)
	it("reaches from under the part to over it, plus ReachUp", function()
		expect(HomeZone.contains(0, -7 - HomeZone.BELOW - 0.1, 0, SIZE, R, nil)).toBe(false)
		expect(HomeZone.contains(0, 7 + HomeZone.ABOVE, 0, SIZE, R, nil)).toBe(true)
		expect(HomeZone.contains(0, 7 + HomeZone.ABOVE + 10, 0, SIZE, R, nil)).toBe(false)
		expect(HomeZone.contains(0, 7 + HomeZone.ABOVE + 10, 0, SIZE, R, 16)).toBe(true)
	end)
	it("keeps the Hall of Fame path out of plots 4 and 5", function()
		for _, y in { -110, -100, -90 } do
			local p = WorldLayout.hallPoint(0, y)
			for _, i in { 4, 5 } do
				local c, yaw = WorldLayout.plotCentre(i)
				local a = math.rad(yaw)
				local dx, dz = p[1] - c[1], p[3] - c[3]
				-- the zone's frame is the plot's (turned by yaw); a circle doesn't care, the box would
				local lx, lz = dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
				expect(HomeZone.contains(lx, 0, lz, SIZE, R, nil)).toBe(false)
			end
		end
	end)
end)
