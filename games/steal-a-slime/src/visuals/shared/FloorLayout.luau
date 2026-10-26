--!strict
--[[
	FloorLayout (owner: Archer; B11 + B3, concept c3 "ranch boardwalk")

	FloorLayout.build(g: Geometry): { Node }   -- Map.Paths, Map.Lawns, Map.Field (WorldLayout.map adds them)
	FloorLayout.groundMaterial(x, z, material): string   -- GroundTerrain's cell material with the grass under the floor swapped
	FloorLayout.terrainRows(): { Row }                    -- the same swap as rows of whole cells (server/FloorTerrain)

	The new main floor is parts, meshes and materials on TOP of the voxel terrain; no terrain-height file is touched.
	  * Map.Field   FieldBand (the old pre-#270 grass (98,160,70), r 300, the border band), FieldHem (tan curb line) and
	                FieldSand (flat warm sand, r 228): the yard the plots stand in. Grass is only the outer border band.
	  * Map.Paths   PlazaDisc (cream), DeckPlaza (ONE baked mesh: 72 radial planks, inlay, rim), Boardwalk (ONE baked mesh:
	                the ring, eight spokes, planks and rails) and eight GateRamp blocks up to the plot floor.
	  * Map.YardPatches   a dozen flat discs on the sand (darker sand, trodden dirt, small grass islands; YardProps.PATCHES).
	  * Map.Lawns   32 grass blocks: an annular-sector lawn in each of the eight wedges between the spokes (grass accents).
	Nothing here collides except the gate ramps: the terrain (y = FLOOR_Y) and the invisible Map.Ground floor are the
	walk surface and the floor parts sit at most TRIM_TOP above it, so there is no trip lip. Decor never queries or touches.

	THE height: FLOOR_Y. Everything is placed as FLOOR_Y + a layer offset (LAYER), so if the terrain surface moves after
	Gojo's B1 fix, change FLOOR_Y and nothing else. The gate ramp tops out at the plot Base floor top (Geometry.plotFloorTop,
	an absolute height).

	Snow v2: every surface says what it is with the SnowKind attribute (SnowCover.KIND_ATTRIBUTE): the grass-class surfaces
	(FieldBand, FieldSand, lawns) go fully white like the terrain grass did and melt last; the path-class ones (deck, boardwalk,
	disc, hem, ramps) take SnowCover's light frost and melt first. The baked meshes are tinted by their slot colour (MeshTint),
	which is their brightest colour, so the frost (a lerp of that colour toward white) brightens every plank.
]]

local YardProps = if script then require(script.Parent.YardProps) else require("./YardProps")

export type Node = {
	name: string,
	class: string,
	shape: string?,
	size: { number }?,
	pos: { number }?,
	rot: { number }?,
	color: { number }?,
	material: string?,
	transparency: number?,
	canCollide: boolean?,
	canQuery: boolean?,
	canTouch: boolean?,
	attributes: { [string]: any }?,
	children: { Node }?,
}

-- WorldLayout's numbers the floor is laid out from (FloorLayout cannot require WorldLayout: it is required by it).
export type Geometry = {
	ringRadius: number, -- the ring path's centre line
	ringWidth: number,
	plazaRadius: number,
	plotRing: number, -- plot centres
	plotSize: number,
	plotFloorTop: number, -- absolute top of every plot's Base floor
	plots: number, -- spokes / wedges
	hall: Hall?, -- the Hall of Fame plaza and its path (WorldLayout.HALL_OF_FAME)
}

-- The Hall of Fame floor, in world studs: the round plaza (rim + floor), the podium stage disc on it and the plank
-- path from the ring path out to it (centre, width, length, bearing of its long axis).
export type Hall = {
	x: number,
	z: number,
	radius: number,
	rim: number, -- width of the darker rim round the floor
	stage: { x: number, z: number, radius: number },
	path: { x: number, z: number, width: number, length: number, bearing: number },
}

local FloorLayout = {}

-- The ONE height: the walk surface the floor is flush with (the terrain surface / the invisible Map.Ground top).
FloorLayout.FLOOR_Y = 0

-- Layer tops above FLOOR_Y. Strictly increasing by >= 0.025 so no two overlapping surfaces share a depth.
FloorLayout.LAYER = table.freeze({
	band = 0.03,
	hem = 0.055,
	sand = 0.08,
	disc = 0.105,
	lawn = 0.135,
	plank = 0.17, -- planks of the baked meshes (kit PLANK_TOP)
	trim = 0.21, -- rails, rim, inlay (kit TRIM_TOP)
})

FloorLayout.FIELD_RADIUS = 228 -- the sand yard (plots reach r 184.4)
FloorLayout.HEM_RADIUS = 230.4
FloorLayout.BAND_RADIUS = 300 -- the grass border band: out to just past the world border wall (r 292)
FloorLayout.TERRAIN_SAND_RADIUS = 298 -- terrain Grass cells whose centre is inside are sand (their tufts would poke through the floor)
FloorLayout.PLAZA_DISC_RADIUS = 65.8

FloorLayout.COLORS = table.freeze({
	sand = { 230, 211, 170 },
	hem = { 205, 177, 130 },
	grass = { 98, 160, 70 }, -- the pre-#270 Ground colour Merijn preferred
	cream = { 244, 233, 207 },
	hallRim = { 214, 186, 138 },
	hallStage = { 240, 206, 120 },
	plank = { 184, 134, 84 },
	deckBase = { 244, 232, 200 }, -- slot colour of the deck mesh (kit INLAY): its brightest colour
	pathBase = { 196, 146, 92 }, -- slot colour of the boardwalk mesh (kit BASE)
} :: { [string]: { number } })

-- The baked meshes (shared/modeling-kit/models/ranch_floor_*.py). Native size = the slot box: hub-centred and 8-fold
-- symmetric, so the slot centre is the hub whatever the import turn.
FloorLayout.DECK_MESH = "ranch_floor_deck"
FloorLayout.PATH_MESH = "ranch_floor_paths"
FloorLayout.DECK_SIZE = table.freeze({ 131.2, 0.21, 131.2 })
FloorLayout.PATH_SIZE = table.freeze({ 192, 0.21, 192 })

-- Boardwalk geometry shared with the kit script: spokes run r 65.6..(ring) and (ring)..SPOKE_PLANK_END; the ramp takes the
-- last RAMP_LENGTH studs up to the plot floor.
FloorLayout.SPOKE_WIDTH = 8
FloorLayout.SPOKE_PLANK_END = 96
FloorLayout.RAMP_START = 96
FloorLayout.RAMP_END = 100 -- the plot's inner edge (PLOT_RING_RADIUS - PLOT_SIZE / 2)
FloorLayout.RAMP_WIDTH = 8.4
FloorLayout.RAMP_THICKNESS = 0.4

-- Lawns: annular sectors between the spokes, kept clear of each spoke's centre line.
FloorLayout.LAWN_R0 = 85.5
FloorLayout.LAWN_R1 = 99
FloorLayout.LAWN_MARGIN_DEG = 5.7 -- 8.5 studs from a spoke's centre line at r 85.5; the chord blocks' corners keep >= 6.5 (spoke half width 4 + rail 0.8)
FloorLayout.LAWN_BLOCKS = 4 -- chord blocks per wedge
FloorLayout.LAWN_STEP = 0.004

-- Yard ground patches (YardProps.PATCHES, from tools/yard): flat discs on the sand, each kind its own height above FieldSand
-- (0.08) so no two share a depth. They are parts, not meshes; no collision, no query.
FloorLayout.PATCH_KINDS =
	table.freeze({
		dark = table.freeze({ color = { 198, 172, 124 }, material = "Sand", layer = 0.09, snow = "grass" }), -- soft darker sand
		dirt = table.freeze({ color = { 152, 114, 76 }, material = "Ground", layer = 0.095, snow = "path" }), -- trodden earth
		grass = table.freeze({ color = { 114, 170, 78 }, material = "Grass", layer = 0.1, snow = "grass" }), -- a small grass island
	} :: { [string]: { color: { number }, material: string, layer: number, snow: string } })

FloorLayout.SNOW_KIND_ATTRIBUTE = "SnowKind"

local function top(layer: number): number
	return FloorLayout.FLOOR_Y + layer
end

local function discNode(
	name: string,
	radius: number,
	layer: number,
	color: { number },
	material: string,
	kind: string
): Node
	local thick = 0.2
	return {
		name = name,
		class = "Part",
		shape = "Cylinder",
		size = { thick, radius * 2, radius * 2 },
		pos = { 0, top(layer) - thick / 2, 0 },
		rot = { 0, 0, 90 },
		color = color,
		material = material,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		attributes = { [FloorLayout.SNOW_KIND_ATTRIBUTE] = kind },
	}
end

-- A baked mesh slot: invisible box the size of the mesh (MeshSwap fits the mesh into it), never solid. MeshTint: the
-- slot's colour multiplies the mesh's vertex colours. While the mesh is not loaded the floor shows the sand yard only.
local function meshSlot(name: string, mesh: string, size: { number }, color: { number }): Node
	return {
		name = name,
		class = "Part",
		shape = "Block",
		size = { size[1], size[2], size[3] },
		pos = { 0, FloorLayout.FLOOR_Y + size[2] / 2, 0 },
		rot = { 0, 0, 0 },
		color = color,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		attributes = { MeshAsset = mesh, MeshTint = true, [FloorLayout.SNOW_KIND_ATTRIBUTE] = "path" },
	}
end

-- The up-ramp from the boardwalk's end to the plot floor: a tilted plank, solid (it is the one walkable floor piece
-- the terrain does not give). Its low end meets the planks flush; its high end meets the plot Base top flush.
function FloorLayout.ramp(bearing: number, plotFloorTop: number): Node
	local s0, s1 = FloorLayout.RAMP_START, FloorLayout.RAMP_END
	local y0, y1 = top(FloorLayout.LAYER.plank), plotFloorTop
	local run, rise = s1 - s0, y1 - y0
	local length = math.sqrt(run * run + rise * rise)
	local tilt = math.atan2(rise, run)
	local t = FloorLayout.RAMP_THICKNESS
	-- centre = top-line midpoint pushed down the plank's normal by half its thickness
	local sc = (s0 + s1) / 2 + math.sin(tilt) * t / 2
	local yc = (y0 + y1) / 2 - math.cos(tilt) * t / 2
	local b = math.rad(bearing)
	return {
		name = "GateRamp",
		class = "Part",
		shape = "Block",
		size = { FloorLayout.RAMP_WIDTH, t, length },
		pos = { math.sin(b) * sc, yc, math.cos(b) * sc },
		rot = { -math.deg(tilt), bearing, 0 },
		color = FloorLayout.COLORS.plank,
		material = "SmoothPlastic",
		canCollide = true,
		canQuery = false,
		canTouch = false,
		attributes = { [FloorLayout.SNOW_KIND_ATTRIBUTE] = "path" },
	}
end

-- One lawn block: a chord block of the sector, tangent to the mid radius, bearings a0..a1.
function FloorLayout.lawnBlock(name: string, a0: number, a1: number, odd: boolean?): Node
	local r0, r1 = FloorLayout.LAWN_R0, FloorLayout.LAWN_R1
	local rm = (r0 + r1) / 2
	local mid = math.rad((a0 + a1) / 2)
	-- as wide as the sector's OUTER arc chord (+0.4 overlap): neighbouring chord blocks then overlap at the inner edge instead of
	-- opening a sliver of sand at the outer one
	local chord = 2 * r1 * math.sin(math.rad(a1 - a0) / 2) + 0.4
	local thick = 0.2
	return {
		name = name,
		class = "Part",
		shape = "Block",
		size = { chord, thick, r1 - r0 },
		-- neighbouring blocks overlap: every other one sits LAWN_STEP higher, so no two share a top plane (z-fight)
		pos = {
			math.sin(mid) * rm,
			top(FloorLayout.LAYER.lawn) + (if odd then FloorLayout.LAWN_STEP else 0) - thick / 2,
			math.cos(mid) * rm,
		},
		rot = { 0, math.deg(mid), 0 },
		color = FloorLayout.COLORS.grass,
		material = "Grass",
		canCollide = false,
		canQuery = false,
		canTouch = false,
		attributes = { [FloorLayout.SNOW_KIND_ATTRIBUTE] = "grass" },
	}
end

function FloorLayout.build(g: Geometry): { Node }
	local c = FloorLayout.COLORS
	local field: { Node } = {
		discNode("FieldBand", FloorLayout.BAND_RADIUS, FloorLayout.LAYER.band, c.grass, "Grass", "grass"),
		discNode("FieldHem", FloorLayout.HEM_RADIUS, FloorLayout.LAYER.hem, c.hem, "SmoothPlastic", "path"),
		discNode("FieldSand", FloorLayout.FIELD_RADIUS, FloorLayout.LAYER.sand, c.sand, "SmoothPlastic", "grass"),
	}
	local paths: { Node } = {
		discNode("PlazaDisc", FloorLayout.PLAZA_DISC_RADIUS, FloorLayout.LAYER.disc, c.cream, "SmoothPlastic", "path"),
		meshSlot("DeckPlaza", FloorLayout.DECK_MESH, FloorLayout.DECK_SIZE :: any, c.deckBase),
		meshSlot("Boardwalk", FloorLayout.PATH_MESH, FloorLayout.PATH_SIZE :: any, c.pathBase),
	}
	local hall = g.hall
	if hall then
		local layer = FloorLayout.LAYER
		local function at(node: Node, x: number, z: number): Node
			local y = (node.pos :: { number })[2]
			node.pos = { x, y, z }
			return node
		end
		table.insert(
			paths,
			at(discNode("HallRim", hall.radius, layer.disc, c.hallRim, "SmoothPlastic", "path"), hall.x, hall.z)
		)
		table.insert(
			paths,
			at(
				discNode("HallFloor", hall.radius - hall.rim, layer.lawn, c.cream, "SmoothPlastic", "path"),
				hall.x,
				hall.z
			)
		)
		local st = hall.stage
		table.insert(
			paths,
			at(discNode("HallStage", st.radius, layer.plank, c.hallStage, "SmoothPlastic", "path"), st.x, st.z)
		)
		local walk = hall.path
		local thick = 0.2
		table.insert(paths, {
			name = "HallPath",
			class = "Part",
			shape = "Block",
			size = { walk.width, thick, walk.length },
			pos = { walk.x, top(layer.plank) - thick / 2, walk.z },
			rot = { 0, walk.bearing, 0 },
			color = c.plank,
			material = "WoodPlanks",
			canCollide = false,
			canQuery = false,
			canTouch = false,
			attributes = { [FloorLayout.SNOW_KIND_ATTRIBUTE] = "path" },
		})
	end
	local lawns: { Node } = {}
	local step = 360 / g.plots
	local margin, blocks = FloorLayout.LAWN_MARGIN_DEG, FloorLayout.LAWN_BLOCKS
	for k = 0, g.plots - 1 do
		local spoke = step * k
		table.insert(paths, FloorLayout.ramp(spoke, g.plotFloorTop))
		paths[#paths].name = `GateRamp{k + 1}`
		local a0, a1 = spoke + margin, spoke + step - margin
		for i = 0, blocks - 1 do
			local lo = a0 + (a1 - a0) * i / blocks
			local hi = a0 + (a1 - a0) * (i + 1) / blocks
			table.insert(lawns, FloorLayout.lawnBlock(`Lawn{k + 1}_{i + 1}`, lo, hi, i % 2 == 1))
		end
	end
	local patches: { Node } = {}
	for _, row in YardProps.PATCHES do
		local kind = FloorLayout.PATCH_KINDS[row[2]]
		local a = math.rad(row[3])
		local node = discNode(row[1], row[5], kind.layer, kind.color, kind.material, kind.snow)
		node.pos = { math.sin(a) * row[4], top(kind.layer) - 0.1, math.cos(a) * row[4] }
		table.insert(patches, node)
	end
	return {
		{ name = "Field", class = "Folder", children = field },
		{ name = "Paths", class = "Folder", children = paths },
		{ name = "Lawns", class = "Folder", children = lawns },
		{ name = "YardPatches", class = "Folder", children = patches },
	}
end

-- Terrain under the floor: the voxel Grass inside TERRAIN_SAND_RADIUS becomes Sand (a Terrain.Decoration tuft grows on
-- Grass voxels and would poke through every floor part). Outside the band the pastel Grass and its tufts stay.
function FloorLayout.groundMaterial(x: number, z: number, material: string): string
	if material == "Grass" and x * x + z * z <= FloorLayout.TERRAIN_SAND_RADIUS ^ 2 then
		return "Sand"
	end
	return material
end

export type Row = { z0: number, x0: number, x1: number } -- z0..z0+cell, x0..x1: whole 4-stud cells, symmetric about x = 0

-- The cells of groundMaterial's swap as one Region per 4-stud row (cell centres at 2 mod 4, like GroundTerrain's grid).
function FloorLayout.terrainRows(): { Row }
	local cell, limit = 4, FloorLayout.TERRAIN_SAND_RADIUS
	local rows: { Row } = {}
	local j = -math.floor(limit / cell) - 1
	while j * cell <= limit do
		local zc = j * cell + cell / 2
		local rem = limit * limit - zc * zc
		if rem >= 0 then
			local xmax = math.sqrt(rem)
			if xmax >= cell / 2 then
				local m = math.floor((xmax - cell / 2) / cell) -- cells 0..m on each side of x = 0
				table.insert(rows, { z0 = j * cell, x0 = -(m + 1) * cell, x1 = (m + 1) * cell })
			end
		end
		j += 1
	end
	return rows
end

return FloorLayout
