--!strict
--[[
	BaseShapes (pure)

	The buildings a plot can stand in (CONTRACT.md §44): the goo jar tower (today's WorldLayout jar), the Goo Factory,
	the Mushroom Pagoda and the round Exclusive bases (Carousel Tent, Space Rocket, Tree House, Lighthouse, Snow
	Globe: one inside, models/_round_base_layout.py). BaseShapes.get(id) is the one place that knows each base's geometry; servers and clients
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
local Pagoda = if script then require(script.Parent.BaseShapeData.Pagoda) else require("./BaseShapeData/Pagoda")
local PagodaMeshes = if script
	then require(script.Parent.BaseShapeData.PagodaMeshes)
	else require("./BaseShapeData/PagodaMeshes")
local FactoryMeshes = if script
	then require(script.Parent.BaseShapeData.FactoryMeshes)
	else require("./BaseShapeData/FactoryMeshes")
-- the round Exclusive bases (models/_round_base_layout.py): same inside, their own shell and roof
local Carousel = if script then require(script.Parent.BaseShapeData.Carousel) else require("./BaseShapeData/Carousel")
local Rocket = if script then require(script.Parent.BaseShapeData.Rocket) else require("./BaseShapeData/Rocket")
local Treehouse = if script
	then require(script.Parent.BaseShapeData.Treehouse)
	else require("./BaseShapeData/Treehouse")
local Lighthouse = if script
	then require(script.Parent.BaseShapeData.Lighthouse)
	else require("./BaseShapeData/Lighthouse")
local Snowglobe = if script
	then require(script.Parent.BaseShapeData.Snowglobe)
	else require("./BaseShapeData/Snowglobe")
local JarMeshes = if script then require(script.Parent.JarMeshes) else require("./JarMeshes")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

type Vec = { number }
type WorldNode = WorldLayout.WorldNode

export type Guard = {
	radii: { number },
	floorTop: number,
	floorHeight: number,
	wall: number,
	square: boolean?, -- true: radii are half-widths of a square (max(|x|, |z|)), not radii
	extra: { { x: number, z: number, r: number } }?, -- more round rooms inside on every floor (the pagoda's turret)
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
	table.freeze({ "Base", "PlotFloor", "HomeZone", "Slimes", "Moat", "JarFloor", "Sign", "LockSign" })

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

-- The mesh that is a collider's look (it hides once that mesh lands, MeshSwap's MeshStandIn), by name, "role#floor" or role.
local function lookOfPart(p: any, standIns: { [string]: string }?): string?
	if not standIns then
		return nil
	end
	return standIns[p.name] or standIns[`{p.role}#{p.floor}`] or standIns[p.role]
end

local function partNode(
	p: any,
	at: (Vec) -> Vec,
	yaw: number,
	standIns: { [string]: string }?,
	plain: boolean?
): WorldNode
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
	local attributes: { [string]: any } = {}
	if p.show and plain then
		-- in the roof folder (only ever on the current top floor): a plain collider, its look a mesh slot
		node.transparency = 1
	elseif p.show then
		-- shown only while its floor is (or is not) the top one (BaseFloors.setLids): a collider whose look is a mesh
		-- slot of the same variant shows itself until that mesh lands (MeshStandIn, then StandInHidden)
		attributes.JarFloor = p.floor
		attributes.JarShow = p.show
		attributes.JarHidden = p.show == "covered"
		attributes.JarCollide = if p.collide then true else nil
		attributes.JarShowSelf = if p.collide then true else nil
		if p.show == "covered" or not p.collide then
			node.transparency = 1
		end
	end
	local look = lookOfPart(p, standIns)
	if look then
		attributes.MeshStandIn = look
	end
	if next(attributes) then
		node.attributes = attributes
	end
	return node
end

-- A mesh slot from a generated slot plan (BaseShapeData/<Name>Meshes): an invisible box the mesh is fitted into
-- (MeshSwap), turned half round like the jar's looks (the kit ships these meshes mirrored, see models/_goo_jar ship).
local function slotNode(slot: any, boxes: any, at: (Vec) -> Vec, yaw: number): WorldNode?
	local box = boxes[slot.mesh]
	if not box then
		for name, b in boxes do
			if string.sub(name, 1, #slot.mesh + 1) == slot.mesh .. "@" then
				box = b
				break
			end
		end
	end
	if not box then
		return nil
	end
	local o, c = slot.offset, box.centre
	local k = slot.scale or 1
	local attributes: { [string]: any } = { MeshAsset = slot.mesh }
	if slot.role then
		attributes.ThemeRole = slot.role
	end
	if slot.glass then
		-- see-through like the jar's glass (server/MeshSwap reads these), so players outside see the pads inside
		attributes.MeshMaterial = WorldLayout.JAR_GLASS_MATERIAL
		attributes.MeshTransparency = WorldLayout.JAR_GLASS_MESH_TRANSPARENCY
		attributes.MeshCastShadow = false
	end
	if slot.show then
		attributes.JarFloor = slot.floor
		attributes.JarShow = slot.show
		attributes.JarHidden = slot.show == "covered"
	end
	return {
		name = slot.name,
		class = "Part",
		shape = "Block",
		size = { box.size[1] * k, box.size[2] * k, box.size[3] * k },
		pos = at({ o[1] + c[1] * k, o[2] + c[2] * k, o[3] + c[3] * k }),
		rot = { 0, yaw + 180, 0 },
		color = { 200, 200, 200 },
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		attributes = attributes,
	}
end

-- The jar's mascot slot (goo_jar_mascot, `scale` x its native box) standing at plot-local `bottom`.
local function mascotNode(
	f: number,
	show: string?,
	bottom: Vec,
	scale: number,
	at: (Vec) -> Vec,
	yaw: number
): WorldNode
	local m = (JarMeshes :: any).goo_jar_mascot
	local c, size = m.centre, m.size
	local attributes: { [string]: any } = { MeshAsset = "goo_jar_mascot" }
	if show then
		attributes.JarFloor = f
		attributes.JarShow = show
		attributes.JarHidden = show == "covered"
	end
	return {
		name = "MascotLook",
		class = "Part",
		shape = "Block",
		size = { size[1] * scale, size[2] * scale, size[3] * scale },
		pos = at({ bottom[1] + c[1] * scale, bottom[2] + c[2] * scale, bottom[3] + c[3] * scale }),
		rot = { 0, yaw + 180, 0 },
		color = { 200, 200, 200 },
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		attributes = attributes,
	}
end

-- Options for a base built from generated data:
--   looks     the mesh slot plan (BaseShapeData/<Name>Meshes: boxes, slots, tints);
--   standIns  which mesh is the look of which collider (by part name, "role#floor" or role);
--   mascot    where the mascot sits on the top floor ({ x, up from the floor, z }, scale);
--   topFolder the top floor's own colliders (the dome, the tall turret) go in the plot's TopColliders folder, rebuilt
--             on whichever floor is on top (like the jar's roof), instead of standing on every floor hidden;
--   jarDoor   the round door is the jar's (stopper shut and parked, lock ring, open-door collider), moved this many
--             studs along plot z from the jar's doorway to this base's;
--   jarFoot   the plot floor and moat look is the jar's goo_jar_foot.
type Options = {
	looks: any?,
	standIns: { [string]: string }?,
	mascot: any?,
	topFolder: boolean?,
	jarDoor: number?,
	jarFoot: boolean?,
}

local function fromData(data: any, opts: Options): Shape
	local looks, standIns, mascot = opts.looks, opts.standIns, opts.mascot
	local pads: { [number]: any } = {}
	for _, pad in data.pads do
		pads[pad.j] = pad
	end
	local box = data.inside.kind == "box"
	local half = data.inside.half
	local radii: { number } = if box then { half, half, half, half } else data.inside.radii
	-- round rooms beside the main one that count as inside on every floor (the pagoda's stair turret)
	local extra: { { x: number, z: number, r: number } } = {}
	for _, e in data.inside.extra or {} do
		table.insert(extra, table.freeze({ x = e.x, z = e.z, r = e.r }))
	end
	local guard: Guard = table.freeze({
		radii = table.freeze(table.clone(radii)),
		floorTop = WorldLayout.PLOT_FLOOR_TOP,
		floorHeight = WorldLayout.FLOOR_HEIGHT,
		wall = 1,
		square = box,
		extra = if #extra > 0 then table.freeze(extra) else nil,
	})

	-- floor f's parts: "floor" = what stands on the floor (all of it, or without the top-only ones when they go in
	-- the roof folder), "top" = the top-only ones for the roof folder
	local function partsOf(f: number, at: (Vec) -> Vec, yaw: number, which: string?): { WorldNode }
		local out = {}
		local roof = which == "top"
		for _, p in data.parts do
			if p.floor == f then
				local topOnly = p.show == "top"
				if roof and topOnly then
					table.insert(out, partNode(p, at, yaw, standIns, true))
				elseif not roof and not (opts.topFolder and topOnly) then
					table.insert(out, partNode(p, at, yaw, standIns))
				end
			end
		end
		if roof then
			return out
		end
		if looks then
			for _, slot in looks.slots do
				if slot.floor == f and not slot.plot then
					local node = slotNode(slot, looks.boxes, at, yaw)
					if node then
						table.insert(out, node)
					end
				end
			end
		end
		if mascot then
			local show = if f < #Config.BASE_FLOORS then "top" else nil
			local bottom = { mascot.at[1], WorldLayout.floorTop(f) + mascot.at[2], mascot.at[3] }
			table.insert(out, mascotNode(f, show, bottom, mascot.scale, at, yaw))
		end
		return out
	end

	-- floor-1 slots the game finds by name on the plot itself (FootLook, StopperShut, StopperParked)
	local function plotSlots(at: (Vec) -> Vec, yaw: number): { WorldNode }
		local out = {}
		if looks then
			for _, slot in looks.slots do
				if slot.plot then
					local node = slotNode(slot, looks.boxes, at, yaw)
					if node then
						table.insert(out, node)
					end
				end
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
		inside = function(f: number, x: number, z: number, slack: number?): boolean
			if box then
				return math.max(math.abs(x), math.abs(z)) < half + (slack or 0)
			end
			local r = radii[math.clamp(f, 1, #radii)] + (slack or 0)
			if math.sqrt(x * x + z * z) < r then
				return true
			end
			for _, e in extra do
				local dx, dz = x - e.x, z - e.z
				if math.sqrt(dx * dx + dz * dz) < e.r + (slack or 0) then
					return true
				end
			end
			return false
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
			for _, node in plotSlots(at, yaw) do
				table.insert(out, node)
			end
			if opts.jarDoor then
				-- the jar's round door, lock ring and open-door collider, moved to this base's doorway
				for _, name in { "StopperShut", "StopperParked", "DoorRing", "OpenDoorCollider" } do
					local node = find(jarNodes, name)
					if node then
						table.insert(out, shifted(node, 0, opts.jarDoor, yaw))
					end
				end
			end
			if opts.jarFoot then
				local foot = find(jarNodes, "FootLook")
				if foot then
					table.insert(out, foot)
				end
			end
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
		top = if opts.topFolder
			then function(i: number, f: number): WorldNode
				local at, yaw = WorldLayout.plotFrame(i)
				return {
					name = "TopColliders",
					class = "Folder",
					attributes = { TopFloor = f },
					children = partsOf(f, at, yaw, "top"),
				}
			end
			else nil,
		dropLanding = function(): Vec
			return { data.exit.lands[1], WorldLayout.PLOT_FLOOR_TOP + 3, data.exit.lands[2] }
		end,
		route = false,
	}
	return shape
end

-- The Goo Factory: which mesh is the look of each collider (they hide once it lands), and the mascot on the goo tank.
local FACTORY_STAND_INS: { [string]: string } = {
	["wall#1"] = "factory_storey_1",
	wall = "factory_storey",
	["core wall"] = "factory_core",
	["floor#1"] = "factory_floor_1",
	floor = "factory_slab",
	CoreCapA = "factory_core_cap",
	CoreCapLanding = "factory_core_cap",
	ramp = "factory_stair",
	roof = "factory_roof",
	["goo belt (collides: 1.2 tall)"] = "factory_belt",
	["yard silo"] = "factory_silo",
	DropHatch = "factory_hatch",
}
local FACTORY_MASCOT = { at = { 9, 28, 4 }, scale = 3.4 }

-- The Mushroom Pagoda: its walls, decks and stair are the looks of their colliders; the door is the jar's round door
-- moved from the jar's doorway (glass centre line 31.5 studs out) to the pagoda's (wall centre line 28.5 out).
local PAGODA_STAND_INS: { [string]: string } = {
	["room wall#1"] = "pagoda_room_1",
	["room wall#2"] = "pagoda_room_2",
	["room wall#3"] = "pagoda_room_3",
	["room wall#4"] = "pagoda_room_4",
	["deck#2"] = "pagoda_deck_2",
	["deck#3"] = "pagoda_deck_3",
	["deck#4"] = "pagoda_deck_4",
	ramp = "pagoda_ramp",
	-- the turret storey meshes carry the landing, the post and the wall; the top floor's is the tall one with the cap
	landing = "pagoda_turret_mid",
	["turret wall"] = "pagoda_turret_mid",
	["turret post"] = "pagoda_turret_mid",
	["landing#4"] = "pagoda_turret_top",
	["turret wall#4"] = "pagoda_turret_top",
	["turret post#4"] = "pagoda_turret_top",
	["turret cap"] = "pagoda_turret_cap",
	dome = "pagoda_dome",
	mascot = "goo_jar_mascot",
}
local PAGODA_DOOR_SHIFT = (WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL / 2) + Pagoda.door.z

-- The round Exclusive bases: walls, decks, ramp and roof are the looks of their colliders (BaseShapeData/<Name>Meshes
-- once modelled); the door is the jar's round door moved to the base's doorway, the foot the jar's.
local ROUND: { [string]: any } = {
	carousel = Carousel,
	rocket = Rocket,
	treehouse = Treehouse,
	lighthouse = Lighthouse,
	snowglobe = Snowglobe,
}
local ROUND_LOOKS: { [string]: any } = {}
local ROUND_STAND_INS: { [string]: { [string]: string } } = {}

local function roundShape(data: any): Shape
	return fromData(data, {
		looks = ROUND_LOOKS[data.id],
		standIns = ROUND_STAND_INS[data.id],
		topFolder = true,
		jarDoor = (WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL / 2) + data.door.z,
		jarFoot = true,
	})
end

local SHAPES: { [string]: Shape } = {
	jar = jar,
	factory = fromData(Factory, {
		looks = FactoryMeshes,
		standIns = FACTORY_STAND_INS,
		mascot = FACTORY_MASCOT,
	}),
	pagoda = fromData(Pagoda, {
		looks = PagodaMeshes,
		standIns = PAGODA_STAND_INS,
		topFolder = true,
		jarDoor = PAGODA_DOOR_SHIFT,
		jarFoot = true,
	}),
}
for id, data in ROUND do
	SHAPES[id] = roundShape(data)
end
local TINTS: { [string]: any } = { factory = FactoryMeshes.tints, pagoda = PagodaMeshes.tints }
for id, looks in ROUND_LOOKS do
	TINTS[id] = looks.tints
end

-- The MeshPart.Color (sRGB 0..255) of a tint-only piece of base `base` in plot skin `skin` for theme role `role`;
-- the classic skin's when the skin has none, nil for a base without tints (the jar's themes are their own meshes).
function BaseShapes.tint(base: string?, skin: string?, role: string): { number }?
	local tints = TINTS[base or ""]
	if not tints then
		return nil
	end
	local row = tints[skin or "classic"] or tints.classic
	return row[role] or tints.classic[role]
end

-- The shape of base `id`; the jar for nil or an unknown id (a free plot, the flag off).
function BaseShapes.get(id: string?): Shape
	return SHAPES[id or ""] or jar
end

-- The generated data of base `id` (tests), or nil for the jar.
function BaseShapes.data(id: string): any
	if id == "factory" then
		return Factory
	elseif id == "pagoda" then
		return Pagoda
	end
	return ROUND[id]
end

return table.freeze(BaseShapes)
