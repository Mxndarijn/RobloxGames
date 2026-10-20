--!strict
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local R = WorldLayout.jarRadius(1)
local DOORWAY = WorldLayout.doorway()
local DOOR: PlotLockGuard.Door = { halfWidth = DOORWAY.halfWidth, zOuter = DOORWAY.zOuter }
local SLAB = DOOR.zOuter
local HALF = WorldLayout.PLOT_SIZE / 2

local function leaver(userId: number, x: number, y: number, z: number, was: boolean?, locked: boolean?, owner: number?)
	local ownerId = if owner == nil then 1 else owner
	return PlotLockGuard.isLeaver(userId, ownerId, locked ~= false, x, y, z, R, DOOR, was)
end

describe("PlotLockGuard: one-way stopper on a round jar", function()
	it("makes a non-owner standing inside a locked plot's jar a leaver (passes the stopper)", function()
		expect(leaver(2, 0, 3, 0)).toBe(true)
		local x, z = WorldLayout.padOffset(3)
		expect(leaver(2, x, 3, z)).toBe(true)
	end)
	it("keeps the owner out of the leaver state", function()
		expect(leaver(1, 0, 3, 0)).toBe(false)
		expect(leaver(1, 0, 3, 0, true)).toBe(false)
	end)
	it("does nothing while the plot is unlocked or has no owner", function()
		expect(leaver(2, 0, 3, 0, nil, false)).toBe(false)
		expect(PlotLockGuard.isLeaver(2, nil, true, 0, 3, 0, R, DOOR, true)).toBe(false)
	end)
	it("keeps a non-owner on the bridge, the moat or a plot corner colliding, so entering stays blocked", function()
		local moat = (WorldLayout.MOAT.inner + WorldLayout.MOAT.outer) / 2
		expect(leaver(2, 0, 3, SLAB - 0.5)).toBe(false) -- on the bridge, at the stopper's outer face
		expect(leaver(2, 0, 3, -moat)).toBe(false) -- bridge over the moat
		expect(leaver(2, 0, 3, -(HALF - 1))).toBe(false) -- bridge foot
		expect(leaver(2, moat, 3, 0)).toBe(false) -- moat at the side
		expect(leaver(2, 0, 3, moat)).toBe(false) -- moat at the back
		expect(leaver(2, HALF - 2, 3, -(HALF - 2))).toBe(false) -- front corner
		expect(leaver(2, -(HALF - 2), 3, HALF - 2)).toBe(false) -- back corner
		expect(leaver(2, 0, PlotLockGuard.MAX_Y + 5, 0)).toBe(false)
		expect(leaver(2, 0, PlotLockGuard.MIN_Y - 5, 0)).toBe(false)
	end)
	it("treats the doorway passage as inside, which the plain jar check misses", function()
		local z = (DOORWAY.zOuter + DOORWAY.zInner) / 2
		expect(PlotLockGuard.inside(0, 3, z, R)).toBe(false)
		expect(PlotLockGuard.trapped(0, 3, z, R, DOOR)).toBe(true)
		expect(leaver(2, 0, 3, z)).toBe(true)
		expect(leaver(1, 0, 3, z)).toBe(false)
		-- beside the doorway, outside the glass, is outside
		expect(leaver(2, DOOR.halfWidth + 3, 3, z)).toBe(false)
	end)
	it("flips back only once the root is EXIT_MARGIN clear of the doorway (hysteresis)", function()
		local m = PlotLockGuard.EXIT_MARGIN
		expect(leaver(2, 0, 3, SLAB - m / 2, true)).toBe(true) -- just out: still a leaver
		expect(leaver(2, 0, 3, SLAB - m / 2, false)).toBe(false) -- never was one: collides
		expect(leaver(2, 0, 3, SLAB - m - 0.1, true)).toBe(false) -- clear: collides again
		-- walking out through the door over the bridge: leaver all the way, then flips and cannot walk back in
		local was = false
		local flippedAt
		for step = 0, 200 do
			local z = -(R - 5) - step * 0.5
			was = leaver(2, 0, 3, z, was)
			if not was then
				flippedAt = z
				break
			end
		end
		expect(flippedAt ~= nil and flippedAt < SLAB).toBe(true)
		expect(leaver(2, 0, 3, flippedAt + 0.5, false)).toBe(false) -- stepping back in is no leaver
	end)
	it("applies the same hysteresis at the glass all the way round", function()
		for _, deg in { 0, 45, 90, 180, 225 } do
			local function at(r: number)
				local x, z = WorldLayout.polar(r, deg)
				return x, z
			end
			local x1, z1 = at(R - PlotLockGuard.MARGIN - 0.5)
			expect(leaver(2, x1, 3, z1)).toBe(true)
			local x2, z2 = at(R - PlotLockGuard.MARGIN + 0.5)
			expect(leaver(2, x2, 3, z2, true)).toBe(true)
			expect(leaver(2, x2, 3, z2, false)).toBe(false)
			local x3, z3 = at(R - PlotLockGuard.MARGIN + PlotLockGuard.EXIT_MARGIN + 0.5)
			expect(leaver(2, x3, 3, z3, true)).toBe(false)
		end
	end)
	it("uses the jar at the character's height: an upper jar is smaller than the ground jar", function()
		local top = #Config.BASE_FLOORS
		local y = WorldLayout.floorTop(top) + 3
		expect(WorldLayout.floorAt(y)).toBe(top)
		expect(WorldLayout.floorAt(WorldLayout.floorTop(1) + 3)).toBe(1)
		local rTop = WorldLayout.jarRadius(top)
		local r = (rTop + R) / 2 -- outside the top jar's glass, inside the ground jar's footprint
		expect(PlotLockGuard.isLeaver(2, 1, true, r, y, 0, rTop, DOOR)).toBe(false)
		expect(PlotLockGuard.isLeaver(2, 1, true, rTop - 4, y, 0, rTop, DOOR)).toBe(true)
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
	it("never moves a character: no eject API, no position write in the lock guard", function()
		expect(rawget(PlotLockGuard, "shouldEject")).toBe(nil)
		expect(rawget(PlotLockGuard, "ejectPoint")).toBe(nil)
		expect(rawget(PlotLockGuard, "ejectPose")).toBe(nil)
		local src = fs.readFile("src/server/WorldView.luau")
		local from = string.find(src, "function WorldView.enforceLocks", 1, true)
		local to = string.find(src, "function WorldView.updatePlots", 1, true)
		expect(from ~= nil and to ~= nil and to > from).toBe(true)
		local body = string.sub(src, from :: number, to :: number)
		for _, forbidden in { "PivotTo", ".CFrame =", "AssemblyLinearVelocity", "Position =", "ApplyImpulse" } do
			expect(string.find(body, forbidden, 1, true)).toBe(nil)
		end
		expect(string.find(src, "ejectIntruders", 1, true)).toBe(nil)
		expect(string.find(src, "ejectToGate", 1, true)).toBe(nil)
	end)
end)
