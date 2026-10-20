--!strict
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local HALF = 40
local SLAB = WorldLayout.frontBarrier().zOuter

local function leaver(userId: number, x: number, y: number, z: number, was: boolean?, locked: boolean?, owner: number?)
	local ownerId = if owner == nil then 1 else owner
	return PlotLockGuard.isLeaver(userId, ownerId, locked ~= false, x, y, z, HALF, SLAB, was)
end

describe("PlotLockGuard: one-way barrier", function()
	it("makes a non-owner standing inside a locked plot a leaver (passes the barrier)", function()
		expect(leaver(2, 0, 3, 0)).toBe(true)
		expect(leaver(2, 30, 3, -30)).toBe(true)
	end)
	it("keeps the owner out of the leaver state", function()
		expect(leaver(1, 0, 3, 0)).toBe(false)
		expect(leaver(1, 0, 3, 0, true)).toBe(false)
	end)
	it("does nothing while the plot is unlocked or has no owner", function()
		expect(leaver(2, 0, 3, 0, nil, false)).toBe(false)
		expect(PlotLockGuard.isLeaver(2, nil, true, 0, 3, 0, HALF, SLAB, true)).toBe(false)
	end)
	it("keeps a non-owner standing outside colliding, so entering stays blocked", function()
		expect(leaver(2, 0, 3, SLAB - 2)).toBe(false) -- at the front slab's outer face
		expect(leaver(2, 0, 3, -(HALF + 3))).toBe(false)
		expect(leaver(2, HALF + 5, 3, 0)).toBe(false)
		expect(leaver(2, 0, PlotLockGuard.MAX_Y + 5, 0)).toBe(false)
		expect(leaver(2, 0, PlotLockGuard.MIN_Y - 5, 0)).toBe(false)
	end)
	it("treats the front slab as inside, which the plain footprint check misses", function()
		local z = (SLAB + WorldLayout.frontBarrier().zInner) / 2
		expect(PlotLockGuard.inside(0, 3, z, HALF)).toBe(false)
		expect(PlotLockGuard.trapped(0, 3, z, HALF, SLAB)).toBe(true)
		expect(leaver(2, 0, 3, z)).toBe(true)
		expect(leaver(1, 0, 3, z)).toBe(false)
	end)
	it("flips back only once the root is EXIT_MARGIN clear of the front line (hysteresis)", function()
		local m = PlotLockGuard.EXIT_MARGIN
		expect(leaver(2, 0, 3, SLAB - m / 2, true)).toBe(true) -- just out: still a leaver
		expect(leaver(2, 0, 3, SLAB - m / 2, false)).toBe(false) -- never was one: collides
		expect(leaver(2, 0, 3, SLAB - m - 0.1, true)).toBe(false) -- clear: collides again
		-- walking out through the gate: leaver all the way, then flips and cannot walk back in
		local was = false
		local flippedAt
		for step = 0, 200 do
			local z = -(HALF - 5) - step * 0.5
			was = leaver(2, 0, 3, z, was)
			if not was then
				flippedAt = z
				break
			end
		end
		expect(flippedAt ~= nil and flippedAt < SLAB).toBe(true)
		expect(leaver(2, 0, 3, flippedAt + 0.5, false)).toBe(false) -- stepping back in is no leaver
	end)
	it("applies the same hysteresis on the sides and back of the plot", function()
		expect(leaver(2, HALF - 1, 3, 0, true)).toBe(true)
		expect(leaver(2, HALF - 0.5, 3, 0, true)).toBe(true)
		expect(leaver(2, HALF + PlotLockGuard.EXIT_MARGIN + 0.5, 3, 0, true)).toBe(false)
		expect(leaver(2, HALF + PlotLockGuard.EXIT_MARGIN + 0.5, 3, 0, false)).toBe(false)
	end)
	it("gives the same answer for all 8 plot yaws (plot-local maths)", function()
		for i = 1, Config.PLOT_COUNT do
			local _, yaw = WorldLayout.plotCentre(i)
			local rot = LayoutMath.orientation({ 0, yaw, 0 })
			local back = LayoutMath.orientation({ 0, -yaw, 0 })
			local function local_(px: number, py: number, pz: number)
				local w = LayoutMath.apply(rot, { px, py, pz })
				return LayoutMath.apply(back, w)
			end
			local inx, iny, inz = table.unpack(local_(0, 3, 0))
			local outx, outy, outz = table.unpack(local_(0, 3, SLAB - 4))
			expect(leaver(2, inx, iny, inz)).toBe(true)
			expect(leaver(2, outx, outy, outz)).toBe(false)
			expect(leaver(2, outx, outy, outz, true)).toBe(false)
			expect(leaver(1, inx, iny, inz)).toBe(false)
		end
	end)
	it("names one lock and one owner group per plot and one shared leaver group", function()
		expect(PlotLockGuard.lockGroup(3)).toBe("PlotLock_3")
		expect(PlotLockGuard.ownerGroup(3)).toBe("PlotOwner_3")
		expect(PlotLockGuard.LEAVER_GROUP).toBe("PlotLeaver")
	end)
end)
