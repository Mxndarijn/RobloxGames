--!strict
--[[
	WorldLayout (owner: Archer)

	WorldLayout.build(): { WorldNode }

	Pure description of the world in CONTRACT.md §5.3, as a tree of nodes
	(Folder / Model / Part / PointLight) in world space. WorldBuilder turns it into
	Instances under workspace; the render proof draws it under Lune.

	  Map      Ground (640x640 invisible void-safety floor; the visible ground is
	           GroundTerrain voxels), Volcano = the Slime Ranch fountain
	           (kit slime_fountain; contract name kept, Crater = the goo pool
	           on top = the drop origin), Chute (primitive slide, hidden once
	           the fountain mesh loads), Plaza
	           (signpost, podiums, landing-ring tiles, goo drain), Decor
	           (rocks, mushrooms, the RanchProps kit props), Border
	           (WorldBorder: the invisible wall ring + seeded hedges, fences,
	           pines, hills, rocks along the edge). Kit meshes go on MeshAsset
	           slots via server/MeshSwap.
	  Plots    Plot_1..PLOT_COUNT in a ring around the fountain, each facing
	           it (door at local -Z): Base, jar 1 of the goo jar tower (Jar
	           glass wall + Lid, Moat, JarFloor, Bridge) with Pad_1..PADS_PER_FLOOR
	           on its pad ring, HomeZone, MergeVat, LockButton, Sign (the
	           plot's name board), Slimes folder, and the PlotDecor cosmetics
	           (LockBarrier stopper, ParkedStopper, LockSign, RebirthDecor).
	           Upper jars come from WorldLayout.floor (server/BaseFloors)
	Every Part is anchored (WorldBuilder forces it). PROP_SPOTS suggests
	where Props go.

	Wild drops land MIN_RADIUS..MAX_RADIUS (34..62) studs from the centre and
	ride the fountain spiral (end r 35.5) before sliding out to that spot.
	Plots start past 90.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Constants = if script then require(script.Parent.Parent.Shared.Constants) else require("../../shared/Constants")
local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")
local FloorLayout = if script then require(script.Parent.FloorLayout) else require("./FloorLayout")
local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local Meadow = if script then require(script.Parent.Meadow) else require("./Meadow")
local RanchProps = if script then require(script.Parent.RanchProps) else require("./RanchProps")
local VatDecor = if script then require(script.Parent.VatDecor) else require("./VatDecor")
local JarMeshes = if script then require(script.Parent.JarMeshes) else require("./JarMeshes")
local WorldBorder = if script then require(script.Parent.WorldBorder) else require("./WorldBorder")

type Vec = LayoutMath.Vec

export type WorldNode = {
	name: string,
	class: string, -- "Folder" | "Model" | "Part" | "PointLight"
	shape: string?, -- Enum.PartType name (Part only)
	size: Vec?,
	pos: Vec?,
	rot: Vec?, -- orientation degrees
	color: Vec?,
	material: string?, -- Enum.Material name
	transparency: number?,
	canCollide: boolean?, -- default true
	canQuery: boolean?, -- default true
	canTouch: boolean?, -- default true
	attributes: { [string]: any }?, -- set only when missing (never overwrites server values)
	primaryPart: string?, -- Model only: name of a child Part
	children: { WorldNode }?,
	preset: string?, -- PointLight: Effects.LIGHTS name
}

local WorldLayout = {}

WorldLayout.MAP_NAME = "Map"
WorldLayout.SLIMES_FOLDER = "Slimes"
-- Slime Ranch layout (shared/modeling-kit/models/FOUNTAIN_SIZES.md): 80-stud
-- plots with one gated entrance. FOUNTAIN_SIZES proposes plot centres at
-- r ~130, but 80-stud squares 45 degrees apart only clear each other's inner
-- corners from r ~137 (40 / tan 22.5 + 40), so the ring sits at 140.
WorldLayout.PLOT_RING_RADIUS = 140
WorldLayout.PLOT_SIZE = 80
-- Absolute top of every plot's Base floor (plot(): a 1-stud slab centred at y 0.5). The floor's gate ramps climb to it.
WorldLayout.PLOT_FLOOR_TOP = 1
-- Flat sand past the wild landing ring (r62) and the hub spawn (r64).
WorldLayout.PLAZA_RADIUS = 66
WorldLayout.FOUNTAIN_HEIGHT = 43.3 -- polished mesh height; Effects caps rise at h/2
WorldLayout.FOUNTAIN_DIAMETER = 28
-- The fountain mesh's silo profile (kit models/slime_fountain.py PROF, studs,
-- silo axis at the origin, kit z = Roblox y). The fountain colliders are built
-- from these numbers, not from the primitive stand-ins.
WorldLayout.FOUNTAIN_PROFILE = table.freeze({
	plinthRadius = 13.1, -- "plinth_top" (13.0 at the foot)
	plinthTop = 1.5,
	trimRadius = 12.3, -- "trim_lo", the bevel up to the staves
	trimTop = 2.4,
	wallRadius = 11.2, -- staves at foot and top (wall_r, 11.7 mid-bulge)
	wallTop = 30.0, -- WALL_TOP, the eave underside
	eaveTop = 31.3, -- Z0, eave edge top (the red dome starts here)
	eaveRadius = 13.4, -- the eave edge's outer radius at its top
	domeCentre = 8.9, -- dome shoulder: r = domeCentre + domeSpan * cos(phi), z = eaveTop + domeRise * sin(phi)
	domeSpan = 4.5,
	domeRise = 4.6,
})
local DOME_STEPS = 18 -- 5 degrees each: no tier rises more than 0.4 studs

-- The solid top of the fountain mesh, above the silo wall: stacked upright
-- cylinders {radius, bottom, top} from the eave over the dome to the rim top
-- (eaveTop + domeRise: the basin's flat floor, a stud under the slide's head). Each tier
-- is as wide as the profile at its foot, so the collision never sits inside
-- the visible surface (feet never sink) and pokes out at most one tier rise.
-- Every tier is a full column from the eave underside (wallTop) up to its own top: the
-- union is the same solid as a stack of thin slabs, but a body landing on the dome meets
-- a part >= 1.3 studs thick instead of a 0.1..0.4 slab it can sink through in one
-- physics step (fountain_walk: a character ball dropped at 44 studs/s sank 0.11 at r 11.5).
-- The goo crown above stays open: the slide starts in it.
function WorldLayout.fountainTopTiers(): { { number } }
	local fp = WorldLayout.FOUNTAIN_PROFILE
	local tiers = { { fp.eaveRadius, fp.wallTop, fp.eaveTop } }
	for i = 0, DOME_STEPS - 1 do
		local a, b = math.rad(i * 90 / DOME_STEPS), math.rad((i + 1) * 90 / DOME_STEPS)
		table.insert(
			tiers,
			{ fp.domeCentre + fp.domeSpan * math.cos(a), fp.wallTop, fp.eaveTop + fp.domeRise * math.sin(b) }
		)
	end
	return tiers
end
-- The silo axis is the map centre: every fountain piece (mesh slot, emerge
-- slot, colliders, crater, slide, landing ring, goo drain) is laid out from
-- FOUNTAIN_CENTRE. The slime_fountain mesh's silo axis is SILO_OFFSET (X, Z)
-- from its bbox centre (kit SILO_AXIS (-6.52, 7.75), Roblox Z = -kit y; an
-- OBJ circle fit of the staves gives the same), so its slot sits at
-- FOUNTAIN_CENTRE - SILO_OFFSET. EMERGE_OFFSET = emerge bbox centre minus
-- fountain bbox centre (FOUNTAIN_SIZES.md). Unrotated: rotate both with the
-- fountain if it ever turns.
WorldLayout.FOUNTAIN_CENTRE = table.freeze({ 0, 0, 0 }) :: Vec
WorldLayout.FOUNTAIN_MESH_SIZE = table.freeze({ 54.45, 43.316, 63.851 }) :: Vec
WorldLayout.FOUNTAIN_SILO_OFFSET = table.freeze({ -6.52, 0, -7.75 }) :: Vec
WorldLayout.FOUNTAIN_EMERGE_OFFSET = table.freeze({ -11.2, 18.94, -8.25 }) :: Vec
-- Legacy name: the fountain still answers to Map.Volcano(.Crater) (CONTRACT §5.3).
WorldLayout.VOLCANO_HEIGHT = WorldLayout.FOUNTAIN_HEIGHT
-- The live ride is WorldLayout.SLIDE_PATH (mesh spiral, end r 35.5 on +Z).
-- The old straight chute bearing was yaw 22.5; that slide is gone.
WorldLayout.RING_PATH_RADIUS = 78
WorldLayout.RING_PATH_WIDTH = 8
-- Props keep this corridor clear in front of every plot's bridge (PropClearance).
WorldLayout.ENTRANCE_CLEAR = 20
-- Mesh slots in the whole world, as the pc-watcher counts MeshParts (MeshAsset + pending BorderMesh
-- slots + the WorldProps skins) (tests/WorldBudget.spec).
-- MeshParts are a SOFT budget now: MESH_SLOT_BUDGET mirrors tools/pipeline/pc-watcher/budgets.json
-- mesh_parts.warn (500; tools/pr-gate/budget_check.py fails if they drift) and only warns. The real mesh limits
-- are world triangles (<= 500000, pr-gate budget.sh from the kit FBX) and unique meshes (<= 120, runtime budget).
-- #80's hard per-category split (fence 128 / gate posts 8 / border 96 / decor 152 / runtime 16 = 400) was folded
-- into those limits; BORDER_SLOT_COUNT stays as a layout-correctness pin (a change to the ring trips it).
--   border  Map.Border's slots: 86 = 66 decor pieces + 20 giant trees.
--   runtime MeshParts the pc-watcher counts in the play world that WorldLayout.build() does not produce: 16, the
--           constant gap between the build count and the watcher's (340 vs 356 at 09ea65e, 398 vs 414 at
--           b84f795). RUNTIME_SLOT_ALLOWANCE is the Studio calibration offset (the podium R15 rig); the pr-gate
--           runtime counter adds it to parts, MeshParts and unique meshes (tools/pr-gate/README.md).
WorldLayout.MESH_SLOT_BUDGET = 500
WorldLayout.BORDER_SLOT_COUNT = 86
WorldLayout.RUNTIME_SLOT_ALLOWANCE = 16
-- Parts outside Map.Border (THEME.md asked <= 1200; raised to 1400 for the
-- primitive meadow clusters in the grass band behind the plots). Asserted
-- over the world WorldLayout builds outside Map.Border; the border ring
-- (main #54) is held to its own budget, since its pieces still carry an
-- invisible slot plus primitive stand-ins each.
WorldLayout.PART_BUDGET = 1400
WorldLayout.BORDER_PART_BUDGET = 700

-- Every slime spot uses the one round cork stand; only the habitat on top
-- changes per slime type (Habitats / HabitatFx).
WorldLayout.PAD_MESH = "goo_cork_stand"
-- Where a slime sits on the stand at native size (kit model header): the Pad
-- top goes here, so slimes rest on the mesh instead of sinking into it.
WorldLayout.PAD_SEAT_Y = 2.4
-- The stand's dish (models/_goo_jar.py cork_stand, native size, from the
-- stand bottom): habitat overlays rest on its rim at height y (the seat), on
-- the rim band between the slime (radius matHalf) and the dish edge (radius
-- half).
WorldLayout.PAD_DECK = table.freeze({ y = 2.4, half = 3.75, matHalf = 2.6 })
-- The goo jar tower (CONTRACT.md §5.3): floor f is the inside of glass jar f, FLOOR_HEIGHT above floor f - 1.
-- Plot-local angles: a point at angle a (degrees) and radius r is (r cos a, r sin a) in (x, z), so -90 is the
-- entrance side (-Z), where jar 1's door is. Jars shrink upwards; each jar's pads sit on PAD_RINGS[f] facing the
-- centre, with at least a 3-stud walkway between pads and 4.5 studs to the glass. The spiral stair from floor f to
-- f + 1 winds round the centre post (STAIR: post radius, tread outer radius, one 1-stud step per STAIR.angle
-- degrees), up through the hole in the deck above; each stair starts a quarter turn past where the one below
-- arrived. Upper floors (Config.BASE_FLOORS beyond 1) are built at runtime by server/BaseFloors.
WorldLayout.FLOOR_HEIGHT = 16
WorldLayout.JAR_RADII = table.freeze({ 31, 27, 24, 21.5 })
WorldLayout.PAD_RINGS = table.freeze({ 19, 17, 15.5, 14.1 })
-- The gameplay Pad box (collision, prompt, PivotTo top) under each round cork stand; the stand's dish keeps the
-- crate deck's size (PAD_DECK.half), so the habitat overlays still fit on it.
WorldLayout.PAD_SIZE = 6.4
WorldLayout.JAR_WALL = 1 -- glass thickness
WorldLayout.JAR_WALL_SEGMENTS = 12
WorldLayout.DECK_SEGMENTS = 16
WorldLayout.DOOR = table.freeze({ angle = -90, width = 8, height = 11 }) -- no wider than one glass segment
WorldLayout.STAIR = table.freeze({ post = 1.5, outer = 5.5, hole = 6, angle = 22.5, firstAngle = 90 })
WorldLayout.MOAT = table.freeze({ inner = 34.5, outer = 38.5 })
-- The drop tube runs down the back; every upper jar's hatch sits at this angle, the splash pool outside the moat.
-- DROP_TUBE: the tube's radius out from the jar centre (over the moat, outside jar 1's glass) and its width.
WorldLayout.DROP_ANGLE = 70
WorldLayout.DROP_TUBE = table.freeze({ radius = 37, width = 3 })
-- Jar 1's ground pieces (plot-local; angles as above). The bridge crosses the moat to the door. Floor 1's pads stand
-- FLOOR1_PAD_STEP apart either side of the door, leaving a bay at the back (round the stair's foot) where the
-- MergeVat and the LockButton stand side by side: locking and merging happen inside, on the ground floor, so nobody
-- camps an owner's button from outside. The LockSign (status) stands outside by the bridge with the plot's name
-- board (Sign, PlotSigns writes on its Front face) on the same post, the rebirth banners either side of the door.
-- Players spawn on the walkway between the stair and the pads, in front of the door. Boss trophies stand on the plot
-- corners, clear of the moat.
WorldLayout.BRIDGE_WIDTH = 10
WorldLayout.FLOOR1_PAD_STEP = 36
WorldLayout.VAT_SPOT = table.freeze({ angle = 106, radius = 22.5 })
WorldLayout.LOCK_BUTTON_SPOT = table.freeze({ 6.2, 21.6 }) -- in the back bay beside the vat (angle 74, radius 22.5)
WorldLayout.LOCK_SIGN_SPOT = table.freeze({ 8.5, -36.5 }) -- on the moat by the bridge, across from the parked stopper
WorldLayout.NAME_BOARD = table.freeze({ width = 9, height = 2.4, y = 10.7 }) -- above the LockSign, on its post
WorldLayout.BANNER_ANGLES = table.freeze({ -108, -72 })
-- Jar 1's door is a round plank door on two hinges on its left (-X). Locked, it sits shut in the doorway (StopperShut);
-- open, it swings DOOR_SWING.angle degrees out of the jar round its hinge pin (StopperParked), folded back towards
-- the glass so its far edge stays on the plot (a 90 degree swing would reach past the plot's edge). hinge = the pin's
-- plot x and its z offset from the shut door's inner face (the door is 1 stud thick, the pin in its middle).
WorldLayout.DOOR_SWING = table.freeze({ hinge = { -4.75, -0.5 }, angle = 130 })
WorldLayout.SPAWN_SPOT = table.freeze({ 0, -12.5 })
WorldLayout.TROPHY_SPOTS = table.freeze({ { -31, 31 }, { 31, 31 }, { -31, -31 } })
-- The plot SlimeDex board skins the two-sided phoenix_top_earners_board at
-- DEX_SCALE (14.8 x 14 x 2.9, about the gate's height). DEX_FACE = its front
-- cream panel at native size, measured on out/phoenix_top_earners_board.fbx
-- in the mesh's own frame (front +Z): centre x off the box centre, centre y
-- up from the bottom, front face z ahead of the box centre. The DexBoard
-- parts are laid out on that panel at DEX_CONTENT_SCALE of their old size.
WorldLayout.DEX_MESH = "phoenix_top_earners_board"
WorldLayout.DEX_SCALE = 0.7
WorldLayout.DEX_CONTENT_SCALE = 0.6
WorldLayout.DEX_FACE = table.freeze({ x = -0.35, y = 11.53, front = 0.4, width = 12.9, height = 11.5 })
-- The plaza ShopStand skins ranch_shop_stand at BUY_STAND_SCALE (9.6 x
-- 11.3 x 6, about the old primitive stand). BUY_STAND_FACE = its butter SHOP
-- sign face and BUY_STAND_COUNTER = its counter, at native size from the kit
-- source (models/ranch_shop_stand.py) in the mesh's own frame (front +Z):
-- centre x, centre y up from the bottom, z from the box centre (+ = front);
-- `front` is the sign's front face.
WorldLayout.BUY_STAND_MESH = "ranch_shop_stand"
WorldLayout.BUY_STAND_SCALE = 0.8
WorldLayout.BUY_STAND_FACE = table.freeze({ x = 0, y = 12.2, front = -2.42, width = 7.6, height = 2 })
WorldLayout.BUY_STAND_COUNTER = table.freeze({ x = 0, z = 0.53, width = 11, depth = 4.2, top = 4.1 })

-- Suggested placements for Props (pivot CFrame = CFrame.new(pos) *
-- CFrame.Angles(0, math.rad(yaw), 0)), just outside the ring path between
-- two spokes. The shop and the Top Earners board face the fountain (Props
-- front = local -Z; every shop faces the map centre, TODO v28 #10, v29 B3);
-- the tutorial NPC stands behind the hub SpawnLocation (scripts/StaticWorld,
-- same bearing) and faces it.
local function propSpot(angle: number, faceVolcano: boolean?, radius: number?): { pos: Vec, yaw: number }
	-- Ring path outer edge is r 82 (78 + 8/2). 90 keeps a shop-sized prop off it.
	local r, a = radius or 90, math.rad(angle)
	return { pos = { math.sin(a) * r, 0, math.cos(a) * r }, yaw = if faceVolcano then angle else angle + 180 }
end
-- ItemShopStand is the old ShopStand spot (WorldProps still places the single "ShopStand" there while
-- FEATURES.WorldShops is off); UpgradeShopStand sits between the plot 1 and 2 spokes, bearing 34.5 / r 96 (22.5 / r 92 is the Campfire / CampBench camp, 20 studs away; 35 at r 90-98 would clip the plot 2 entrance; CONTRACT.md §27.2).
WorldLayout.PROP_SPOTS = table.freeze({
	ItemShopStand = propSpot(67.5, true),
	UpgradeShopStand = propSpot(34.5, true, 96),
	LeaderboardBoard = propSpot(157.5, true),
	TutorialNpc = propSpot(247.5, true),
}) :: { [string]: { pos: Vec, yaw: number } }

-- Spiral the polished slime_fountain slide follows (models/slime_fountain.py):
-- 1.75 turns, end r 35.5 at the front. Kit (x, y, z-up) -> Roblox (x, z, -y),
-- about the silo axis (FOUNTAIN_CENTRE, the world origin). Wilds ride this; the primitive chute copies it
-- and hides once the fountain mesh loads.
local SLIDE_TURNS, SLIDE_THETA_END = 1.75, -math.pi / 2
local SLIDE_R0, SLIDE_RHELIX, SLIDE_REND = 4.8, 17.2, 35.5
local SLIDE_Z0, SLIDE_Z1, SLIDE_FLARE = 36.4, 0.7, 0.62

local function slideKit(t: number): (number, number)
	local th = SLIDE_THETA_END + SLIDE_TURNS * math.pi * 2 * (1 - t)
	local r
	if t < 0.07 then
		local u = t / 0.07
		r = SLIDE_R0 + (SLIDE_RHELIX - SLIDE_R0) * (1 - (1 - u) ^ 2)
	elseif t < SLIDE_FLARE then
		r = SLIDE_RHELIX
	else
		local u = (t - SLIDE_FLARE) / (1 - SLIDE_FLARE)
		r = SLIDE_RHELIX + (SLIDE_REND - SLIDE_RHELIX) * (u * u * (3 - 2 * u))
	end
	return math.cos(th) * r, math.sin(th) * r
end

-- The ride line sampled `samples` times (the live ride and the colliders use 33; the kit mesh itself is built from 66).
local function buildSlide(samples: number): { Vec }
	local ts, xy = {}, {}
	for k = 0, samples - 1 do
		local t = k / (samples - 1)
		local x, y = slideKit(t)
		table.insert(ts, t)
		table.insert(xy, { x, y })
	end
	local length = { 0 }
	for k = 1, samples - 1 do
		local a, b = xy[k], xy[k + 1]
		local dist = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local weight = if ts[k] < SLIDE_FLARE then 1.7 else 1
		length[k + 1] = length[k] + dist * weight
	end
	local total = length[samples]
	local path = {}
	for k = 1, samples do
		local u = length[k] / total
		local drop = math.max(0, 1 - u / 0.9) ^ 1.2
		local z = SLIDE_Z1 + (SLIDE_Z0 - SLIDE_Z1) * drop
		local p, c = xy[k], WorldLayout.FOUNTAIN_CENTRE
		table.insert(path, { c[1] + p[1], c[2] + z, c[3] - p[2] })
	end
	return path
end

WorldLayout.SLIDE_END_RADIUS = SLIDE_REND
WorldLayout.SLIDE_PATH = table.freeze(buildSlide(33))
WorldLayout.KIT_SLIDE_SAMPLES = 66 -- models/slime_fountain.py N: the posts and brackets hang off these samples
function WorldLayout.slidePath(samples: number): { Vec }
	return buildSlide(samples)
end

function WorldLayout.slidePosition(t: number): Vec
	local path = WorldLayout.SLIDE_PATH
	local f = math.clamp(t, 0, 1) * (#path - 1)
	local i = math.floor(f)
	local k = f - i
	local a, b = path[i + 1], path[math.min(i + 2, #path)]
	return {
		a[1] + (b[1] - a[1]) * k,
		a[2] + (b[2] - a[2]) * k,
		a[3] + (b[3] - a[3]) * k,
	}
end

-- Slime Ranch palette: plots get their identity from saturated mid-value
-- accents, neutrals are warm (wood, sand, ranch stone) and Neon is kept for
-- gameplay signals (goo, buttons).
local PLOT_COLORS = {
	{ 232, 112, 140 },
	{ 120, 196, 112 },
	{ 240, 186, 82 },
	{ 156, 120, 220 },
	{ 86, 186, 196 },
	{ 236, 140, 96 },
	{ 100, 156, 226 },
	{ 214, 214, 222 },
}

local GRASS = { 98, 160, 70 }
local SAND = { 206, 178, 132 } -- paths
local ROCK = { 132, 120, 108 } -- scattered decor rocks
local STONE = { 196, 150, 102 } -- warm ranch stone (fountain stand-ins, plaza slots)
local STONE_TRIM = { 176, 160, 138 }
local POOL = { 120, 220, 170 } -- slime-goo water
local PLAZA = { 222, 198, 150 } -- ranch_plaza sand
local WOOD = { 110, 74, 48 }
local SIGN = { 222, 178, 120 }
local FENCE = { 150, 104, 68 }
local SIGN_BOARD = { 62, 42, 30 } -- dark wood: the lock sign's coloured text stays readable
local GOO = { 120, 255, 140 }

local function light(preset: string): WorldNode
	return { name = preset, class = "PointLight", preset = preset }
end

-- Kit mesh slot: MeshSwap (server) puts the MeshAssets mesh in this box. With
-- `standIn` the slot itself is invisible and decor-only (the primitive look
-- lives in siblings tagged MeshStandIn = name, hidden when the mesh lands).
local function meshSlot(node: WorldNode, mesh: string, standIn: boolean?): WorldNode
	local attributes = node.attributes or {}
	attributes.MeshAsset = mesh
	node.attributes = attributes
	if standIn then
		node.transparency = 1
		node.canCollide = false
		node.canQuery = false
		node.canTouch = false
	end
	return node
end

local function standIn(node: WorldNode, mesh: string): WorldNode
	local attributes = node.attributes or {}
	attributes.MeshStandIn = mesh
	node.attributes = attributes
	return node
end

-- MeshSwap fits a mesh to its slot box, so a slot that isn't the mesh's native
-- size times one `scale` squashes it (a 4x9x2 box made the signpost 0.32/0.62/0.26).
local function meshSize(mesh: string, scale: number): Vec
	local native = (MeshAssets.get(mesh) :: any).size :: Vec
	return { native[1] * scale, native[2] * scale, native[3] * scale }
end
-- Also for the WorldProps skins (server/WorldProps sets their MeshSize).
WorldLayout.meshSize = meshSize

local function block(name: string, size: Vec, pos: Vec, color: Vec, material: string?, rot: Vec?): WorldNode
	return {
		name = name,
		class = "Part",
		shape = "Block",
		size = size,
		pos = pos,
		rot = rot or { 0, 0, 0 },
		color = color,
		material = material or "SmoothPlastic",
	}
end

-- Upright cylinder (Roblox cylinders run along X, so roll 90 degrees).
local function disc(
	name: string,
	height: number,
	diameter: number,
	pos: Vec,
	color: Vec,
	material: string?,
	yaw: number?
): WorldNode
	return {
		name = name,
		class = "Part",
		shape = "Cylinder",
		size = { height, diameter, diameter },
		pos = pos,
		rot = { 0, yaw or 0, 90 },
		color = color,
		material = material or "SmoothPlastic",
	}
end

-- Frame helper: rotates local offsets by `yaw` degrees and adds `origin`.
local function frame(origin: Vec, yaw: number): (Vec) -> Vec
	local m = LayoutMath.orientation({ 0, yaw, 0 })
	return function(v: Vec): Vec
		return LayoutMath.add(origin, LayoutMath.apply(m, v))
	end
end

-- Yaw (degrees) that turns a kit front (+Z) at `pos` to face FOUNTAIN_CENTRE.
function WorldLayout.facingCentre(pos: Vec): number
	local c = WorldLayout.FOUNTAIN_CENTRE
	return math.deg(math.atan2(c[1] - pos[1], c[3] - pos[3]))
end

-- Map --------------------------------------------------------------------

-- Slime fountain (kit slime_fountain), kept under the contract name
-- Map.Volcano with Crater (the goo pool on top) as the drop origin.
local function volcano(): WorldNode
	local h = WorldLayout.FOUNTAIN_HEIGHT
	local d = WorldLayout.FOUNTAIN_DIAMETER
	local M = "slime_fountain"
	local c = WorldLayout.FOUNTAIN_CENTRE
	local function onAxis(y: number): Vec
		return { c[1], c[2] + y, c[3] }
	end
	local children: { WorldNode } = {
		standIn(disc("Rock1", 3, d, onAxis(1.5), STONE, "Slate"), M),
		standIn(disc("BasinRim", 1, d + 1, onAxis(3.5), STONE_TRIM, "Slate"), M),
		standIn(disc("Pool", 0.4, d - 3, onAxis(3.1), POOL, "Glass"), M),
		standIn(disc("Column", h - 8, 6, onAxis(3 + (h - 8) / 2), STONE, "Slate"), M),
		standIn(disc("Bowl", 3, 14, onAxis(h - 3.5), STONE_TRIM, "Slate"), M),
	}
	local pool = children[3]
	pool.canCollide = false
	-- Stand-in too: once the mesh is in, a d11 neon plate poked out round the
	-- mesh's own goo crown. It keeps its place as the drop origin and emitter host.
	local crater = standIn(disc("Crater", 0.6, 11, onAxis(h - 1.7), POOL, "Neon"), M)
	crater.canCollide = false
	-- Client emitters attach here (VisualsClient); the glow keeps the pool lit.
	crater.children = { light("CraterGlow") }
	table.insert(children, crater)
	-- The fountain's collision, shaped like the mesh (FOUNTAIN_PROFILE): a
	-- walkable plinth (ground to its 1.5-stud top), the trim bevel round the
	-- foot of the staves (r 12.3 up to 2.4; without it feet sank 1.1 studs
	-- into the bevel) and the silo wall from the plinth top to the eave. All
	-- invisible and anchored, tagged MeshCollider = M and off until the mesh
	-- loads: MeshSwap flips them on and the stand-ins off in one step
	-- (MeshStandInsCollide). While loading or failed the visible stand-ins
	-- are the only collision.
	local fp = WorldLayout.FOUNTAIN_PROFILE
	local wallHeight = fp.eaveTop - fp.plinthTop
	local trimHeight = fp.trimTop - fp.plinthTop
	local plinth = disc("BasinCollider", fp.plinthTop, fp.plinthRadius * 2, onAxis(fp.plinthTop / 2), STONE_TRIM)
	local trim = disc("TrimCollider", trimHeight, fp.trimRadius * 2, onAxis(fp.plinthTop + trimHeight / 2), STONE_TRIM)
	local wall = disc("SiloCollider", wallHeight, fp.wallRadius * 2, onAxis(fp.plinthTop + wallHeight / 2), STONE)
	local colliders = { plinth, trim, wall }
	for i, tier in WorldLayout.fountainTopTiers() do
		local height = tier[3] - tier[2]
		table.insert(colliders, disc(`TopCollider{i}`, height, tier[1] * 2, onAxis(tier[2] + height / 2), STONE))
	end
	for _, collider in colliders do
		collider.attributes = { MeshCollider = M }
		collider.transparency = 1
		collider.canCollide = false
		collider.canQuery = false
		collider.canTouch = false
		table.insert(children, collider)
	end
	-- Native bbox of the polished slime_fountain (stats size, no squash),
	-- placed so its silo axis is FOUNTAIN_CENTRE and its base is the ground.
	local fountainSize, silo = WorldLayout.FOUNTAIN_MESH_SIZE, WorldLayout.FOUNTAIN_SILO_OFFSET
	local fountainCentre: Vec = { c[1] - silo[1], c[2] + fountainSize[2] / 2, c[3] - silo[3] }
	local slot = meshSlot(block("FountainMesh", fountainSize, fountainCentre, STONE), M, true)
	slot.attributes = slot.attributes or {}
	slot.attributes.MeshStandInsCollide = false
	table.insert(children, slot)
	-- Emerge slimes, split out of the fountain (FOUNTAIN_SIZES): the same
	-- bbox-centre offset. Invisible until its mesh id is filled; bobbing can
	-- hook this slot later.
	local emergePos = LayoutMath.add(fountainCentre, WorldLayout.FOUNTAIN_EMERGE_OFFSET)
	table.insert(
		children,
		meshSlot(block("EmergeMesh", { 19.436, 12.798, 11.353 }, emergePos, POOL), "slime_fountain_emerge", true)
	)
	return { name = "Volcano", class = "Model", primaryPart = "Rock1", children = children }
end

-- Contract name Map.Chute. A goo ribbon along the mesh spiral (ends r 35.5),
-- not the old straight yaw-22.5 chute. MeshStandIn hides it once slime_fountain
-- loads (MeshSwap); it never collides, so a hidden copy can't wall the plaza.
local function chute(): WorldNode
	local path = WorldLayout.SLIDE_PATH
	local children: { WorldNode } = {}
	local width, thick = 7, 0.6
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local delta = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
		local length = math.sqrt(delta[1] ^ 2 + delta[2] ^ 2 + delta[3] ^ 2)
		if length < 1e-3 then
			continue
		end
		local mid = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 + thick / 2, (a[3] + b[3]) / 2 }
		local rot = LayoutMath.facing(LayoutMath.scale(delta, 1 / length))
		local part =
			block(if i == 1 then "Floor" else `Span{i}`, { width, thick, length + 0.35 }, mid, GOO, "Glass", rot)
		part.canCollide = false
		part.canQuery = false
		part.canTouch = false
		table.insert(children, standIn(part, "slime_fountain"))
	end
	return { name = "Chute", class = "Model", primaryPart = "Floor", children = children }
end

local function plotYaw(i: number): number
	return (i - 1) * 360 / Config.PLOT_COUNT
end

-- 20° curb tile. Arc centre (plaza origin) is outside the mesh: at yaw 0 the
-- bbox centre sits on +Z (FBX stake match, ranch_landing_ring). Visual only;
-- the box is deeper than the stones and must not leave an invisible wall.
local LANDING_TILES = 18
-- The slide's last stretch (r 31..35.5, 7 wide) runs under tiles 1..5 (yaw 0..80) and the goo lane leaves
-- its mouth through tiles 18 and 17 (yaw 340, 320; 17's cushion and goo splat sat against the lane's first
-- bend): those seven are left out, so the ring opens where the slide lands slimes
-- and the lane starts (ParadeLane.MOUTH). Nothing stands over the slide or the lane start.
local LANDING_GAP =
	table.freeze({ [16] = true, [17] = true, [0] = true, [1] = true, [2] = true, [3] = true, [4] = true })
local LANDING_SIZE: Vec = { 13.145, 3.145, 10.27 }
local LANDING_BBOX = 38.678

-- Collision for the curb (the box above is deeper than the stones: it stays decor). The real stones (kit
-- ranch_landing_ring: r 34..35.7 from the plaza centre, 1.25 +- 0.08 tall, three per tile) get one thin invisible box
-- per tile, LANDING_CURB_HEIGHT high: under a Humanoid's step height, so it is a step-over, never a wall. The wood
-- stake at each tile's -X end (0.8 x 0.8, 2.6 tall, kit angle -9.4 deg) gets its own post. The ring is open over the
-- seven gap tiles (the slide mouth and the lane start), so nobody is walled in. docs/COLLISION.md.
WorldLayout.LANDING_CURB_HEIGHT = 1.3
local LANDING_CURB_RADIUS = 34.85 -- centre line of the stones
local LANDING_CURB_LENGTH = 12.0 -- chord of one tile's three stones (arc 12.4, seams)
local LANDING_CURB_DEPTH = 1.7
local LANDING_STAKE_ANGLE = -9.4 -- degrees from the tile's middle, kit x is world x
-- Goo drain (kit ranch_goo_drain): the curb ring (r 4.4, 1.0 + 0.22 warning tiles) round the funnel is one disc, the
-- warning post (0.7 x 4.2) and its plaque (2.6 x 1.9 x 0.35) on the fountain side. Kit +y is world -z; the curb
-- centre is 0.475 past the box centre (ParadeLane.DRAIN z 52.5).
WorldLayout.DRAIN_CURB_HEIGHT = 1.22
local DRAIN_CENTRE_Z = 52.475

-- Outer edge of the curb on +Z (r 43.8): the slide exit strip starts here.
WorldLayout.LANDING_OUTER_RADIUS = LANDING_BBOX + LANDING_SIZE[3] / 2

-- The paths (ring, spokes) and the plaza are FloorLayout's baked boardwalk and deck on top of the terrain (B11); the
-- voxel terrain (GroundTerrain, written by server/GroundTerrainView) stays the walk surface underneath.

-- Deterministic hash in [0, 1) so the decor is the same in every build.
local function hash(i: number, salt: number): number
	local x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function onPolar(yaw: number, r: number, y: number): Vec
	local n = LayoutMath.direction(yaw, 0)
	return { -n[1] * r, y, -n[3] * r }
end

-- Decor rocks are plain ranch Rock (no basalt). Upright boxes read as grey
-- crates from the plaza and low tilted slabs as paving tiles (tools/render
-- review), so every rock is a Ball: half boulders sunk to a low dome, half
-- wider flat stones sunk to their top sixth. Same part count as before.
local function rock(name: string, pos: Vec, s: number, salt: number): WorldNode
	local d, y
	if hash(salt, 10) < 0.5 then
		d = s * (1.2 + hash(salt, 4) * 0.5)
		y = -d * 0.22
	else
		d = s * (1.3 + hash(salt, 4) * 0.5)
		y = d * (0.15 + hash(salt, 5) * 0.05 - 0.5)
	end
	return {
		name = name,
		class = "Part",
		shape = "Ball",
		size = { d, d, d },
		pos = { pos[1], y, pos[3] },
		rot = { 0, 0, 0 },
		color = ROCK,
		material = "Rock",
	}
end

local function mushroom(name: string, pos: Vec, salt: number): WorldNode
	local h = 1.6 + hash(salt, 21) * 1.6
	local capColor = if hash(salt, 22) < 0.5 then { 232, 72, 104 } else { 240, 158, 64 }
	local m = { name = name, class = "Model", primaryPart = "Stem", children = {} :: { WorldNode } }
	table.insert(m.children :: { WorldNode }, disc("Stem", h, 0.8, { pos[1], h / 2, pos[3] }, { 246, 232, 206 }))
	table.insert(m.children :: { WorldNode }, {
		name = "Cap",
		class = "Part",
		shape = "Ball",
		size = { h * 1.3, h * 1.3, h * 1.3 },
		pos = { pos[1], h, pos[3] },
		rot = { 0, 0, 0 },
		color = capColor,
		material = "SmoothPlastic",
	})
	return m
end

-- Keeps decor off the drop ring (34..62 + margin), the ring path, plots,
-- spoke paths, the chute, the prop spots and the border wall.
local function clearSpot(pos: Vec, radius: number): boolean
	local r = math.sqrt(pos[1] ^ 2 + pos[3] ^ 2)
	if r < WorldLayout.RING_PATH_RADIUS + 6 + radius or r > WorldBorder.RADIUS - 10 - radius then
		return false
	end
	for i = 1, Config.PLOT_COUNT do
		local c = WorldLayout.plotCentre(i)
		local half = WorldLayout.PLOT_SIZE / 2 + 6 + radius
		if math.abs(pos[1] - c[1]) < half and math.abs(pos[3] - c[3]) < half then
			return false
		end
		-- spoke path i: from the ring to the plot entrance
		local n = LayoutMath.direction(plotYaw(i), 0)
		local along = -(pos[1] * n[1] + pos[3] * n[3])
		local across = math.abs(pos[1] * n[3] - pos[3] * n[1])
		if along > 0 and along < WorldLayout.PLOT_RING_RADIUS and across < 6 + radius then
			return false
		end
	end
	for _, spot in WorldLayout.PROP_SPOTS do
		if (pos[1] - spot.pos[1]) ^ 2 + (pos[3] - spot.pos[3]) ^ 2 < (12 + radius) ^ 2 then
			return false
		end
	end
	for _, prop in WorldLayout.RANCH_PROPS do
		if (pos[1] - prop.pos[1]) ^ 2 + (pos[3] - prop.pos[3]) ^ 2 < (prop.radius + 2 + radius) ^ 2 then
			return false
		end
	end
	return true
end

-- Placeholder look per kit prop (shown only while its mesh isn't in);
-- anything not listed is plain planks.
local RANCH_LOOKS: { [string]: { any } } = {
	ranch_hay_bale = { { 228, 196, 110 }, "Fabric" },
	ranch_crate_goo = { { 120, 220, 140 }, "WoodPlanks" },
	ranch_feed_trough = { WOOD, "Wood" },
	ranch_shed = { { 176, 92, 72 }, "WoodPlanks" },
	ranch_barn_loft = { { 176, 92, 72 }, "WoodPlanks" },
	ranch_well = { ROCK, "Slate" },
	ranch_campfire = { { 236, 140, 60 }, "SmoothPlastic" },
	ranch_sunflower_patch = { { 240, 200, 80 }, "Grass" },
	ranch_pumpkin_patch = { { 236, 140, 60 }, "Grass" },
	ranch_flower_planter = { { 250, 150, 182 }, "WoodPlanks" },
	ranch_lantern_post = { { 168, 148, 110 }, "Metal" },
	ranch_mailbox = { { 168, 148, 110 }, "Metal" },
	ranch_milk_churn = { { 168, 148, 110 }, "Metal" },
	ranch_goo_bucket = { { 120, 220, 140 }, "WoodPlanks" },
	ranch_goo_hive = { { 228, 196, 110 }, "Fabric" },
	ranch_horseshoe_pit = { SAND, "Sand" },
}

export type RanchProp = {
	name: string,
	mesh: string,
	cluster: string,
	scale: number,
	pos: Vec, -- slot centre (base on the ground)
	yaw: number, -- world orientation, degrees
	size: Vec, -- native size * scale
	radius: number, -- half the XZ diagonal: a circle that holds the footprint
	tint: Vec?, -- slot colour for MeshTint (near white), yard props only
}

local function resolveProp(p: RanchProps.Placement): RanchProp
	local size = meshSize(p.mesh, p.scale)
	local pos: Vec, yaw: number
	if p.plot then
		local centre, plotTurn = WorldLayout.plotCentre(p.plot)
		pos = frame(centre, plotTurn)({ p.x :: number, size[2] / 2, p.z :: number })
		yaw = plotTurn + p.yaw
	else
		local a = math.rad(p.angle :: number)
		local r = p.r :: number
		pos = { math.sin(a) * r, size[2] / 2, math.cos(a) * r }
		yaw = (p.angle :: number) + p.yaw
	end
	return {
		name = p.name,
		mesh = p.mesh,
		cluster = p.cluster,
		scale = p.scale,
		pos = pos,
		yaw = yaw % 360,
		size = size,
		radius = math.sqrt(size[1] ^ 2 + size[3] ^ 2) / 2,
		tint = p.tint,
	}
end

-- Scattered rocks and mushrooms between and behind the plots, and where they
-- landed (x, z, radius).
local function scatter(): ({ WorldNode }, { { number } })
	local children: { WorldNode } = {}
	local placed: { { number } } = {}
	local function add(node: WorldNode, pos: Vec, radius: number): boolean
		if clearSpot(pos, radius) then
			table.insert(children, node)
			table.insert(placed, { pos[1], pos[3], radius })
			return true
		end
		return false
	end
	local rocks, mushrooms = 0, 0
	for k = 1, 120 do
		local yaw = hash(k, 1) * 360
		local r = 90 + hash(k, 2) * 205
		local pos = onPolar(yaw, r, 0)
		if hash(k, 30) < 0.6 then
			local s = 2 + hash(k, 31) * 4
			if add(rock(`Rock{rocks + 1}`, pos, s, k), pos, s) then
				rocks += 1
			end
		else
			if add(mushroom(`Mushroom{mushrooms + 1}`, pos, k), pos, 2) then
				mushrooms += 1
			end
		end
	end
	return children, placed
end

-- Meadow clusters in the grass band behind the plots (Meadow), clear of the
-- same ground as the scatter (plots, spoke paths, prop spots, kit props) and
-- of the scattered rocks and mushrooms themselves.
function WorldLayout.meadowClusters(): { Meadow.Cluster }
	local _, placed = scatter()
	return Meadow.clusters(function(x: number, z: number, radius: number): boolean
		for _, p in placed do
			if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < (p[3] + radius + 2) ^ 2 then
				return false
			end
		end
		return clearSpot({ x, 0, z }, radius)
	end)
end

local function decor(): WorldNode
	local children = scatter()
	table.insert(children, Meadow.build(WorldLayout.meadowClusters()) :: any)
	-- Kit ranch props (RanchProps table, PropClearance keeps them off the
	-- lanes); the rocks and mushrooms above already stepped round them.
	for _, prop in WorldLayout.RANCH_PROPS do
		local look = RANCH_LOOKS[prop.mesh] or { WOOD, "WoodPlanks" }
		local slot = block(prop.name, prop.size, prop.pos, look[1], look[2], { 0, prop.yaw, 0 })
		-- Decor (no MeshAssets.COLLISION entry) never collides, mesh or not. A colliding mesh keeps its slot box as the
		-- collider until MeshSwap places the mesh, which then turns the box off.
		if MeshAssets.collision(prop.mesh) == nil then
			slot.canCollide = false
		end
		if prop.cluster == "yard" then
			-- Yard dressing: the slot colour is a slight tint of the mesh (MeshTint multiplies the vertex colours, so near white
			-- keeps the kit's look). SnowKind "none": under snow the props keep their own colours, only the sand yard whitens.
			slot.attributes = { MeshTint = true, [FloorLayout.SNOW_KIND_ATTRIBUTE] = "none" }
			slot.color = prop.tint or slot.color
		end
		table.insert(children, meshSlot(slot, prop.mesh))
	end
	-- The map edge (walls + edge decor) is WorldBorder, built as Map.Border.
	return { name = "Decor", class = "Folder", children = children }
end

-- Plaza showpieces between the drop ring (62) and the ring path, as kit mesh
-- slots. The Top Earners board and shop stand skin the live WorldProps models
-- (ShopStand / LeaderboardBoard, MeshAsset on the Model).
local function plazaProp(name: string, mesh: string, yaw: number, r: number, scale: number)
	return { name = name, mesh = mesh, yaw = yaw, r = r, size = meshSize(mesh, scale) }
end
WorldLayout.PLAZA_PROPS = table.freeze({
	plazaProp("Signpost", "ranch_plaza_signpost", 112.5, 68, 0.62),
	plazaProp("Podium_1", "phoenix_plaza_podium_1", 157.5, 68, 0.7),
	plazaProp("Podium_2", "phoenix_plaza_podium_2", 150, 68, 0.7),
	plazaProp("Podium_3", "phoenix_plaza_podium_3", 165, 68, 0.7),
})
WorldLayout.PROP_MESHES = table.freeze({
	ItemShopStand = WorldLayout.BUY_STAND_MESH,
	UpgradeShopStand = WorldLayout.BUY_STAND_MESH,
	LeaderboardBoard = "phoenix_top_earners_board",
})

local function visualMesh(node: WorldNode, mesh: string): WorldNode
	node.canCollide = false
	node.canQuery = false
	node.canTouch = false
	-- Not uploaded yet: a visible box that never collides buried the wilds that
	-- landed in it (landing ring r33.5..43.8, goo drain). Hidden until the id lands.
	if MeshAssets.meshId(mesh) == nil then
		node.transparency = 1
	end
	return meshSlot(node, mesh)
end

-- The landing ring's and the goo drain's solids (see the constants above): invisible Parts, built at runtime by
-- server/PlazaColliders under Map.Plaza.PlazaColliders. Not part of build(): the 1400 layout parts budget is full.
function WorldLayout.plazaColliders(): { WorldNode }
	local c = WorldLayout.FOUNTAIN_CENTRE
	local colliders: { WorldNode } = {}
	local function solidBlock(name: string, size: Vec, pos: Vec, yaw: number)
		local part = block(name, size, pos, STONE, "Slate", { 0, yaw, 0 })
		part.transparency = 1
		part.canQuery = false
		part.canTouch = false
		table.insert(colliders, part)
	end
	for i = 0, LANDING_TILES - 1 do
		if LANDING_GAP[i] then
			continue
		end
		local yaw = i * (360 / LANDING_TILES)
		local a, h = math.rad(yaw), WorldLayout.LANDING_CURB_HEIGHT
		solidBlock(
			`LandingCurb{i + 1}`,
			{ LANDING_CURB_LENGTH, h, LANDING_CURB_DEPTH },
			{ c[1] + math.sin(a) * LANDING_CURB_RADIUS, c[2] + h / 2, c[3] + math.cos(a) * LANDING_CURB_RADIUS },
			yaw
		)
		local s = a + math.rad(LANDING_STAKE_ANGLE)
		solidBlock(
			`LandingStake{i + 1}`,
			{ 0.8, 2.6, 0.8 },
			{ c[1] + math.sin(s) * LANDING_CURB_RADIUS, c[2] + 1.3, c[3] + math.cos(s) * LANDING_CURB_RADIUS },
			math.deg(s)
		)
	end
	local drainH = WorldLayout.DRAIN_CURB_HEIGHT
	local curb = disc("DrainCurb", drainH, 8.8, { c[1], c[2] + drainH / 2, c[3] + DRAIN_CENTRE_Z }, STONE, "Slate")
	curb.transparency = 1
	curb.canQuery = false
	curb.canTouch = false
	table.insert(colliders, curb)
	solidBlock("DrainPost", { 0.7, 4.2, 0.7 }, { c[1], c[2] + 2.1, c[3] + DRAIN_CENTRE_Z - 5 }, 0)
	solidBlock("DrainPlaque", { 2.6, 1.9, 0.35 }, { c[1], c[2] + 3.5, c[3] + DRAIN_CENTRE_Z - 4.5 }, 0)
	return colliders
end

local function plaza(): WorldNode
	local children: { WorldNode } = {}
	for _, def in WorldLayout.PLAZA_PROPS do
		local size = def.size :: Vec
		local pos = onPolar(def.yaw, def.r, size[2] / 2)
		-- Kit front (+Z) faces the fountain: the slot at (sin, cos) * r turned
		-- yaw + 180 (yaw alone put the podium plaques and sign faces outward).
		table.insert(
			children,
			meshSlot(block(def.name, size, pos, STONE, "Slate", { 0, (def.yaw + 180) % 360, 0 }), def.mesh)
		)
	end
	local tiles: { WorldNode } = {}
	local y = LANDING_SIZE[2] / 2
	for i = 0, LANDING_TILES - 1 do
		if LANDING_GAP[i] then
			continue
		end
		local yaw = i * (360 / LANDING_TILES)
		local a = math.rad(yaw)
		local c = WorldLayout.FOUNTAIN_CENTRE
		local pos = { c[1] + math.sin(a) * LANDING_BBOX, c[2] + y, c[3] + math.cos(a) * LANDING_BBOX }
		table.insert(
			tiles,
			visualMesh(block(`Tile{i + 1}`, LANDING_SIZE, pos, PLAZA, "Slate", { 0, yaw, 0 }), "ranch_landing_ring")
		)
	end
	table.insert(children, { name = "LandingRing", class = "Folder", children = tiles })
	-- On the slide exit (+Z), post toward the fountain, clear of the splash pool.
	local drainSize: Vec = { 8.8, 4.45, 9.75 }
	table.insert(
		children,
		visualMesh(
			block(
				"GooDrain",
				drainSize,
				LayoutMath.add(WorldLayout.FOUNTAIN_CENTRE, { 0, drainSize[2] / 2, 52 }),
				PLAZA,
				"Slate"
			),
			"ranch_goo_drain"
		)
	)
	return { name = "Plaza", class = "Folder", children = children }
end

local function map(): WorldNode
	-- Void-safety floor only: invisible, flush with the terrain surface (y = 0) that GroundTerrainView writes
	-- over it, so a player never falls through if the terrain write is late or fails.
	local ground = block("Ground", { 640, 2, 640 }, { 0, -1, 0 }, GRASS, "Grass")
	ground.transparency = 1
	local children: { WorldNode } = { ground, volcano(), chute(), plaza(), decor(), WorldBorder.build() :: any }
	-- B11 floor (FloorLayout): the sand yard, boardwalk, plaza deck and lawns, on top of the terrain.
	for _, node in
		FloorLayout.build({
			ringRadius = WorldLayout.RING_PATH_RADIUS,
			ringWidth = WorldLayout.RING_PATH_WIDTH,
			plazaRadius = WorldLayout.PLAZA_RADIUS,
			plotRing = WorldLayout.PLOT_RING_RADIUS,
			plotSize = WorldLayout.PLOT_SIZE,
			plotFloorTop = WorldLayout.PLOT_FLOOR_TOP,
			plots = Config.PLOT_COUNT,
		})
	do
		table.insert(children, node :: any)
	end
	return { name = WorldLayout.MAP_NAME, class = "Folder", children = children }
end

-- Plots ------------------------------------------------------------------

local function polar(r: number, deg: number): (number, number)
	local a = math.rad(deg)
	return r * math.cos(a), r * math.sin(a)
end
WorldLayout.polar = polar

-- The floor (jar) pad j stands on.
function WorldLayout.padFloor(j: number): number
	return math.ceil(j / Config.PADS_PER_FLOOR)
end

-- Plot-local angle (degrees) of pad j on its jar's pad ring, counting round from half a step past the door. Upper
-- floors fill the ring; floor 1's pads keep the same gap at the door but stand FLOOR1_PAD_STEP apart, half either
-- side of it, so the back bay stays free for the vat and the lock button.
function WorldLayout.padAngle(j: number): number
	local n = Config.PADS_PER_FLOOR
	local k = (j - 1) % n
	local gap = 360 / n / 2
	if WorldLayout.padFloor(j) > 1 then
		return WorldLayout.DOOR.angle + gap + k * 2 * gap
	end
	local step = WorldLayout.FLOOR1_PAD_STEP
	if k < n // 2 then
		return WorldLayout.DOOR.angle + gap + k * step
	end
	return WorldLayout.DOOR.angle + 360 - gap - (n - 1 - k) * step
end

-- Local pad centre (x, z) for pad index 1..PADS_MAX on its jar's pad ring.
function WorldLayout.padOffset(j: number): (number, number)
	return polar(WorldLayout.PAD_RINGS[WorldLayout.padFloor(j)], WorldLayout.padAngle(j))
end

-- Plot-local yaw (degrees) that turns pad j's box square to the jar's centre.
function WorldLayout.padYaw(j: number): number
	return 90 - WorldLayout.padAngle(j)
end

-- Inner radius of jar f's glass.
function WorldLayout.jarRadius(f: number): number
	return WorldLayout.JAR_RADII[f]
end

-- Plot-local angle (degrees) of tread k (1..steps) of the stair that climbs from floor f to f + 1. Tread k's top is
-- k studs above floor f; the last tread is flush with the deck above.
function WorldLayout.treadAngle(f: number, k: number): number
	local st = WorldLayout.STAIR
	local turn = 360 + 90 -- one full turn per floor, then a quarter turn on to the next stair's first tread
	return (st.firstAngle + (f - 1) * turn + (k - 1) * st.angle) % 360
end

function WorldLayout.stairSteps(): number
	return math.floor(WorldLayout.FLOOR_HEIGHT + 0.5)
end

-- Plot-local height of floor f's walking surface (floor 1 is the Base top).
function WorldLayout.floorTop(f: number): number
	return WorldLayout.PLOT_FLOOR_TOP + (f - 1) * WorldLayout.FLOOR_HEIGHT
end

function WorldLayout.plotCentre(i: number): (Vec, number)
	local yaw = plotYaw(i)
	local n = LayoutMath.direction(yaw, 0)
	-- direction() points along -Z at yaw 0; plots sit behind it (+Z side)
	-- so their local -Z (the entrance) faces the volcano.
	local r = WorldLayout.PLOT_RING_RADIUS
	return { -n[1] * r, 0, -n[3] * r }, yaw
end

-- Decor only: anchored, never collides, never blocks prompts or raycasts.
local function ghost(node: WorldNode, transparency: number?): WorldNode
	node.canCollide = false
	node.canQuery = false
	node.canTouch = false
	node.transparency = transparency
	return node
end

-- The doorway through jar 1's glass (plot-local, door at -Z). The stopper's collider (LockBarrier.Stopper) fills it
-- from DOOR_OUTER_PAD outside the glass to the PlotLockGuard limit (DOOR_INNER_INSET in from the glass), so a
-- character in the passage counts as inside and the stopper can never squeeze one in or out.
WorldLayout.DOOR_OUTER_PAD = 0.5
WorldLayout.DOOR_INNER_INSET = 2 -- = PlotLockGuard.MARGIN (tests/LockBarrier.spec checks)
function WorldLayout.doorway(): { size: Vec, centre: Vec, halfWidth: number, zOuter: number, zInner: number }
	local r = WorldLayout.jarRadius(1)
	local zOuter = -(r + WorldLayout.JAR_WALL + WorldLayout.DOOR_OUTER_PAD)
	local zInner = -(r - WorldLayout.DOOR_INNER_INSET)
	local d = WorldLayout.DOOR
	return {
		size = { d.width, d.height, zInner - zOuter },
		centre = { 0, WorldLayout.PLOT_FLOOR_TOP + d.height / 2, (zOuter + zInner) / 2 },
		halfWidth = d.width / 2,
		zOuter = zOuter,
		zInner = zInner,
	}
end

-- The floor (jar) whose storey holds plot-local height y, clamped to the tower.
function WorldLayout.floorAt(y: number): number
	return math.clamp(
		math.floor((y - WorldLayout.PLOT_FLOOR_TOP) / WorldLayout.FLOOR_HEIGHT) + 1,
		1,
		#WorldLayout.JAR_RADII
	)
end

local JAR_GLASS = { 200, 240, 244 }
local JAR_CORK = { 214, 170, 116 }
local JAR_GOO = { 110, 226, 170 }
WorldLayout.JAR_GLASS_TRANSPARENCY = 0.6
-- The jar glass meshes have an outer and an inner surface (Roblox culls back faces), so each is clearer; seen through
-- both it stacks to about the single primitive pane's look.
WorldLayout.JAR_GLASS_MESH_TRANSPARENCY = 0.7
-- The drop tube's goo-tinted glass is clearer still, so the slimes packed in it show.
WorldLayout.DROP_TUBE_GLASS_TRANSPARENCY = 0.55
-- The jar meshes' shape above each floor (shared/modeling-kit/models/_goo_jar.py builds to these). A jar with another
-- on it: straight glass `wall` high, then a rounded shoulder `shoulder` high in to the next jar's neck. The top jar:
-- straight glass `topWall` high, then a round dome `topDome` high in to a neck of `topNeck` x its radius, a glass lip
-- `lip` high, and on it the tall cork stopper (`cork`) or, on the last jar, the flat crown lid (`lid`). The mascot
-- sits on the top cork.
WorldLayout.JAR_SHAPE = table.freeze({
	wall = 9,
	shoulder = 3.6,
	topWall = 7.5,
	topDome = 6.5,
	topNeck = 0.5,
	lip = 0.8,
	cork = 3.2,
	lid = 1.6,
})
-- Mascot radius for a tower of v jars: MASCOT.base + MASCOT.grow * v (the mesh is built at radius 1).
WorldLayout.MASCOT = table.freeze({ base = 3.4, grow = 1.3, crownUp = 1.45 })

-- A box whose local +Z points out along plot-local angle `deg` at radius `r`, `size` = { tangential, height,
-- radial }, its centre `y` up.
local function radial(
	name: string,
	size: Vec,
	r: number,
	deg: number,
	y: number,
	at: (Vec) -> Vec,
	yaw: number
): WorldNode
	local x, z = polar(r, deg)
	return block(name, size, at({ x, y, z }), JAR_GLASS, "Glass", { 0, yaw + 90 - deg, 0 })
end

-- Attribute-driven plot cosmetics (PlotDecor; VisualsClient shows / hides them locally): the stopper lock and the
-- lock sign, rebirth trim / pillars / banners / crown, SlimeDex board. Shipped in their neutral state: free plot,
-- unlocked, no rebirths, empty dex.
local function cosmetics(at: (Vec) -> Vec, yaw: number, s: number): { WorldNode }
	local r = { 0, yaw, 0 }
	local h = s / 2
	local nodes: { WorldNode } = {}

	-- Lock: the cork Stopper fills jar 1's doorway (hidden and non-colliding = unlocked; the server makes it solid
	-- while locked). The ParkedStopper lies in the moat beside the door while the plot is open.
	local door = WorldLayout.doorway()
	local barrier: WorldNode = { name = "LockBarrier", class = "Model", children = {} }
	-- Half a stud wider than the opening each side, so it seals against the glass segments beside the door.
	local stopper =
		block("Stopper", { door.size[1] + 1, door.size[2], door.size[3] }, at(door.centre), JAR_CORK, "Wood", r)
	table.insert(barrier.children :: { WorldNode }, ghost(stopper, 1))
	table.insert(nodes, barrier)
	local moat = (WorldLayout.MOAT.inner + WorldLayout.MOAT.outer) / 2
	local px, pz = polar(moat, WorldLayout.DOOR.angle - 22)
	local parked = disc("ParkedStopper", 2.6, WorldLayout.DOOR.width * 0.8, at({ px, 1.4, pz }), JAR_CORK, "Wood", yaw)
	table.insert(nodes, ghost(parked))

	-- Lock sign by the bridge, facing out of the plot (Front face); the post carries the name board (Sign) above it.
	local bx, bz = WorldLayout.LOCK_SIGN_SPOT[1], WorldLayout.LOCK_SIGN_SPOT[2]
	local postH = WorldLayout.NAME_BOARD.y + WorldLayout.NAME_BOARD.height / 2 - 1
	local lockSign = ghost(block("LockSign", { 6, 2.6, 0.3 }, at({ bx + 1.5, 7.2, bz + 2.6 }), SIGN_BOARD, "Wood", r))
	lockSign.children = {
		ghost(block("Post", { 0.5, postH, 0.5 }, at({ bx + 1.5, 1 + postH / 2, bz + 3.0 }), FENCE, "Wood", r)),
		ghost(disc("Lamp", 0.4, 1.3, at({ bx - 1.8, 7.2, bz + 2.6 }), { 90, 220, 110 }, "Neon", yaw)),
	}
	table.insert(nodes, lockSign)

	-- Rebirth cosmetics (PlotDecor.band): the trim ring round the moat, corner pillars, banners on the glass either
	-- side of the door, the crown over the door.
	local rebirth: WorldNode = { name = "RebirthDecor", class = "Model", children = {} }
	local function add(node: WorldNode)
		table.insert(rebirth.children :: { WorldNode }, ghost(node, 1))
	end
	local metal = { 168, 148, 110 } -- ranch_metal (pewter); blue-grey is off the ranch palette
	add(disc("Trim_Moat", 0.3, (WorldLayout.MOAT.outer + 0.8) * 2, at({ 0, 0.92, 0 }), metal, "Metal", yaw))
	for k, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = corner[1] * (h - 1), corner[2] * (h - 1)
		add(block(`Pillar_{k}`, { 2.2, 10, 2.2 }, at({ x, 6, z }), metal, "Marble", r))
		local cap = { name = `PillarCap_{k}`, class = "Part", shape = "Ball", size = { 2.6, 2.6, 2.6 } } :: WorldNode
		cap.pos, cap.rot, cap.color, cap.material = at({ x, 12.3, z }), r, metal, "Neon"
		add(cap)
	end
	local glassOut = WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL + 0.1
	for k, deg in WorldLayout.BANNER_ANGLES do
		local banner = radial(if k == 1 then "Banner_R" else "Banner_L", { 3, 7, 0.15 }, glassOut, deg, 8.5, at, yaw)
		banner.color, banner.material = metal, "Fabric"
		add(banner)
	end
	local crown = { name = "Crown", class = "Part", shape = "Ball", size = { 3, 3, 3 } } :: WorldNode
	crown.pos, crown.rot, crown.color, crown.material = at({ 0, 14, -(glassOut + 1.5) }), r, metal, "Neon"
	add(crown)
	table.insert(nodes, rebirth)

	return nodes
end

-- Pad_<j> on its floor: the Pad stays the gameplay surface (collision, prompt, slimes rest on its top) from the
-- floor up to the stand's seat; the stand mesh sits on the floor at native size and the Pad hides under it once it
-- lands.
local function padNode(j: number, at: (Vec) -> Vec, yaw: number, color: Vec): WorldNode
	local x, z = WorldLayout.padOffset(j)
	local y = WorldLayout.floorTop(WorldLayout.padFloor(j))
	local turn = { 0, yaw + WorldLayout.padYaw(j), 0 }
	local look = WorldLayout.PAD_MESH
	local seat = WorldLayout.PAD_SEAT_Y
	local ps = WorldLayout.PAD_SIZE
	local pad = block(`Pad_{j}`, { ps, seat, ps }, at({ x, y + seat / 2, z }), color, "SmoothPlastic", turn)
	pad.attributes = { PadIndex = j }
	standIn(pad, look)
	local stand = meshSize(look, 1)
	pad.children = { meshSlot(block("Stand", stand, at({ x, y + stand[2] / 2, z }), color, nil, turn), look, true) }
	return pad
end

-- Radius of the centre of jar f's collision wall segments: their inner faces are a polygon inscribed in the jar's
-- glass (its corners on the glass), so nobody stands inside the glass mesh.
function WorldLayout.jarWallRadius(f: number): number
	return WorldLayout.jarRadius(f) * math.cos(math.pi / WorldLayout.JAR_WALL_SEGMENTS) + WorldLayout.JAR_WALL / 2
end

-- The point (x, z) at plot-local angle `deg` on the centre plane of jar f's wall segments (the polygon round the jar).
function WorldLayout.jarWallPoint(f: number, deg: number): (number, number)
	local step = 360 / WorldLayout.JAR_WALL_SEGMENTS
	local off = ((deg - WorldLayout.DOOR.angle + step / 2) % step) - step / 2
	return polar(WorldLayout.jarWallRadius(f) / math.cos(math.rad(off)), deg)
end

-- Jar f's glass wall collision: JAR_WALL_SEGMENTS collidable segments from floor f up to the deck (or lid) above (the
-- glass mesh is the look; they show as glass until it lands). Jar 1's segment at DOOR.angle is the door: two jambs
-- either side of the opening and the lintel over it. Glass never blocks prompts or raycasts.
local function jarWall(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	local out = {}
	local n = WorldLayout.JAR_WALL_SEGMENTS
	local r = WorldLayout.jarWallRadius(f)
	local width = 2 * (r + WorldLayout.JAR_WALL / 2) * math.tan(math.pi / n) + 0.3
	local h = WorldLayout.FLOOR_HEIGHT - 1
	local base = WorldLayout.floorTop(f)
	local t = WorldLayout.JAR_WALL
	for k = 1, n do
		local deg = WorldLayout.DOOR.angle + (k - 1) * 360 / n
		local nodes
		if f == 1 and k == 1 then
			local dh, dw = WorldLayout.DOOR.height, WorldLayout.DOOR.width
			local jw = (width - dw) / 2
			local x, z = polar(r, deg)
			local tx, tz = -math.sin(math.rad(deg)), math.cos(math.rad(deg))
			local turn = { 0, yaw + 90 - deg, 0 }
			local off = dw / 2 + jw / 2
			nodes = {
				radial("DoorLintel", { width, h - dh, t }, r, deg, base + dh + (h - dh) / 2, at, yaw),
				block(
					"DoorJambL",
					{ jw, dh, t },
					at({ x - tx * off, base + dh / 2, z - tz * off }),
					JAR_GLASS,
					"Glass",
					turn
				),
				block(
					"DoorJambR",
					{ jw, dh, t },
					at({ x + tx * off, base + dh / 2, z + tz * off }),
					JAR_GLASS,
					"Glass",
					turn
				),
			}
		else
			nodes = { radial(`Wall_{k}`, { width, h, t }, r, deg, base + h / 2, at, yaw) }
		end
		for _, node in nodes do
			node.transparency = WorldLayout.JAR_GLASS_TRANSPARENCY
			node.canQuery = false
			node.canTouch = false
			table.insert(out, node)
		end
	end
	return out
end

-- Floor f's deck (f >= 2): DECK_SEGMENTS boxes making a ring from the stair hole out over jar f - 1's glass, so it is
-- also that jar's lid. Its top is floor f's walking surface.
local function jarDeck(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	local out = {}
	local n = WorldLayout.DECK_SEGMENTS
	local inner = WorldLayout.STAIR.hole
	local outer = WorldLayout.jarRadius(f - 1) + WorldLayout.JAR_WALL
	local width = 2 * outer * math.sin(math.pi / n) * 1.02
	for k = 1, n do
		local deg = (k - 0.5) * 360 / n
		local node = radial(
			`Deck_{k}`,
			{ width, 1, outer - inner },
			(inner + outer) / 2,
			deg,
			WorldLayout.floorTop(f) - 0.5,
			at,
			yaw
		)
		node.color = JAR_GOO
		node.material = "SmoothPlastic"
		table.insert(out, node)
	end
	return out
end

-- The spiral stair from floor f up to floor f + 1: the centre post and one tread per stud of height.
local function jarStair(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	local st = WorldLayout.STAIR
	local base = WorldLayout.floorTop(f)
	local h = WorldLayout.FLOOR_HEIGHT
	local out = { disc("StairPost", h, st.post * 2, at({ 0, base + h / 2, 0 }), JAR_GOO, "SmoothPlastic", yaw) }
	local mid = (st.post + st.outer) / 2
	for k = 1, WorldLayout.stairSteps() do
		local node = radial(
			`Tread_{k}`,
			{ 2.9, 1, st.outer - st.post + 0.4 },
			mid,
			WorldLayout.treadAngle(f, k),
			base + k - 0.5,
			at,
			yaw
		)
		node.color = JAR_CORK
		node.material = "Wood"
		table.insert(out, node)
	end
	return out
end

-- Jar f's lid: the roof while jar f is the top jar (server/BaseFloors hides it while jar f + 1 stands).
local function jarLid(f: number, at: (Vec) -> Vec, yaw: number): WorldNode
	local r = WorldLayout.jarRadius(f) + WorldLayout.JAR_WALL
	local lid = disc("Lid", 1, r * 2, at({ 0, WorldLayout.floorTop(f + 1) - 0.5, 0 }), JAR_CORK, "Wood", yaw)
	lid.attributes = { JarLid = f }
	lid.transparency = 1 -- the roof's look is the jar trim mesh (cork lid or stopper)
	return lid
end

-- Goo jar tower meshes (JarMeshes: every uploaded kit piece's box round its build anchor). jarLook makes the mesh slot
-- for `mesh`: an invisible decor box exactly where the kit builder put the piece, round plot-local `anchor`, turned
-- `turn` degrees (Roblox yaw) and scaled by `scale`. The primitives it replaces carry MeshStandIn = that mesh, so
-- they hide (and keep their collision) once it lands.
local function jarLook(
	name: string,
	mesh: string,
	anchor: Vec,
	at: (Vec) -> Vec,
	yaw: number,
	turn: number?,
	scale: number?
): WorldNode
	local m = (JarMeshes :: any)[mesh]
	assert(m, `no JarMeshes entry for {mesh}`)
	local k = scale or 1
	local t = math.rad(turn or 0)
	local cx, cy, cz = m.centre[1] * k, m.centre[2] * k, m.centre[3] * k
	local x = cx * math.cos(t) + cz * math.sin(t)
	local z = -cx * math.sin(t) + cz * math.cos(t)
	local size = { m.size[1] * k, m.size[2] * k, m.size[3] * k }
	local pos = at({ anchor[1] + x, anchor[2] + cy, anchor[3] + z })
	-- These meshes are built in game axes; MeshSwap turns a Part slot's mesh by MeshAssets.IMPORT_YAW (180), so the
	-- slot turns half round more to undo it (measured in Studio: the drop tube's ends land where the builder put them).
	local node = block(name, size, pos, JAR_CORK, nil, { 0, yaw + (turn or 0) + 180, 0 })
	return meshSlot(node, mesh, true)
end

-- Glass slots: the mesh wears Glass at the mesh glass transparency (or `clear`) and casts no shadow, so the jars and
-- the tube stay light inside (server/MeshSwap reads these).
local function glassy(node: WorldNode, clear: number?): WorldNode
	local a = node.attributes or {}
	a.MeshMaterial = "Glass"
	a.MeshTransparency = clear or WorldLayout.JAR_GLASS_MESH_TRANSPARENCY
	a.MeshCastShadow = false
	node.attributes = a
	return node
end

-- A look shown only while jar `floor` is the top jar ("top") or only while a jar stands on it ("covered");
-- server/BaseFloors flips JarHidden (and the mesh) as jars come and go. Built as jar `floor` alone on top.
local function variant(node: WorldNode, floor: number, show: string): WorldNode
	local a = node.attributes or {}
	a.JarFloor = floor
	a.JarShow = show
	a.JarHidden = show == "covered"
	node.attributes = a
	return node
end

-- An opaque jar look that casts no shadow (the decks, trim and stair): the floor under them stays light.
local function noShadow(node: WorldNode): WorldNode
	local a = node.attributes or {}
	a.MeshCastShadow = false
	node.attributes = a
	return node
end

-- Jar f's lamp: an invisible point under its ceiling holding a JarGlow light, so the jar is light inside.
local function jarLamp(f: number, at: (Vec) -> Vec): WorldNode
	local lamp = block(
		"JarLamp",
		{ 0.5, 0.5, 0.5 },
		at({ 0, WorldLayout.floorTop(f) + WorldLayout.FLOOR_HEIGHT - 4, 0 }),
		JAR_GLASS
	)
	lamp.transparency = 1
	lamp.canCollide = false
	lamp.canQuery = false
	lamp.canTouch = false
	lamp.children = { { name = "Glow", class = "PointLight", preset = "JarGlow" } }
	return lamp
end

local function standIns(nodes: { WorldNode }, mesh: string)
	for _, node in nodes do
		standIn(node, mesh)
	end
end

-- Height of top jar f's neck lip (where its cork or crown lid sits) above its floor. Jar 1's straight glass clears
-- its door, so its dome starts higher.
local function jarNeckY(f: number): number
	local sh = WorldLayout.JAR_SHAPE
	local wall = 0.2 + sh.topWall
	if f == 1 then
		wall = math.max(wall, WorldLayout.DOOR.height + 0.3)
	end
	return wall + sh.topDome + sh.lip
end

-- The looks of jar f: glass and trim in the "top" form (a narrow neck with the cork stopper, or the crowned lid on the
-- last jar; hidden while a jar stands on it) and the mascot on its top cork (crowned on the last jar). Above floor 1
-- also jar f - 1 in its "covered" form (a wide neck this jar stands in), this jar's deck, the stair up into it and the
-- drop tube for a tower of f jars.
local function jarLooks(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	local base = { 0, WorldLayout.floorTop(f), 0 }
	local last = f >= #Config.BASE_FLOORS
	local out = {
		variant(glassy(jarLook("GlassTop", `goo_jar_glass_{f}_top`, base, at, yaw)), f, "top"),
		variant(noShadow(jarLook("TrimTop", `goo_jar_trim_{f}_top`, base, at, yaw)), f, "top"),
		jarLamp(f, at),
	}
	local m = WorldLayout.MASCOT
	local size = m.base + m.grow * f
	local lidTop = WorldLayout.floorTop(f)
		+ jarNeckY(f)
		+ (if last then WorldLayout.JAR_SHAPE.lid else WorldLayout.JAR_SHAPE.cork)
	table.insert(out, variant(jarLook("MascotLook", "goo_jar_mascot", { 0, lidTop, 0 }, at, yaw, 0, size), f, "top"))
	if last then
		local crown = { 0, lidTop + size * m.crownUp, 0 }
		table.insert(out, variant(jarLook("CrownLook", "goo_jar_crown", crown, at, yaw, 0, size), f, "top"))
	end
	if f >= 2 then
		-- jar f - 1 in its covered form (a wide neck this jar stands in): it only shows while this jar stands
		local below = { 0, WorldLayout.floorTop(f - 1), 0 }
		table.insert(out, glassy(jarLook("GlassBelow", `goo_jar_glass_{f - 1}_mid`, below, at, yaw)))
		table.insert(out, noShadow(jarLook("TrimBelow", `goo_jar_trim_{f - 1}_mid`, below, at, yaw)))
		table.insert(out, noShadow(jarLook("DeckLook", `goo_jar_deck_{f}`, base, at, yaw)))
		-- the stair mesh is built on floor 1's treads; each floor's stair starts a quarter turn further round
		local turn = -(WorldLayout.treadAngle(f - 1, 1) - WorldLayout.treadAngle(1, 1))
		table.insert(out, noShadow(jarLook("StairLook", "goo_jar_stair", below, at, yaw, turn)))
		local ground = { 0, WorldLayout.floorTop(1) - 1, 0 }
		local tubeGlass = jarLook("TubeGlass", `goo_drop_tube_glass_{f}`, ground, at, yaw)
		table.insert(out, variant(glassy(tubeGlass, WorldLayout.DROP_TUBE_GLASS_TRANSPARENCY), f, "top"))
		table.insert(out, variant(jarLook("TubeGoo", `goo_drop_tube_goo_{f}`, ground, at, yaw), f, "top"))
	end
	return out
end

-- Plot-local landing point (x, y, z) of the drop tube: the splash pool behind the tower.
function WorldLayout.dropLanding(): Vec
	local x, z = polar(WorldLayout.MOAT.outer + 1.0, WorldLayout.DROP_ANGLE)
	return { x, WorldLayout.PLOT_FLOOR_TOP + 3, z }
end

-- Upper jar f (2..#BASE_FLOORS) of plot i, as the nodes the server adds under Plot_<i>: a Floor_<f> Model (deck,
-- glass wall, the stair up from floor f - 1, the lid, the drop-tube hatch) and the jar's Pad_<j>.
function WorldLayout.floor(i: number, f: number): { WorldNode }
	assert(f >= 2 and f <= #Config.BASE_FLOORS, `floor {f} is not an upper floor`)
	local centre, yaw = WorldLayout.plotCentre(i)
	local at = frame(centre, yaw)
	local color = PLOT_COLORS[(i - 1) % #PLOT_COLORS + 1]
	local children: { WorldNode } = {}
	local deck, wall, stair = jarDeck(f, at, yaw), jarWall(f, at, yaw), jarStair(f - 1, at, yaw)
	standIns(deck, `goo_jar_deck_{f}`)
	standIns(wall, `goo_jar_glass_{f}_top`)
	standIns(stair, "goo_jar_stair")
	for _, list in { deck, wall, stair, jarLooks(f, at, yaw) } do
		for _, node in list do
			table.insert(children, node)
		end
	end
	table.insert(children, jarLid(f, at, yaw))
	local hatch = radial(
		"DropHatch",
		{ 3.4, 4, 0.6 },
		WorldLayout.jarRadius(f) - 0.4,
		WorldLayout.DROP_ANGLE,
		WorldLayout.floorTop(f) + 2,
		at,
		yaw
	)
	hatch.color = JAR_CORK
	hatch.material = "Wood"
	table.insert(children, hatch)
	-- The goo tube (decor, never collides): an arm from the hatch out through the glass, and this floor's length of
	-- the upright tube down to the next arm below (floor 2's reaches the ground and its splash pool).
	local tube = WorldLayout.DROP_TUBE
	local armIn = WorldLayout.jarRadius(f) + WorldLayout.JAR_WALL
	local armY = WorldLayout.floorTop(f) + 2
	local arm = radial(
		"TubeArm",
		{ tube.width, tube.width, tube.radius - armIn },
		(armIn + tube.radius) / 2,
		WorldLayout.DROP_ANGLE,
		armY,
		at,
		yaw
	)
	local lo = if f == 2 then WorldLayout.PLOT_FLOOR_TOP else WorldLayout.floorTop(f - 1) + 2
	local tx, tz = polar(tube.radius, WorldLayout.DROP_ANGLE)
	local pipe = disc(
		"Tube",
		armY + tube.width / 2 - lo,
		tube.width,
		at({ tx, (lo + armY + tube.width / 2) / 2, tz }),
		JAR_GOO,
		"Glass",
		yaw
	)
	for _, node in { arm, pipe } do
		node.color, node.material, node.transparency = JAR_GOO, "Glass", WorldLayout.JAR_GLASS_TRANSPARENCY
		table.insert(children, standIn(ghost(node, WorldLayout.JAR_GLASS_TRANSPARENCY), `goo_drop_tube_goo_{f}`))
	end
	if f == 2 then
		local land = WorldLayout.dropLanding()
		table.insert(
			children,
			ghost(
				disc(
					"SplashPool",
					0.2,
					6,
					at({ land[1], WorldLayout.PLOT_FLOOR_TOP + 0.1, land[3] }),
					JAR_GOO,
					"Glass",
					yaw
				)
			)
		)
	end
	for _, node in children do
		if node.name == "SplashPool" then
			standIn(node, "goo_drop_tube_goo_2")
		end
	end
	local nodes: { WorldNode } =
		{ { name = `Floor_{f}`, class = "Model", attributes = { FloorIndex = f }, children = children } }
	for j = (f - 1) * Config.PADS_PER_FLOOR + 1, f * Config.PADS_PER_FLOOR do
		table.insert(nodes, padNode(j, at, yaw, color))
	end
	return nodes
end

local function plot(i: number): WorldNode
	local centre, yaw = WorldLayout.plotCentre(i)
	local at = frame(centre, yaw)
	local s = WorldLayout.PLOT_SIZE
	local r = { 0, yaw, 0 }
	local color = PLOT_COLORS[(i - 1) % #PLOT_COLORS + 1]
	local children: { WorldNode } = {
		-- sand like the plaza round it, so the round jar foot reads (the plot colour is on the jar's trim and labels)
		block("Base", { s, 1, s }, at({ 0, 0.5, 0 }), { 232, 214, 178 }, "Sand", r),
	}
	for j = 1, Config.PADS_PER_FLOOR do
		table.insert(children, padNode(j, at, yaw, color))
	end

	local zone = block("HomeZone", { s, 14, s }, at({ 0, 8, 0 }), color, "SmoothPlastic", r)
	zone.transparency = 1
	zone.canCollide = false
	zone.canQuery = false
	-- The zone check reaches up over every upper floor (CONTRACT.md §5.3).
	zone.attributes = { ReachUp = (#Config.BASE_FLOORS - 1) * WorldLayout.FLOOR_HEIGHT }
	table.insert(children, zone)

	-- Jar 1 (the static part of the tower): the goo moat and the cork floor inside it (decor on the Base, which stays
	-- the walking surface), the bridge to the door, the glass wall with the door, and the lid.
	local moat = WorldLayout.MOAT
	local moatDisc = ghost(disc("Moat", 0.2, moat.outer * 2, at({ 0, 1, 0 }), JAR_GOO, "Glass", yaw))
	local floorDisc = ghost(disc("JarFloor", 0.2, moat.inner * 2, at({ 0, 1.02, 0 }), JAR_CORK, "Wood", yaw))
	standIns({ moatDisc, floorDisc }, "goo_jar_foot")
	table.insert(children, moatDisc)
	table.insert(children, floorDisc)
	local f1 = WorldLayout.floorTop(1)
	table.insert(children, jarLook("FootLook", "goo_jar_foot", { 0, f1, 0 }, at, yaw))
	local bridgeLen = s / 2 - WorldLayout.jarRadius(1)
	local bridge = block(
		"Bridge",
		{ WorldLayout.BRIDGE_WIDTH, 0.4, bridgeLen },
		at({ 0, 1.2, -(s / 2 - bridgeLen / 2) }),
		WOOD,
		"WoodPlanks",
		r
	)
	bridge.canQuery = false
	table.insert(children, bridge)
	local wall1 = jarWall(1, at, yaw)
	standIns(wall1, "goo_jar_glass_1_top")
	local jar: WorldNode = { name = "Jar", class = "Model", children = wall1 }
	table.insert(jar.children :: { WorldNode }, jarLid(1, at, yaw))
	table.insert(children, jar)
	-- jar 1's mesh looks (decor slots) beside the solid Jar
	table.insert(children, { name = "JarLooks", class = "Model", children = jarLooks(1, at, yaw) })
	-- the round door, its lock ring (MeshTint: PlotDecor turns it red while locked) and the two stopper looks
	-- (PlotDecor shows the door shut, StopperShut, while locked and swung open, StopperParked, while open)
	table.insert(children, jarLook("DoorLook", "goo_jar_door", { 0, f1, 0 }, at, yaw))
	local ring = jarLook("DoorRing", "goo_jar_door_ring", { 0, f1, 0 }, at, yaw)
	ring.color = { 168, 148, 110 }
	local ringAttrs = ring.attributes or {}
	ringAttrs.MeshTint = true
	ring.attributes = ringAttrs
	table.insert(children, ring)
	local dz = WorldLayout.doorway().zOuter + 0.6
	local dy = WorldLayout.DOOR.height / 2 + 0.1
	local doorY, doorZ = f1 + dy - 4.6, dz + 0.3
	table.insert(children, jarLook("StopperShut", "goo_jar_stopper", { 0, doorY, doorZ }, at, yaw))
	-- open: the same door swung out of the jar round its hinge pin (DOOR_SWING)
	local swing = WorldLayout.DOOR_SWING
	local hx, hz = swing.hinge[1], doorZ + swing.hinge[2]
	local t = math.rad(swing.angle)
	local ax, az = -hx, doorZ - hz
	local open = { hx + ax * math.cos(t) + az * math.sin(t), doorY, hz - ax * math.sin(t) + az * math.cos(t) }
	table.insert(children, jarLook("StopperParked", "goo_jar_stopper", open, at, yaw, swing.angle))

	local vat = WorldLayout.VAT_SPOT
	local vx, vz = polar(vat.radius, vat.angle)
	-- The VatDecor mesh (server/MeshSwap) is the vat's look; the stand-in is the plain tub.
	table.insert(
		children,
		disc(
			"MergeVat",
			VatDecor.DISC_HEIGHT,
			VatDecor.DISC_DIAMETER,
			at({ vx, 1 + VatDecor.DISC_HEIGHT / 2, vz }),
			{ 150, 160, 180 },
			"Metal",
			yaw
		)
	)

	local bx, bz = WorldLayout.LOCK_BUTTON_SPOT[1], WorldLayout.LOCK_BUTTON_SPOT[2]
	local button = disc("LockButton", 0.6, 4, at({ bx, 2.8, bz }), { 255, 70, 70 }, "Neon", yaw)
	local pedestal = block("Pedestal", { 5, 1.5, 5 }, at({ bx, 1.75, bz }), FENCE, "WoodPlanks", r)
	standIns({ button, pedestal }, "goo_lock_button")
	button.children = { pedestal }
	table.insert(children, button)
	table.insert(children, jarLook("ButtonLook", "goo_lock_button", { bx, WorldLayout.floorTop(1), bz }, at, yaw))

	-- Sign = the plot's name board on the LockSign's post by the bridge (PlotSigns writes on its Front face, out of
	-- the plot).
	local board = WorldLayout.NAME_BOARD
	local sx, sz = WorldLayout.LOCK_SIGN_SPOT[1] + 1.5, WorldLayout.LOCK_SIGN_SPOT[2] + 2.6
	local sign = block("Sign", { board.width, board.height, 0.3 }, at({ sx, board.y, sz }), SIGN, "WoodPlanks", r)
	sign.canQuery = false
	table.insert(children, sign)

	for _, node in cosmetics(at, yaw, s) do
		table.insert(children, node)
	end

	table.insert(children, { name = WorldLayout.SLIMES_FOLDER, class = "Folder" })

	return {
		name = `Plot_{i}`,
		class = "Model",
		primaryPart = "Base",
		attributes = { PlotIndex = i, OwnerUserId = 0, LockUntil = 0, Rebirths = 0 },
		children = children,
	}
end

function WorldLayout.build(): { WorldNode }
	local plots = {}
	for i = 1, Config.PLOT_COUNT do
		table.insert(plots, plot(i))
	end
	return {
		map(),
		{ name = Constants.PLOTS_FOLDER, class = "Folder", children = plots },
	}
end

-- Kit props from the RanchProps table, resolved to world slots (deterministic).
local ranchProps: { RanchProp } = {}
local byName: { [string]: RanchProp } = {}
for _, p in RanchProps.PLACEMENTS do
	local prop = resolveProp(p)
	table.insert(ranchProps, prop)
	byName[prop.name] = prop
end
-- `face`: turn the kit front (+Z) at another prop.
for k, p in RanchProps.PLACEMENTS do
	if p.face then
		local prop, target = ranchProps[k], byName[p.face]
		assert(target, `RanchProps {p.name} faces unknown {p.face}`)
		prop.yaw = math.deg(math.atan2(target.pos[1] - prop.pos[1], target.pos[3] - prop.pos[3])) % 360
	end
end
WorldLayout.RANCH_PROPS = table.freeze(ranchProps)

return table.freeze(WorldLayout)
