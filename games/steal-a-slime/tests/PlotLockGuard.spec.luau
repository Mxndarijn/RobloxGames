--!strict
-- The plot lock blocks non-owners both ways: no way in, no way out while it lasts. Only someone caught in the
-- doorway as the lock starts is set down outside (PlotLockGuard.wedged / doorwayExit).
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DOORWAY = WorldLayout.doorway()
local DOOR: PlotLockGuard.Door = {
	halfWidth = DOORWAY.halfWidth,
	zOuter = DOORWAY.zOuter,
	zInner = DOORWAY.zInner,
	height = WorldLayout.PLOT_FLOOR_TOP + WorldLayout.DOOR.height,
}
local MID = (DOOR.zOuter + DOOR.zInner) / 2

local function wedged(userId: number, x: number, y: number, z: number, locked: boolean?, owner: number?)
	local ownerId = if owner == nil then 1 else owner
	return PlotLockGuard.wedged(userId, ownerId, locked ~= false, x, y, z, DOOR)
end

describe("PlotLockGuard: locked both ways", function()
	it("has no leaver pass any more: nothing lets a non-owner through a locked stopper", function()
		expect((PlotLockGuard :: any).isLeaver).toBeNil()
		expect((PlotLockGuard :: any).LEAVER_GROUP).toBeNil()
	end)
	it("finds a non-owner standing in a locked plot's doorway", function()
		expect(wedged(2, 0, 3, MID)).toBe(true)
		expect(wedged(2, DOOR.halfWidth - 0.1, 3, DOOR.zOuter + 0.1)).toBe(true)
	end)
	it("leaves the owner, unlocked and unowned plots, and anyone not in the doorway alone", function()
		expect(wedged(1, 0, 3, MID)).toBe(false)
		expect(wedged(2, 0, 3, MID, false)).toBe(false)
		expect(PlotLockGuard.wedged(2, nil, true, 0, 3, MID, DOOR)).toBe(false)
		expect(wedged(2, 0, 3, DOOR.zOuter - 1)).toBe(false) -- on the bridge
		expect(wedged(2, 0, 3, 0)).toBe(false) -- inside the jar: stays in
		expect(wedged(2, DOOR.halfWidth + 1, 3, MID)).toBe(false) -- in the glass beside the door
		expect(wedged(2, 0, DOOR.height + 5, MID)).toBe(false) -- above the door
	end)
	it("sets a wedged character down outside the stopper, on the bridge", function()
		local z = PlotLockGuard.doorwayExit(DOOR)
		expect(z < DOOR.zOuter).toBe(true)
		expect(wedged(2, 0, 3, z)).toBe(false)
		expect(z > -WorldLayout.PLOT_SIZE / 2).toBe(true)
		expect(z < -WorldLayout.MOAT.inner).toBe(true) -- over the moat, where the bridge runs
	end)
	it("gives the same answer for all 8 plot yaws (plot-local maths)", function()
		for i = 1, Config.PLOT_COUNT do
			local _, yaw = WorldLayout.plotCentre(i)
			local rot = LayoutMath.orientation({ 0, yaw, 0 })
			local back = LayoutMath.orientation({ 0, -yaw, 0 })
			local x, y, z = table.unpack(LayoutMath.apply(back, LayoutMath.apply(rot, { 0, 3, MID })))
			expect(wedged(2, x, y, z)).toBe(true)
		end
	end)
	it("names one lock and one owner group per plot", function()
		expect(PlotLockGuard.lockGroup(3)).toBe("PlotLock_3")
		expect(PlotLockGuard.ownerGroup(3)).toBe("PlotOwner_3")
	end)
end)
