--!strict
-- The plot lock blocks non-owners both ways: no way in, no way out while it lasts. It never moves anyone.
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DOORWAY = WorldLayout.doorway()
local BRIDGE = DOORWAY.zOuter - 3 -- on the bridge, just outside the stopper

describe("PlotLockGuard: locked both ways", function()
	it("has no leaver pass and moves nobody: no set-down out of the doorway", function()
		expect((PlotLockGuard :: any).isLeaver).toBeNil()
		expect((PlotLockGuard :: any).LEAVER_GROUP).toBeNil()
		expect((PlotLockGuard :: any).wedged).toBeNil()
		expect((PlotLockGuard :: any).doorwayExit).toBeNil()
	end)
	it("names one lock and one owner group per plot", function()
		expect(PlotLockGuard.lockGroup(3)).toBe("PlotLock_3")
		expect(PlotLockGuard.ownerGroup(3)).toBe("PlotOwner_3")
	end)
end)

describe("PlotLockGuard.insideJar", function()
	local JAR: PlotLockGuard.Jar = {
		radii = WorldLayout.JAR_RADII,
		floorTop = WorldLayout.PLOT_FLOOR_TOP,
		floorHeight = WorldLayout.FLOOR_HEIGHT,
		wall = WorldLayout.JAR_WALL,
	}
	local floor1 = WorldLayout.PLOT_FLOOR_TOP + 3
	it("counts the middle of jar 1 as inside and the bridge as outside", function()
		expect(PlotLockGuard.insideJar(0, floor1, 0, JAR, 1, false)).toBe(true)
		expect(PlotLockGuard.insideJar(0, floor1, BRIDGE, JAR, 1, false)).toBe(false)
	end)
	it("keeps a character inside while it leans on the glass or the stopper", function()
		local r = WorldLayout.jarRadius(1)
		expect(PlotLockGuard.insideJar(0, floor1, -(r - 0.5), JAR, 1, false)).toBe(false)
		expect(PlotLockGuard.insideJar(0, floor1, -(r - 0.5), JAR, 1, true)).toBe(true)
		expect(PlotLockGuard.insideJar(0, floor1, BRIDGE, JAR, 1, true)).toBe(false)
	end)
	it("only counts floors that are built", function()
		local floor2 = WorldLayout.floorTop(2) + 3
		expect(PlotLockGuard.insideJar(0, floor2, 0, JAR, 1, false)).toBe(false)
		expect(PlotLockGuard.insideJar(0, floor2, 0, JAR, 2, false)).toBe(true)
	end)
	it("calls a character that entered after the lock began an intruder", function()
		expect(PlotLockGuard.intruder(105, 100)).toBe(true)
		expect(PlotLockGuard.intruder(95, 100)).toBe(false)
		-- pushed in by the stopper shutting on them in the doorway
		expect(PlotLockGuard.intruder(100 + PlotLockGuard.SHUT_GRACE, 100)).toBe(false)
	end)
end)
