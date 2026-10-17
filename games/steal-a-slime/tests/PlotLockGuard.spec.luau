--!strict
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local HALF = 40

describe("PlotLockGuard", function()
	it("ejects a non-owner standing inside a locked plot", function()
		expect(PlotLockGuard.shouldEject(2, 1, true, 0, 3, 0, HALF)).toBe(true)
		expect(PlotLockGuard.shouldEject(2, 1, true, 30, 3, -30, HALF)).toBe(true)
	end)
	it("lets the owner stay", function()
		expect(PlotLockGuard.shouldEject(1, 1, true, 0, 3, 0, HALF)).toBe(false)
	end)
	it("does nothing while the plot is unlocked or has no owner", function()
		expect(PlotLockGuard.shouldEject(2, 1, false, 0, 3, 0, HALF)).toBe(false)
		expect(PlotLockGuard.shouldEject(2, nil, true, 0, 3, 0, HALF)).toBe(false)
	end)
	it("ignores characters outside the fence, in the entrance gap and far above or below", function()
		expect(PlotLockGuard.shouldEject(2, 1, true, 0, 3, -(HALF + 3), HALF)).toBe(false)
		expect(PlotLockGuard.shouldEject(2, 1, true, HALF + 5, 3, 0, HALF)).toBe(false)
		expect(PlotLockGuard.shouldEject(2, 1, true, 0, PlotLockGuard.MAX_Y + 5, 0, HALF)).toBe(false)
		expect(PlotLockGuard.shouldEject(2, 1, true, 0, PlotLockGuard.MIN_Y - 5, 0, HALF)).toBe(false)
	end)
	it("catches a character just inside the fence and not one on the margin line outside", function()
		expect(PlotLockGuard.shouldEject(2, 1, true, 0, 3, -(HALF - 3), HALF)).toBe(true)
		expect(PlotLockGuard.shouldEject(2, 1, true, 0, 3, -(HALF - 1), HALF)).toBe(false)
	end)
	it("puts the ejected character outside the front slab, on the ground, facing out", function()
		local slab = WorldLayout.frontBarrier()
		local x, y, z, dx, dy, dz = PlotLockGuard.ejectPose(HALF, slab.zOuter, 1, 1)
		expect(x).toBe(0)
		expect(z < slab.zOuter - 2).toBe(true)
		expect(PlotLockGuard.trapped(x, y, z, HALF, slab.zOuter)).toBe(false)
		expect(y).toBe(PlotLockGuard.GROUND_Y + PlotLockGuard.STAND_HEIGHT)
		expect(dx == 0 and dy == 0 and dz == -1).toBe(true)
		expect(select(2, PlotLockGuard.ejectPose(HALF, slab.zOuter, 1, 1, 7))).toBe(7 + PlotLockGuard.STAND_HEIGHT)
	end)
	it("treats the front slab as trapped, which the plain footprint check misses", function()
		local slab = WorldLayout.frontBarrier()
		local z = (slab.zOuter + slab.zInner) / 2
		expect(PlotLockGuard.inside(0, 3, z, HALF)).toBe(false)
		expect(PlotLockGuard.trapped(0, 3, z, HALF, slab.zOuter)).toBe(true)
		expect(PlotLockGuard.shouldEject(2, 1, true, 0, 3, z, HALF, slab.zOuter)).toBe(true)
		expect(PlotLockGuard.shouldEject(1, 1, true, 0, 3, z, HALF, slab.zOuter)).toBe(false)
		expect(PlotLockGuard.trapped(0, 3, slab.zOuter - 0.5, HALF, slab.zOuter)).toBe(false)
	end)
	it("spreads several intruders sideways so nobody stacks, all outside", function()
		local slab = WorldLayout.frontBarrier()
		for _, count in { 2, 3, 8, 11 } do
			local seen = {}
			for slot = 1, count do
				local x, y, z = PlotLockGuard.ejectPose(HALF, slab.zOuter, slot, count)
				expect(PlotLockGuard.trapped(x, y, z, HALF, slab.zOuter)).toBe(false)
				for _, other in seen do
					local d = math.sqrt((x - other[1]) ^ 2 + (z - other[2]) ^ 2)
					expect(d >= PlotLockGuard.EJECT_SPACING - 1e-6).toBe(true)
				end
				table.insert(seen, { x, z })
			end
		end
		local first = PlotLockGuard.ejectPose(HALF, slab.zOuter, 1, 2)
		local second = PlotLockGuard.ejectPose(HALF, slab.zOuter, 2, 2)
		expect(first + second).toBe(0) -- centred on the gate
	end)
	it("lands outside and faces away from the plot for every plot yaw", function()
		local slab = WorldLayout.frontBarrier()
		for i = 1, Config.PLOT_COUNT do
			local centre, yaw = WorldLayout.plotCentre(i)
			local rot = LayoutMath.orientation({ 0, yaw, 0 })
			for slot = 1, 3 do
				local x, y, z, dx, dy, dz = PlotLockGuard.ejectPose(HALF, slab.zOuter, slot, 3)
				local pos = LayoutMath.apply(rot, { x, y, z })
				local look = LayoutMath.apply(rot, { dx, dy, dz })
				-- the world point is away from the plot centre along the entrance, and the look points the same way
				local out = LayoutMath.apply(rot, { 0, 0, -1 })
				expect(look[1] * out[1] + look[3] * out[3] > 0.999).toBe(true)
				local rel = { pos[1], pos[3] }
				expect(rel[1] * out[1] + rel[2] * out[3] > HALF).toBe(true)
				-- back in plot space the point is not trapped
				local back = LayoutMath.apply(LayoutMath.orientation({ 0, -yaw, 0 }), { pos[1], pos[2], pos[3] })
				expect(PlotLockGuard.trapped(back[1], back[2], back[3], HALF, slab.zOuter)).toBe(false)
				expect(centre ~= nil).toBe(true)
			end
		end
	end)
	it("names one lock and one owner group per plot", function()
		expect(PlotLockGuard.lockGroup(3)).toBe("PlotLock_3")
		expect(PlotLockGuard.ownerGroup(3)).toBe("PlotOwner_3")
	end)
end)
