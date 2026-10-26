--!strict
--[[
	BaseShapes (pure)

	The buildings a plot can stand in (CONTRACT.md §43): the goo jar tower (today's WorldLayout jar), the Goo Factory
	and the Mushroom Pagoda. BaseShapes.get(id) is the one place that knows each base's geometry; servers and clients
	ask it instead of the jar's numbers. Every base keeps WorldLayout.floorTop, SPAWN_SPOT, the door on the plot's -Z
	side and PADS_PER_FLOOR pads per floor.

	A shape:
	- padOffset(j) -> (x, z), padYaw(j): pad j on its floor (plot-local);
	- inside(f, x, z, slack?): plot-local point inside floor f's walls, `slack` studs past them counting too (the drop
	  exit's owner check, the lock guard, evacuate);
	- guard: the PlotLockGuard table for that inside test with its hysteresis;
	- floor1(i): plot i's floor-1 nodes: the kept parts (pads, MergeVat, LockButton, ButtonLook, Bridge, LockBarrier)
	  where this base wants them, plus this base's own pieces (the jar's glass and door, or a "BaseShape" Model);
	- floor(i, f): an upper floor (Floor_<f> + its pads), like WorldLayout.floor;
	- top(i, f): the roof colliders on the top floor, or nil when the roof is part of the floors ("top" pieces);
	- dropLanding(): where the owner's drop exit lands (plot-local, y on the floorTop scale);
	- route: true when a dropped slime needs the hand-built JarRoute leg (else pathfinding walks it down).
	The other bases' numbers are generated from the kit layouts (BaseShapeData/<Name>, see its header).
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Factory = if script then require(script.Parent.BaseShapeData.Factory) else require("./BaseShapeData/Factory")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

type Vec = { number }
type WorldNode = WorldLayout.WorldNode

export type Guard = {
	radii: { number },
	floorTop: number,
	floorHeight: number,
	wall: number,
	square: boolean?, -- true: radii are half-widths of a square (max(|x|, |z|)), not radii
}

export type Shape = {
	id: string,
	padOffset: (j: number) -> (number, number),
	padYaw: (j: number) -> number,
	inside: (f: number, x: number, z: number, slack: number?) -> boolean,
	guard: Guard,
	floor1: (i: number) -> { WorldNode },
	floor: (i: number, f: number) -> { WorldNode },
	top: ((i: number, f: number) -> WorldNode)?,
	dropLanding: () -> Vec,
	route: boolean,
}

local BaseShapes = {}

-- Floor-1 parts every base keeps (same instance; moved to the base's node of the same name) and the ones that stay
-- where the jar has them. Everything else on floor 1 belongs to one base and is rebuilt on a swap.
BaseShapes.KEPT_MOVED = table.freeze({ "MergeVat", "LockButton", "ButtonLook", "Bridge", "LockBarrier" })
BaseShapes.KEPT_STILL =
	table.freeze({ "Base", "PlotFloor", "HomeZone", "Slimes", "FootLook", "Moat", "JarFloor", "Sign", "LockSign" })

local function isPad(name: string): boolean
	local j = tonumber(string.match(name, "^Pad_(%d+)$"))
	return j ~= nil and j <= Config.PADS_PER_FLOOR
end

-- True for a floor-1 child name that every base keeps.
function BaseShapes.kept(name: string): boolean
	return isPad(name)
		or table.find(BaseShapes.KEPT_MOVED, name) ~= nil
		or table.find(BaseShapes.KEPT_STILL, name) ~= nil
end

-- ---------------------------------------------------------------- the goo jar tower

local jarGuard: Guard = table.freeze({
	radii = WorldLayout.JAR_RADII,
	floorTop = WorldLayout.PLOT_FLOOR_TOP,
	floorHeight = WorldLayout.FLOOR_HEIGHT,
	wall = WorldLayout.JAR_WALL,
})

local jar: Shape = {
	id = "jar",
	padOffset = WorldLayout.padOffset,
	padYaw = WorldLayout.padYaw,
	inside = function(f: number, x: number, z: number, slack: number?): boolean
		local r = WorldLayout.jarRadius(math.clamp(f, 1, #WorldLayout.JAR_RADII)) + (slack or 0)
		return math.sqrt(x * x + z * z) < r
	end,
	guard = jarGuard,
	floor1 = function(i: number): { WorldNode }
		return (WorldLayout.plotNode(i).children or {}) :: { WorldNode }
	end,
	floor = WorldLayout.floor,
	top = WorldLayout.topColliders,
	dropLanding = WorldLayout.dropLanding,
	route = true,
}

-- ---------------------------------------------------------------- bases from generated data

type Data = typeof(Factory)

local function find(nodes: { WorldNode }, name: string): WorldNode?
	for _, node in nodes do
		if node.name == name then
			return node
		end
	end
	return nil
end

-- A copy of `node` (and its children) moved by plot-local (dx, dz): `at` is the plot frame, so the shift turns with it.
local function shifted(node: WorldNode, dx: number, dz: number, yaw: number): WorldNode
	local a = math.rad(yaw)
	-- plot-local +x / +z in world axes for a frame turned `yaw` degrees about Y
	local wx, wz = dx * math.cos(a) + dz * math.sin(a), -dx * math.sin(a) + dz * math.cos(a)
	local copy = table.clone(node)
	if node.pos then
		copy.pos = { node.pos[1] + wx, node.pos[2], node.pos[3] + wz }
	end
	if node.children then
		local kids = {}
		for _, child in node.children do
			table.insert(kids, shifted(child, dx, dz, yaw))
		end
		copy.children = kids
	end
	return copy
end

local function partNode(p: any, at: (Vec) -> Vec, yaw: number): WorldNode
	local node: WorldNode = {
		name = p.name,
		class = "Part",
		shape = p.shape,
		size = p.size,
		pos = at(p.pos),
		rot = { p.rot[1], p.rot[2] + yaw, p.rot[3] },
		color = p.color,
		material = p.material,
	}
	if not p.collide then
		-- line-of-sight shields: invisible, never collide, still block the drop prompt's line of sight
		node.canCollide = false
		node.canTouch = false
		node.transparency = 1
	end
	if p.show then
		node.attributes = {
			JarFloor = p.floor,
			JarShow = p.show,
			JarHidden = p.show == "covered",
			JarCollide = if p.collide then true else nil,
		}
	end
	return node
end

local function fromData(data: any): Shape
	local pads: { [number]: any } = {}
	for _, pad in data.pads do
		pads[pad.j] = pad
	end
	local box = data.inside.kind == "box"
	local half = data.inside.half
	local guard: Guard = table.freeze({
		radii = table.freeze({ half, half, half, half }),
		floorTop = WorldLayout.PLOT_FLOOR_TOP,
		floorHeight = WorldLayout.FLOOR_HEIGHT,
		wall = 1,
		square = box,
	})

	local function partsOf(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
		local out = {}
		for _, p in data.parts do
			if p.floor == f then
				table.insert(out, partNode(p, at, yaw))
			end
		end
		return out
	end

	local shape: Shape
	shape = {
		id = data.id,
		padOffset = function(j: number): (number, number)
			local pad = pads[j]
			return pad.x, pad.z
		end,
		padYaw = function(j: number): number
			return pads[j].yaw
		end,
		inside = function(_f: number, x: number, z: number, slack: number?): boolean
			local limit = half + (slack or 0)
			if box then
				return math.max(math.abs(x), math.abs(z)) < limit
			end
			return math.sqrt(x * x + z * z) < limit
		end,
		guard = guard,
		floor1 = function(i: number): { WorldNode }
			local at, yaw = WorldLayout.plotFrame(i)
			local color = WorldLayout.plotColor(i)
			local jarNodes = jar.floor1(i)
			local out: { WorldNode } = {}
			for j = 1, Config.PADS_PER_FLOOR do
				local x, z = shape.padOffset(j)
				table.insert(out, WorldLayout.padNodeAt(j, x, z, shape.padYaw(j), at, yaw, color))
			end
			-- the vat and the lock button: the jar's parts moved to this base's spots
			local vx, vz = WorldLayout.polar(WorldLayout.VAT_SPOT.radius, WorldLayout.VAT_SPOT.angle)
			local vat = find(jarNodes, "MergeVat") :: WorldNode
			table.insert(out, shifted(vat, data.vat[1] - vx, data.vat[2] - vz, yaw))
			local bx, bz = WorldLayout.LOCK_BUTTON_SPOT[1], WorldLayout.LOCK_BUTTON_SPOT[2]
			for _, name in { "LockButton", "ButtonLook" } do
				local node = find(jarNodes, name) :: WorldNode
				table.insert(out, shifted(node, data.lockButton[1] - bx, data.lockButton[2] - bz, yaw))
			end
			-- the bridge and the lock barrier: this base's boxes
			local bridge = table.clone(find(jarNodes, "Bridge") :: WorldNode)
			local spot = data.spots.Bridge
			bridge.pos = at(spot.pos)
			bridge.size = spot.size
			table.insert(out, bridge)
			local barrier = table.clone(find(jarNodes, "LockBarrier") :: WorldNode)
			local stopper = table.clone(((barrier.children or {}) :: { WorldNode })[1])
			local door = data.spots.LockBarrier
			stopper.pos = at(door.pos)
			stopper.size = door.size
			barrier.children = { stopper }
			table.insert(out, barrier)
			table.insert(out, {
				name = "BaseShape",
				class = "Model",
				attributes = { PlotBase = data.id },
				children = partsOf(1, at, yaw),
			})
			return out
		end,
		floor = function(i: number, f: number): { WorldNode }
			local at, yaw = WorldLayout.plotFrame(i)
			local color = WorldLayout.plotColor(i)
			local nodes: { WorldNode } = {
				{
					name = `Floor_{f}`,
					class = "Model",
					attributes = { FloorIndex = f },
					children = partsOf(f, at, yaw),
				},
			}
			for j = (f - 1) * Config.PADS_PER_FLOOR + 1, f * Config.PADS_PER_FLOOR do
				local x, z = shape.padOffset(j)
				table.insert(nodes, WorldLayout.padNodeAt(j, x, z, shape.padYaw(j), at, yaw, color))
			end
			return nodes
		end,
		top = nil,
		dropLanding = function(): Vec
			return { data.exit.lands[1], WorldLayout.PLOT_FLOOR_TOP + 3, data.exit.lands[2] }
		end,
		route = false,
	}
	return shape
end

local SHAPES: { [string]: Shape } = {
	jar = jar,
	factory = fromData(Factory),
}

-- The shape of base `id`; the jar for nil or an unknown id (a free plot, the flag off).
function BaseShapes.get(id: string?): Shape
	return SHAPES[id or ""] or jar
end

-- The generated data of base `id` (tests), or nil for the jar.
function BaseShapes.data(id: string): any
	return if id == "factory" then Factory else nil
end

return table.freeze(BaseShapes)
