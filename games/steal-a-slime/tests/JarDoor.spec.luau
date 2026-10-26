--!nocheck
-- Jar 1's round door (CONTRACT.md §5.3): shut in the doorway while locked, half see-through to the plot's owner only;
-- swung out on its hinges while open, where its OpenDoorCollider is solid without blocking the doorway or the bridge.
local Constants = require("../src/shared/Constants")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local OWNER, VISITOR = 7, 8
local NOW = 1000

local function find(nodes, name)
	for _, node in nodes or {} do
		if node.name == name then
			return node
		end
	end
	return nil
end

-- The collider's footprint corners (plot-local x, z): its disc's ends along the swung door, each side of its thickness.
local function footprint(c)
	local a = math.rad(c.yaw)
	local nx, nz = math.cos(a), -math.sin(a) -- the cylinder's axis (the part's X) = the swung door's normal
	local ux, uz = -nz, nx -- along the door
	local out = {}
	for _, du in { -c.diameter / 2, c.diameter / 2 } do
		for _, dn in { -c.thickness / 2, c.thickness / 2 } do
			table.insert(out, { c.centre[1] + ux * du + nx * dn, c.centre[3] + uz * du + nz * dn })
		end
	end
	return out
end

describe("open door collider", function()
	local plots = find(WorldLayout.build(), Constants.PLOTS_FOLDER)
	local plotNode = plots.children[1]
	local swing = WorldLayout.doorSwing()
	local c = swing.collider

	it("ships solid (a free plot's door stands open), invisible and never queried", function()
		local node = find(plotNode.children, "OpenDoorCollider")
		expect(node ~= nil).toBe(true)
		expect(node.shape).toBe("Cylinder")
		expect(node.canCollide).toBe(nil)
		expect(node.transparency).toBe(1)
		expect(node.canQuery).toBe(false)
		expect(node.canTouch).toBe(false)
	end)

	it("stands in the swung door: on its hinge circle, about the door's size and turned with it", function()
		local hx = WorldLayout.DOOR_SWING.hinge[1]
		local hz = swing.shut[3] + WorldLayout.DOOR_SWING.hinge[2]
		local d = math.sqrt((c.centre[1] - hx) ^ 2 + (c.centre[3] - hz) ^ 2)
		expect(math.abs(d - (WorldLayout.DOOR_DISC.hingeClear + c.diameter / 2)) < 1e-6).toBe(true)
		expect(c.diameter > WorldLayout.DOOR_DISC.radius * 1.6).toBe(true)
		expect(c.diameter <= WorldLayout.DOOR_DISC.radius * 2).toBe(true)
		-- the door turned DOOR_SWING.angle about the pin: the normal from the shut door's z axis
		local a = math.rad(c.yaw)
		local t = math.rad(WorldLayout.DOOR_SWING.angle)
		expect(math.abs(math.cos(a) - math.sin(t)) < 1e-6).toBe(true)
		expect(math.abs(-math.sin(a) - math.cos(t)) < 1e-6).toBe(true)
		-- the mesh's open anchor turns round the same pin (it stays on the pin's circle through the shut anchor)
		local r0 = math.sqrt((swing.shut[1] - hx) ^ 2 + (swing.shut[3] - hz) ^ 2)
		local r1 = math.sqrt((swing.open[1] - hx) ^ 2 + (swing.open[3] - hz) ^ 2)
		expect(math.abs(r0 - r1) < 1e-6).toBe(true)
	end)

	it("keeps clear of the doorway and the bridge, and stays on the plot", function()
		local door = WorldLayout.doorway()
		local half = WorldLayout.BRIDGE_WIDTH / 2
		for _, p in footprint(c) do
			local x, z = p[1], p[2]
			expect(math.abs(x) > half).toBe(true)
			expect(not (math.abs(x) <= door.halfWidth and z >= door.zOuter and z <= door.zInner)).toBe(true)
			expect(math.abs(x) < WorldLayout.PLOT_SIZE / 2 and math.abs(z) < WorldLayout.PLOT_SIZE / 2).toBe(true)
		end
		expect(c.centre[2] - c.diameter / 2 >= WorldLayout.floorTop(1)).toBe(true)
	end)
end)

describe("locked door look", function()
	local world = StaticWorld.build()
	local plots
	for _, root in world do
		if root.Name == Constants.PLOTS_FOLDER then
			plots = root
		end
	end
	local PlotDecor = StaticWorld.visual("PlotDecor")
	local plot = plots:FindFirstChild("Plot_1")
	-- the stopper meshes server/MeshSwap puts under the look slots
	for _, slot in { "StopperShut", "StopperParked" } do
		local mesh = plot:FindFirstChild("Base"):Clone()
		mesh.Name = "Mesh"
		mesh.Parent = plot:FindFirstChild(slot)
	end
	local shut = plot:FindFirstChild("StopperShut"):FindFirstChild("Mesh")
	local parked = plot:FindFirstChild("StopperParked"):FindFirstChild("Mesh")

	it("shows the shut door half see-through to the owner and solid to everyone else", function()
		plot:SetAttribute("OwnerUserId", OWNER)
		plot:SetAttribute("LockUntil", NOW + 60)
		PlotDecor.apply(plot, NOW, OWNER)
		expect(shut.Transparency).toBe(PlotDecor.OWNER_DOOR_TRANSPARENCY)
		expect(PlotDecor.OWNER_DOOR_TRANSPARENCY > 0 and PlotDecor.OWNER_DOOR_TRANSPARENCY < 1).toBe(true)
		expect(parked.Transparency).toBe(1)
		PlotDecor.apply(plot, NOW, VISITOR)
		expect(shut.Transparency).toBe(0)
		PlotDecor.apply(plot, NOW, nil)
		expect(shut.Transparency).toBe(0)
	end)

	it("shows the shut door half see-through to the base's guests (friends let in) too", function()
		plot:SetAttribute("OwnerUserId", OWNER)
		plot:SetAttribute("LockUntil", NOW + 60)
		plot:SetAttribute(Constants.PLOT_GUESTS_ATTRIBUTE, `,{VISITOR},`)
		PlotDecor.apply(plot, NOW, VISITOR)
		expect(shut.Transparency).toBe(PlotDecor.OWNER_DOOR_TRANSPARENCY)
		PlotDecor.apply(plot, NOW, VISITOR + 1)
		expect(shut.Transparency).toBe(0)
		plot:SetAttribute(Constants.PLOT_GUESTS_ATTRIBUTE, nil)
		PlotDecor.apply(plot, NOW, VISITOR)
		expect(shut.Transparency).toBe(0)
	end)

	it("shows the open door solid to the owner too, and the primitive stopper before the meshes land", function()
		plot:SetAttribute("LockUntil", 0)
		PlotDecor.apply(plot, NOW, OWNER)
		expect(shut.Transparency).toBe(1)
		expect(parked.Transparency).toBe(0)
		shut.Parent = nil
		plot:SetAttribute("LockUntil", NOW + 60)
		local stopper = plot:FindFirstChild("LockBarrier"):FindFirstChild("Stopper")
		PlotDecor.apply(plot, NOW, OWNER)
		expect(stopper.Transparency).toBe(PlotDecor.OWNER_DOOR_TRANSPARENCY)
		PlotDecor.apply(plot, NOW, VISITOR)
		expect(stopper.Transparency).toBe(0)
	end)

	it("never shows a free plot's door shut", function()
		plot:SetAttribute("OwnerUserId", 0)
		PlotDecor.apply(plot, NOW, 0)
		expect(plot:FindFirstChild("LockBarrier"):FindFirstChild("Stopper").Transparency).toBe(1)
	end)
end)
