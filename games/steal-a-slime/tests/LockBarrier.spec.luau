--!nocheck
-- The plot lock's stopper (CONTRACT.md §5.3): one cork collider that fills jar 1's doorway from just outside the
-- glass to the PlotLockGuard limit, closes the gap between the wall segments either side of the door, and is too
-- tall to jump over under the lintel. Built from WorldLayout.build() like the real world.
local Constants = require("../src/shared/Constants")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Default Humanoid JumpHeight (JumpPower 50 at gravity 196.2 is 6.4): the highest a character's feet get.
local MAX_JUMP_HEIGHT = 7.2
local EPS = 1e-6

local function find(nodes, name)
	for _, node in nodes or {} do
		if node.name == name then
			return node
		end
	end
	return nil
end

local function toLocal(part)
	local centre, yaw = WorldLayout.plotCentre(1)
	local p = LayoutMath.apply(
		LayoutMath.orientation({ 0, -yaw, 0 }),
		{ part.pos[1] - centre[1], part.pos[2] - centre[2], part.pos[3] - centre[3] }
	)
	return { x = p[1], y = p[2], z = p[3], sx = part.size[1], sy = part.size[2], sz = part.size[3], node = part }
end

describe("LockBarrier stopper", function()
	local plots = find(WorldLayout.build(), Constants.PLOTS_FOLDER)
	local plotNode = plots.children[1]
	local barrier = find(plotNode.children, "LockBarrier")
	local jar = find(plotNode.children, "Jar")
	local door = WorldLayout.doorway()

	it("is one Stopper part, a hidden ghost until the server makes it solid", function()
		expect(#barrier.children).toBe(1)
		local stopper = barrier.children[1]
		expect(stopper.name).toBe("Stopper")
		expect(stopper.transparency).toBe(1)
		expect(stopper.canCollide).toBe(false)
		expect(stopper.canQuery).toBe(false)
	end)

	it("fills the doorway from outside the glass to the PlotLockGuard limit", function()
		local s = toLocal(barrier.children[1])
		expect(WorldLayout.DOOR_INNER_INSET).toBe(PlotLockGuard.MARGIN)
		expect(math.abs(s.x) < EPS).toBe(true)
		expect(math.abs(s.z - s.sz / 2 - door.zOuter) < EPS).toBe(true)
		expect(math.abs(s.z + s.sz / 2 - door.zInner) < EPS).toBe(true)
		expect(door.zOuter < -(WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL)).toBe(true)
		expect(math.abs(door.zInner + (WorldLayout.jarRadius(1) - PlotLockGuard.MARGIN)) < EPS).toBe(true)
	end)

	it("closes the gap between the door jambs either side of the door", function()
		local s = toLocal(barrier.children[1])
		local found = 0
		for _, seg in jar.children do
			if seg.name == "DoorJambL" or seg.name == "DoorJambR" then
				found += 1
				local p = toLocal(seg)
				-- the jambs are turned like the door segment (its tangent is the plot's x axis at the door)
				local tx, tz = 1, 0
				local best
				for _, sign in { -1, 1 } do
					local ex, ez = p.x + sign * tx * seg.size[1] / 2, p.z + sign * tz * seg.size[1] / 2
					if not best or math.abs(ex) < math.abs(best[1]) then
						best = { ex, ez }
					end
				end
				expect(math.abs(best[1]) <= s.sx / 2).toBe(true)
				expect(best[2] >= s.z - s.sz / 2 and best[2] <= s.z + s.sz / 2).toBe(true)
			end
		end
		expect(found).toBe(2)
	end)

	it("stands under the lintel and is too tall to jump over", function()
		local s = toLocal(barrier.children[1])
		expect(math.abs(s.y - s.sy / 2 - WorldLayout.PLOT_FLOOR_TOP) < EPS).toBe(true)
		expect(s.y + s.sy / 2 >= WorldLayout.PLOT_FLOOR_TOP + MAX_JUMP_HEIGHT + 2).toBe(true)
		local lintel = toLocal(find(jar.children, "DoorLintel"))
		expect(math.abs(lintel.y - lintel.sy / 2 - (s.y + s.sy / 2)) < EPS).toBe(true)
	end)
end)
