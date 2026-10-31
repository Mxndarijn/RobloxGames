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
	           (rocks, the RanchProps kit props), Border
	           (WorldBorder: the invisible wall ring + seeded hedges, fences,
	           pines, hills, rocks along the edge). Kit meshes go on MeshAsset
	           slots via server/MeshSwap.
	  Plots    Plot_1..PLOT_COUNT in a ring around the fountain, each facing
	           it (door at local -Z): Base, jar 1 of the goo jar tower (Jar
	           glass wall + Lid, Moat, JarFloor, Bridge) with Pad_1..PADS_PER_FLOOR
	           on its pad ring, HomeZone, MergeVat, LockButton, Sign (the
	           plot's name board), Slimes folder, and the PlotDecor cosmetics
	           (LockBarrier stopper, ParkedStopper); SignLeg_1 / SignLeg_2 under the Sign.
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
local Leaderboards = if script
	then require(script.Parent.Parent.Shared.Leaderboards)
	else require("../../shared/Leaderboards")
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
WorldLayout.RING_RAIL_WIDTH = 0.8 -- the boardwalk's dark rails outside its planks (kit ranch_floor_paths RAIL_W)
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
-- degrees), up through the hole in the deck above; each stair starts exactly where the one below arrives, so the
-- ramps make one unbroken spiral from the ground to the top jar. Upper floors (Config.BASE_FLOORS beyond 1) are built at runtime by server/BaseFloors.
WorldLayout.FLOOR_HEIGHT = 16
WorldLayout.JAR_RADII = table.freeze({ 31, 27, 24, 21.5 })
WorldLayout.PAD_RINGS = table.freeze({ 22, 19, 16.5, 14.1 })
-- The gameplay Pad box (collision, prompt, PivotTo top) under each round cork stand; the stand's dish keeps the
-- crate deck's size (PAD_DECK.half), so the habitat overlays still fit on it.
WorldLayout.PAD_SIZE = 6.4
WorldLayout.JAR_WALL = 1 -- glass thickness
WorldLayout.JAR_WALL_SEGMENTS = 12
WorldLayout.DECK_SEGMENTS = 12
WorldLayout.DOOR = table.freeze({ angle = -90, width = 8, height = 11 }) -- no wider than one glass segment
WorldLayout.STAIR = table.freeze({ post = 1.5, outer = 5.5, hole = 6, angle = 22.5, firstAngle = 90 })
-- The stair is a smooth spiral ramp (easy on a thumbstick): `segments` sloped boxes climb FLOOR_HEIGHT over one turn,
-- from one step before tread 1's angle (WorldLayout.treadAngle) to tread FLOOR_HEIGHT's angle, ending flush
-- with the deck above, where the next floor's ramp goes on. The boxes slope as the helix does at radius `walk` (where
-- feet go). The rail is an invisible wall along the outer edge that follows the visible brass rail: from just under
-- the ramp to `railHeight` studs above it (too tall to step over, so nobody walks off by accident; a deliberate jump
-- clears it), never higher than just under the deck above. It leaves the floor under the ramp's high part and the
-- deck round the hole above free to walk. Open for `railStart` degrees at the bottom and `railEnd` degrees before the
-- top, so you step on and off the side.
WorldLayout.RAMP = table.freeze({ segments = 16, walk = 4.2, railStart = 30, railEnd = 45, railHeight = 2.5 })
-- The top of the stair, on the top jar only (where the stair ends; a jar added above hides it, server/BaseFloors):
-- the ramp goes on for `landing` more degrees, flat at floor height and out to the edge of the hole (no gap to the
-- floor), so you arrive on a small platform instead of running straight off the end. No fence round the hole. The
-- ramp below passes under it: at 120 degrees it still has about 9.7 studs of headroom there (tests/JarTower.spec keeps
-- at least 6). Built in `step`-degree pieces, so keep `landing` a multiple of `step`.
WorldLayout.STAIR_TOP = table.freeze({ landing = 120, step = 30 })
-- The centre post's stub above the top jar's deck (the kit's Newel, collar and round cap, in the trim mesh): a solid
-- cylinder `radius` wide (the cap's) and `height` tall (the cap's top), so nobody stands inside it.
WorldLayout.STAIR_NEWEL = table.freeze({ radius = 1.7, height = 4 })
WorldLayout.MOAT = table.freeze({ inner = 34.5, outer = 38.5 })
-- The drop tube runs down the back; the top jar's hatch sits at this angle, the tube lands in the goo moat.
-- DROP_TUBE: the tube's radius out from the jar centre (over the moat, outside jar 1's glass), its width, and how far
-- along the moat a dropped player lands from the tube's foot (clear of its solid upright, still on the splash pool).
WorldLayout.DROP_ANGLE = 70
WorldLayout.DROP_TUBE = table.freeze({ radius = 37, width = 3, landSide = 2.8 })
-- Jar 1's ground pieces (plot-local; angles as above). The bridge crosses the moat to the door. Floor 1's pads spread
-- evenly from FLOOR1_PAD_ARC[1] to FLOOR1_PAD_ARC[2] degrees round from the door, leaving the front either side of the
-- door free: the MergeVat and the LockButton stand there, one each side, the first things you see coming in (inside
-- and on the ground floor, so nobody camps an owner's button from outside). The plot's sign (Sign, PlotSigns draws on
-- both faces) stands outside by the bridge in a cradle (SignRail) on two short stubs (SignLeg_1, SignLeg_2).
-- Players spawn on the walkway between the stair and the pads, in front of the door.
WorldLayout.BRIDGE_WIDTH = 10
WorldLayout.FLOOR1_PAD_ARC = table.freeze({ 60, 300 })
WorldLayout.VAT_SPOT = table.freeze({ angle = -62, radius = 24 }) -- inside, left of the door as you come in
WorldLayout.LOCK_BUTTON_SPOT = table.freeze({ -11.27, -21.19 }) -- inside, right of the door (angle -118, radius 24)
-- The plot floor is round (the old square sand plate is gone): a collider disc PLOT_FLOOR_RADIUS in radius
-- (PlotFloor), its look the goo_jar_foot mesh; the square Base part stays as the plot's anchor (invisible, never
-- collides).
WorldLayout.PLOT_FLOOR_RADIUS = 40
WorldLayout.SIGN_SPOT = table.freeze({ 8.5, -36.5 }) -- on the moat by the bridge, across from the parked stopper
-- The plot sign by the bridge (Sign, shared/MascotSign): the jar's mascot peeking over a glass nameplate, 6 x 3 studs,
-- at eye level, seated in a wooden cradle (SignRail) on two short stubs (SignLeg_1, SignLeg_2): its bottom a stud
-- above the ground, its top just under a player's head. PlotSigns draws it on both faces, so the cradle and stubs
-- stand under the sign, not behind it, and the rail grips only the empty strip under the stats line (`grip` studs).
WorldLayout.SIGN_LEGS = table.freeze({ width = 0.6, depth = 0.5, inset = 0.9 }) -- studs; inset = from each end of the sign to a leg's centre
WorldLayout.SIGN_RAIL = table.freeze({ width = 5.6, height = 0.3, depth = 0.55, grip = 0.1 })

-- The sign's centre (plot-local x, z): by the bridge, a little in from SIGN_SPOT.
function WorldLayout.signCentre(): (number, number)
	return WorldLayout.SIGN_SPOT[1] + 1.5, WorldLayout.SIGN_SPOT[2] + 2.6
end
WorldLayout.NAME_BOARD = table.freeze({ width = 6, height = 3, y = 3.5 })
-- Jar 1's door is a round plank door on two hinges on its left (-X). Locked, it sits shut in the doorway (StopperShut);
-- open, it swings DOOR_SWING.angle degrees out of the jar round its hinge pin (StopperParked): past square, so it
-- leans back over the moat on the hinge side and its far edge stays about a stud inside the plot's edge (a 90
-- degree swing would reach past it; much more than 130 runs it into the glass). hinge = the pin's
-- plot x and its z offset from the shut door's inner face (the door is 1 stud thick, the pin in its middle).
WorldLayout.DOOR_SWING = table.freeze({ hinge = { -4.75, -0.5 }, angle = 130 })
-- The round door's disc (the goo_jar_stopper mesh's door: radius and thickness) and how far its OpenDoorCollider's
-- hinge edge stays off the hinge pin, so the open door's collider never pokes onto the bridge.
WorldLayout.DOOR_DISC = table.freeze({ radius = 4.6, thickness = 1, hingeClear = 1.3 })
WorldLayout.SPAWN_SPOT = table.freeze({ 0, -12.5 })
-- DEX_FACE = the front cream panel of phoenix_top_earners_board (the plaza
-- Top Earners board's skin) at native size, measured on
-- out/phoenix_top_earners_board.fbx in the mesh's own frame (front +Z): centre
-- x off the box centre, centre y up from the bottom, front face z ahead of the
-- box centre. (Named for the plot SlimeDex board that used to wear the same
-- mesh; Props / PropMesh.spec still lay the board's text out on it.)
WorldLayout.DEX_FACE = table.freeze({ x = -0.35, y = 11.53, front = 0.4, width = 12.9, height = 11.5 })
-- The shop stands (WorldProps Models, Props.shopStand) by model name. Each skins its own kit mesh at `scale`:
-- ItemShopStand a pink market stall (models/ranch_item_shop.py), UpgradeShopStand a blue and gold cabinet that shows
-- the upgrades (models/ranch_upgrade_cabinet.py).
-- `face` = the sign face the SHOP text goes on and `counter` = the counter the Counter part fills, at native size
-- from the kit source in the mesh's own frame (front +Z): centre x, y up from the bottom, z from the box centre
-- (+ = front); `front` is the sign's front face, `top` the counter top. The stand's pivot is its box's bottom centre.
-- 0.7 is the largest scale at which the Upgrade cabinet (11.5 x 10.7 x 7.0) fits its spot between plots 1 and 2
-- (PropClearance); the Item stall wears the same scale so the two counters match.
type StandFace = { x: number, y: number, front: number, width: number, height: number }
type StandCounter = { x: number, z: number, width: number, depth: number, top: number }
export type ShopStand = { mesh: string, scale: number, face: StandFace, counter: StandCounter }
local function shopStand(mesh: string, scale: number, face: StandFace, counter: StandCounter): ShopStand
	return table.freeze({ mesh = mesh, scale = scale, face = table.freeze(face), counter = table.freeze(counter) })
end
WorldLayout.SHOP_STANDS = table.freeze({
	ItemShopStand = shopStand(
		"ranch_item_shop",
		0.7,
		{ x = 0, y = 11.533, front = -2.275, width = 7.6, height = 2 },
		{ x = 0, z = 0.675, width = 11, depth = 4.2, top = 4.233 }
	),
	UpgradeShopStand = shopStand(
		"ranch_upgrade_cabinet",
		0.7,
		{ x = 0, y = 12.5, front = 4.685, width = 7.6, height = 1.6 },
		{ x = 0, z = 1.535, width = 11, depth = 3.6, top = 4.1 }
	),
}) :: { [string]: ShopStand }

-- The Exclusive Shop's Golden Jar Boutique (contract/exclusive-shop.md §7; WorldProps places it,
-- Props.exclusiveJar builds it, the client's ShopDisplayFx shows the featured seats in it). It completes the market row
-- on the east ring (Upgrade Shop 34.5, Item Shop 67.5, Exclusive Shop 112.5): on the plot 3 / plot 4 bisector, facing
-- the fountain, at `scale`. At full size its footprint fits r 92.3-94.35, between the ring path (outer edge r 82) and
-- the two plots' front corners (PropClearance); `radius` is the middle. Two kit meshes
-- (models/exclusive_jar_boutique.py): `shop` (plinth, goo dome, gold lid, trophy slime, pedestals, shop front, awning,
-- sign board) and `glass`, the see-through jar wall. The points below are the
-- kit's (out/exclusive_jar_boutique_layout.json) in the Blender frame at native size (x right, y back, z up; the front
-- faces -y), measured from the shop mesh's bottom centre; WorldLayout.jarPoint turns one into the stand's frame.
--   groundZ       the grass over the shop mesh's bottom (its goo drips hang below the ground)
--   glassOrigin   the glass mesh's bottom centre; the jar's axis runs straight up through it
--   displays      the 3 pedestal spots inside the jar: the bottom of each floating featured seat
--   counter       the counter top's centre; counterSize its width and depth
--   signFace      the centre of the sign board's lilac face (its front plane); signSize its width and height
--   footprint     the plinth's radius with its goo rim and lanterns
-- `displayWidth` = the widest side of a shown seat (a seat template is scaled to it), stand studs.
WorldLayout.EXCLUSIVE_JAR = table.freeze({
	model = Constants.SHOP_STAND_EXCLUSIVE,
	bearing = 112.5,
	radius = 93.3,
	scale = 1,
	shop = "exclusive_jar_boutique",
	glass = "exclusive_jar_boutique_glass",
	groundZ = 0.201,
	glassOrigin = table.freeze({ 0, 0.855, 1.401 }),
	displays = table.freeze({
		table.freeze({ -3.3, 2.255, 7.551 }),
		table.freeze({ 0, 3.455, 9.751 }),
		table.freeze({ 3.3, 2.255, 7.551 }),
	}),
	counter = table.freeze({ 0, -6.345, 4.301 }),
	counterSize = table.freeze({ 9.6, 2.6 }),
	signFace = table.freeze({ 0, -6.755, 8.151 }),
	signSize = table.freeze({ 6.4, 1.4 }),
	footprint = 9.6,
	displayWidth = 3.2, -- the seats' own size: smaller ones vanish behind the glass
	glassTransparency = 0.88, -- clearer than a base jar's glass, so the clouds inside read from the plaza
})

-- A kit point of the jar (Blender frame, native studs) in the stand's own frame at the stand's scale, the stand's
-- origin on the ground: Props Models face local -Z, the kit front faces -y, so (x, y, z) -> (-x, z - groundZ, y) x scale.
function WorldLayout.jarPoint(p: { number }): Vec
	local jar = WorldLayout.EXCLUSIVE_JAR
	local k = jar.scale
	return { -p[1] * k, (p[3] - jar.groundZ) * k, p[2] * k }
end

-- Suggested placements for Props (pivot CFrame = CFrame.new(pos) *
-- CFrame.Angles(0, math.rad(yaw), 0)), just outside the ring path between
-- two spokes. The shop and the Top Earners board face the fountain (Props
-- front = local -Z; every shop faces the map centre, TODO v28 #10, v29 B3);
-- the tutorial NPC stands behind the hub SpawnLocation (scripts/StaticWorld,
-- same bearing) and faces it.
-- A Props Model's spot: pivot position, yaw and (optionally) a uniform Model scale.
export type Spot = { pos: Vec, yaw: number, scale: number? }

local function propSpot(angle: number, faceVolcano: boolean?, radius: number?): Spot
	-- Ring path outer edge is r 82 (78 + 8/2). 90 keeps a shop-sized prop off it.
	local r, a = radius or 90, math.rad(angle)
	return { pos = { math.sin(a) * r, 0, math.cos(a) * r }, yaw = if faceVolcano then angle else angle + 180 }
end
-- The Hall of Fame plaza in the yard between plots 4 and 5: a round plaza `distance` studs out at `bearing`, a plank
-- path from the ring path out to it, an arch where the path leaves the ring path, the five global boards
-- (Leaderboards.BOARDS, left to right as you walk in) on a ring just inside the plaza edge facing its centre, the
-- Top Earners podium on a stage disc in front of the big board and Professor Goo at the plaza entrance.
-- Plaza-local points: x to the right as you walk in, y towards the back (WorldLayout.hallPoint); board angles: 0 =
-- straight back, positive = to the right. The plaza keeps >= 15 studs from both round plots and stops short of the
-- border hedges (r ~277).
WorldLayout.HALL_OF_FAME = table.freeze({
	bearing = 157.5,
	distance = 222, -- plaza centre from the map centre
	radius = 50,
	rim = 3,
	boardRing = 46,
	boardAngles = table.freeze({ -94, -48, 0, 48, 94 }), -- Leaderboards.BOARDS order
	podiumBoardScale = 1.6, -- Top Earners: 1.6x the board
	boardScale = 1.05,
	stage = table.freeze({ x = 0, y = 31, radius = 16 }),
	podiums = table.freeze({ -- Podium_1..3 on the stage
		table.freeze({ x = 0, y = 32 }),
		table.freeze({ x = -9.5, y = 33 }),
		table.freeze({ x = 9.5, y = 33 }),
	}),
	pathWidth = 10,
	archDistance = 88, -- the arch, from the map centre, just past the ring path
	professor = table.freeze({ x = -9.5, y = -46, faceY = -72 }), -- left of the entrance, turned to the path
})

-- Where a podium mesh's flat top is, from its model (shared/modeling-kit/models/_phoenix_podium.py, model units):
-- the top is centred on the model's origin and the base plinth reaches `base` past the column's half width W/2 on
-- every side, but the goo puddle on one front corner sticks out further on the +X side and at the front. Roblox
-- centres the mesh (and the Podium_<rank> slot) on that lopsided box, so the top sits off the slot's centre.
-- `column` is each rank's W; the mesh's own size (MeshAssets) gives how far the puddle reaches.
WorldLayout.PODIUM_TOPS = table.freeze({
	column = table.freeze({ 5.6, 5.0, 4.6 }),
	base = 1.2,
})

-- The centre of podium `rank`'s flat top in its slot's local studs (x, z) for a slot of `sizeX` x `sizeZ`: the
-- slot's +X is the puddle side and +Z its front, so the top is a little towards -X and -Z. (0, 0) when the mesh
-- isn't known.
function WorldLayout.podiumTopCentre(rank: number, sizeX: number, sizeZ: number): (number, number)
	local T = WorldLayout.PODIUM_TOPS
	local entry = MeshAssets.get(`phoenix_plaza_podium_{rank}`)
	local w = T.column[rank]
	if not (entry and w) then
		return 0, 0
	end
	local function shift(slot: number, native: number): number
		-- the box spans -(W/2 + base) .. native - (W/2 + base), the top sits at 0: its centre is this far off
		local off = native / 2 - (w / 2 + T.base)
		return -off * slot / native
	end
	return shift(sizeX, entry.size[1]), shift(sizeZ, entry.size[3])
end

-- A Hall of Fame plaza-local point (x right as you walk in, y towards the back) in world studs (y = 0).
function WorldLayout.hallPoint(x: number, y: number): Vec
	local hall = WorldLayout.HALL_OF_FAME
	local a = math.rad(hall.bearing)
	local fx, fz = math.sin(a), math.cos(a)
	local d = hall.distance + y
	return { fx * d - fz * x, 0, fz * d + fx * x }
end

-- True when `pos` is on the Hall of Fame plaza or its path, grown by `pad` studs.
function WorldLayout.inHallOfFame(pos: Vec, pad: number): boolean
	local hall = WorldLayout.HALL_OF_FAME
	local centre = WorldLayout.hallPoint(0, 0)
	if (pos[1] - centre[1]) ^ 2 + (pos[3] - centre[3]) ^ 2 < (hall.radius + pad) ^ 2 then
		return true
	end
	local a = math.rad(hall.bearing)
	local along = pos[1] * math.sin(a) + pos[3] * math.cos(a)
	local across = math.abs(-pos[1] * math.cos(a) + pos[3] * math.sin(a))
	return along > WorldLayout.RING_PATH_RADIUS and along < hall.distance and across < hall.pathWidth / 2 + pad
end

-- The Hall of Fame floor for FloorLayout: the plaza, the stage disc and the path from the ring path's outer edge.
function WorldLayout.hallFloor(): any
	local hall = WorldLayout.HALL_OF_FAME
	local centre = WorldLayout.hallPoint(0, 0)
	local stage = WorldLayout.hallPoint(hall.stage.x, hall.stage.y)
	-- the path starts at the ring's outer rail: where the rail's curved outer edge crosses the path's two edges, so
	-- the corners meet the rail and the middle tucks under it
	local railOut = WorldLayout.RING_PATH_RADIUS + WorldLayout.RING_PATH_WIDTH / 2 + WorldLayout.RING_RAIL_WIDTH
	local from = math.sqrt(railOut ^ 2 - (hall.pathWidth / 2) ^ 2)
	local to = hall.distance - hall.radius + hall.rim
	local mid = WorldLayout.hallPoint(0, (from + to) / 2 - hall.distance)
	return {
		x = centre[1],
		z = centre[3],
		radius = hall.radius,
		rim = hall.rim,
		stage = { x = stage[1], z = stage[3], radius = hall.stage.radius },
		path = { x = mid[1], z = mid[3], width = hall.pathWidth, length = to - from, bearing = hall.bearing },
	}
end

-- Yaw that turns a Props Model (front = local -Z) at `from` to face `to`.
local function propYaw(from: Vec, to: Vec): number
	return math.deg(math.atan2(-(to[1] - from[1]), -(to[3] - from[3]))) % 360
end

local function hallSpots(): { [string]: Spot }
	local hall = WorldLayout.HALL_OF_FAME
	local centre = WorldLayout.hallPoint(0, 0)
	local spots: { [string]: Spot } = {}
	for i, def in Leaderboards.BOARDS do
		local a = math.rad(hall.boardAngles[i])
		local pos = WorldLayout.hallPoint(math.sin(a) * hall.boardRing, math.cos(a) * hall.boardRing)
		spots[def.model] = {
			pos = pos,
			yaw = propYaw(pos, centre),
			scale = if def.podium then hall.podiumBoardScale else hall.boardScale,
		}
	end
	local prof = hall.professor
	local at = WorldLayout.hallPoint(prof.x, prof.y)
	spots[Constants.PROFESSOR_GOO] = { pos = at, yaw = propYaw(at, WorldLayout.hallPoint(0, prof.faceY)) }
	local b = math.rad(hall.bearing)
	local arch = { math.sin(b) * hall.archDistance, 0, math.cos(b) * hall.archDistance }
	spots[Constants.HALL_ARCH] = { pos = arch, yaw = hall.bearing } -- the sign faces the fountain
	return spots
end

-- UpgradeShopStand sits between the plot 1 and 2 spokes, bearing 34.5 / r 96 (22.5 / r 92 is the Campfire / CampBench camp, 20 studs away; 35 at r 90-98 would clip the plot 2 entrance; CONTRACT.md §27.2).
-- The Upcoming Events wall (server/EventBoardView): a Hall of Fame board (Props.leaderboardBoard, its mesh) in the
-- middle of the lawn between the plot 5 and 6 spokes (the 202.5 bisector, mid-lawn radius), right behind the hub
-- SpawnLocation (r 64 at 202.5), facing the fountain; beside it only the well and its pump, on the plot 6 side
-- (RanchProps moved its picnic table and sunflowers to the 292.5 lawn).
WorldLayout.EVENT_BOARD = table.freeze({ model = "EventBoard", bearing = 202.5, radius = 92.25, scale = 1.05 })

-- The obby (contract/obby.md §5, server/ObbyView). Its portal stands in the yard between plots 8 and 1, opposite the
-- Hall of Fame, in the lawn lane between the two plots' fronts (r 100-185 is clear there), with the yard's windmill
-- scene (YardProps, r 185-210) behind it; a walk `pathWidth` wide runs to it from the ring path, under the OBBY arch
-- at `archDistance` (the ritual circle beside the path's plaza end keeps the arch that far out). Past r ~158 the
-- portal's keep-clear circle would push that windmill scene off its spot. A finished runner lands `exitStep` studs from
-- the portal, towards the plots. The course itself stands in its own world, `world`: `distance` studs out from the map
-- centre at `bearing` (far past any view distance and the map's Atmosphere), `height` studs up, running along `yaw`.
-- Everything within `radius` of the zone's centre counts as the obby world (the client's look swap, the server's
-- send-home).
WorldLayout.OBBY = table.freeze({
	bearing = 337.5,
	portalDistance = 155,
	portalRadius = 5, -- studs: stepping inside starts a run
	exitStep = 10,
	signStep = 9, -- the status sign stands this far behind the portal, facing the plaza
	clearRadius = 12, -- keep-clear circle for props round the portal and its sign
	pathWidth = 10,
	archDistance = 108, -- the arch, from the map centre: past the ritual circle (Config.RITUAL, bearing 348, r 93)
	world = table.freeze({
		bearing = 180,
		distance = 9000,
		height = 400,
		yaw = 180, -- the course runs on away from the map
		centreAhead = 150, -- the zone's centre, this far along the course from its origin
		radius = 1500,
		islands = 16,
		landmarks = 4, -- big islands far out, past the island rows
		clouds = 22,
		seaDepth = 220, -- the cloud sea's top, below the course origin
		seaRadius = 1000, -- the flat base under the cloud banks
		seaRings = table.freeze({ 1, 7, 16 }), -- cloud banks per ring (centre, middle, outer) on the sea
	}),
})

-- The obby portal centre on the ground (y = 0) and the yaw facing the map centre.
function WorldLayout.obbyPortal(): (Vec, number)
	local o = WorldLayout.OBBY
	local a = math.rad(o.bearing)
	return { math.sin(a) * o.portalDistance, 0, math.cos(a) * o.portalDistance }, (o.bearing + 180) % 360
end

-- The obby course frame in its own world: origin (course-local 0, 0, 0) and yaw (course forward).
function WorldLayout.obbyFrame(): (Vec, number)
	local w = WorldLayout.OBBY.world
	local a = math.rad(w.bearing)
	return { math.sin(a) * w.distance, w.height, math.cos(a) * w.distance }, w.yaw
end

-- The obby world's centre (`centreAhead` along the course from its origin) and radius.
function WorldLayout.obbyZone(): (Vec, number)
	local w = WorldLayout.OBBY.world
	local origin, yaw = WorldLayout.obbyFrame()
	local a = math.rad(yaw)
	return { origin[1] + math.sin(a) * w.centreAhead, origin[2], origin[3] + math.cos(a) * w.centreAhead }, w.radius
end

-- True when `pos` is in the obby world (within its radius of the centre, any height).
function WorldLayout.inObbyWorld(pos: Vec): boolean
	local c, r = WorldLayout.obbyZone()
	return (pos[1] - c[1]) ^ 2 + (pos[3] - c[3]) ^ 2 < r * r
end

-- The obby path for FloorLayout.starWalk: from where the ring's outer rail crosses its edges out to the portal.
function WorldLayout.obbyPath(): { x: number, z: number, width: number, length: number, bearing: number }
	local o = WorldLayout.OBBY
	local railOut = WorldLayout.RING_PATH_RADIUS + WorldLayout.RING_PATH_WIDTH / 2 + WorldLayout.RING_RAIL_WIDTH
	local from = math.sqrt(railOut ^ 2 - (o.pathWidth / 2) ^ 2)
	local to = o.portalDistance - o.portalRadius
	local a = math.rad(o.bearing)
	local mid = (from + to) / 2
	return { x = math.sin(a) * mid, z = math.cos(a) * mid, width = o.pathWidth, length = to - from, bearing = o.bearing }
end

-- True when `pos` is on the obby path or round the portal, grown by `pad` studs.
function WorldLayout.onObbyPath(pos: Vec, pad: number): boolean
	local o = WorldLayout.OBBY
	local a = math.rad(o.bearing)
	local along = pos[1] * math.sin(a) + pos[3] * math.cos(a)
	local across = math.abs(-pos[1] * math.cos(a) + pos[3] * math.sin(a))
	if along > WorldLayout.RING_PATH_RADIUS and along < o.portalDistance and across < o.pathWidth / 2 + pad then
		return true
	end
	local portal = WorldLayout.obbyPortal()
	return (pos[1] - portal[1]) ^ 2 + (pos[3] - portal[3]) ^ 2 < (o.clearRadius + pad) ^ 2
end

-- One backdrop piece of the obby world (visuals/client/ObbyBackdrop), course-local (x along the course, y up, z right).
-- kind: "island" | "landmark" | "cloud" | "bank" (a mesh, `model` names it in ObbyBackdrop.MESHES) or "sea" (the flat
-- base disc). `radius` is the piece's half-width in studs (the mesh is scaled to it), `yaw` its turn in degrees and
-- `tone` (1..3) a light tint.
export type ObbyBackdropPiece = { kind: string, model: string?, pos: Vec, radius: number, yaw: number, tone: number }

local OBBY_ISLANDS = { "obby_island_grove", "obby_island_village", "obby_island_crystal" }
local OBBY_LANDMARKS = { "obby_island_tree", "obby_island_mushroom" }

-- The obby world's backdrop: goo islands in two loose rows either side of the course (clear of its sides and
-- off-course band), a few big landmark islands far out, clouds farther out and a cloud sea far below: rings of cloud
-- banks at staggered heights over a flat base disc. Fixed numbers: every client builds the same.
function WorldLayout.obbyBackdrop(): { ObbyBackdropPiece }
	local w = WorldLayout.OBBY.world
	local out: { ObbyBackdropPiece } = {}
	for k = 1, w.islands do
		local t = (k - 1) / (w.islands - 1)
		local side = if k % 2 == 0 then 1 else -1
		table.insert(out, {
			kind = "island",
			model = OBBY_ISLANDS[k % #OBBY_ISLANDS + 1],
			pos = { -90 + t * 520, -80 + (k * 37) % 120, side * (85 + (k * 47) % 130) },
			radius = 14 + (k * 13) % 18,
			yaw = (k * 67) % 360,
			tone = k % 3 + 1,
		})
	end
	for k = 1, w.landmarks do
		local side = if k % 2 == 0 then 1 else -1
		table.insert(out, {
			kind = "landmark",
			model = OBBY_LANDMARKS[k % #OBBY_LANDMARKS + 1],
			pos = { -60 + (k - 1) * 150, -110 + (k * 41) % 90, side * (430 + (k * 89) % 180) },
			radius = 55 + (k * 23) % 30,
			yaw = (k * 101) % 360,
			tone = k % 3 + 1,
		})
	end
	for k = 1, w.clouds do
		local t = (k - 1) / (w.clouds - 1)
		local side = if k % 2 == 0 then -1 else 1
		table.insert(out, {
			kind = "cloud",
			model = if k % 3 == 0 then "obby_cloud_tower" else "obby_cloud_puff",
			pos = { -200 + t * 760, -60 + (k * 53) % 200, side * (260 + (k * 71) % 260) },
			radius = 22 + (k * 17) % 26,
			yaw = (k * 53) % 360,
			tone = k % 2 + 1,
		})
	end
	local ringRadius = { 0, w.seaRadius * 0.32, w.seaRadius * 0.66 }
	local n = 0
	for ring, count in w.seaRings do
		for i = 1, count do
			n += 1
			local a = (i - 1) / count * math.pi * 2 + ring * 0.7
			local r = ringRadius[ring]
			table.insert(out, {
				kind = "bank",
				model = "obby_cloudbank",
				pos = { w.centreAhead + math.cos(a) * r, -w.seaDepth - 26 + (n * 29) % 34, math.sin(a) * r },
				radius = 130 + (n * 37) % 60 + r * 0.08,
				yaw = (n * 77) % 360,
				tone = n % 3 + 1,
			})
		end
	end
	table.insert(
		out,
		{ kind = "sea", pos = { w.centreAhead, -w.seaDepth - 20, 0 }, radius = w.seaRadius * 1.1, yaw = 0, tone = 1 }
	)
	return out
end

local spots: { [string]: Spot } = {
	ItemShopStand = propSpot(67.5, true),
	UpgradeShopStand = propSpot(34.5, true, 96),
	TutorialNpc = propSpot(247.5, true),
}
do
	local jar = WorldLayout.EXCLUSIVE_JAR
	spots[jar.model] = propSpot(jar.bearing, true, jar.radius)
end
do
	local board = WorldLayout.EVENT_BOARD
	local spot = propSpot(board.bearing, true, board.radius)
	spot.scale = board.scale
	spots[board.model] = spot
end
for name, spot in hallSpots() do
	spots[name] = table.freeze(spot)
end
do
	local o = WorldLayout.OBBY
	local b = math.rad(o.bearing)
	spots[Constants.OBBY_ARCH] =
		table.freeze({ pos = { math.sin(b) * o.archDistance, 0, math.cos(b) * o.archDistance }, yaw = o.bearing })
end
WorldLayout.PROP_SPOTS = table.freeze(spots) :: { [string]: Spot }

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
		standIn(disc("Pool", 0.4, d - 3, onAxis(3.1), POOL, WorldLayout.JAR_GLASS_MATERIAL), M),
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
		local part = block(
			if i == 1 then "Floor" else `Span{i}`,
			{ width, thick, length + 0.35 },
			mid,
			GOO,
			WorldLayout.JAR_GLASS_MATERIAL,
			rot
		)
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

-- Kit ground decor scattered between the rocks where the space allows, taken in turn so every kind shows up. Mesh
-- slots, walk-through (no MeshAssets.COLLISION entry): each is a block until MeshSwap places the mesh.
WorldLayout.GROUND_DECOR = table.freeze({
	{ mesh = "decor_slime_nest", label = "Nest", look = { 228, 196, 110 } },
	{ mesh = "decor_wildflower_clump", label = "Wildflowers", look = { 250, 150, 182 } },
	{ mesh = "decor_goo_crystals", label = "GooCrystals", look = { 110, 226, 170 } },
	{ mesh = "decor_slime_topiary", label = "Topiary", look = { 88, 160, 92 } },
	{ mesh = "decor_watering_can", label = "WateringCan", look = { 214, 92, 84 } },
})

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
	if WorldLayout.inHallOfFame(pos, 4 + radius) or WorldLayout.onObbyPath(pos, 4 + radius) then
		return false
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

-- Scattered rocks and ground decor between and behind the plots, and where they
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
	local function apart(pos: Vec, radius: number): boolean
		for _, p in placed do
			if (p[1] - pos[1]) ^ 2 + (p[2] - pos[3]) ^ 2 < (p[3] + radius + 2) ^ 2 then
				return false
			end
		end
		return true
	end
	local function spot(k: number): Vec
		return onPolar(hash(k, 1) * 360, 90 + hash(k, 2) * 205, 0)
	end
	local rocks = 0
	for k = 1, 120 do
		if hash(k, 30) < 0.6 then
			local pos = spot(k)
			local s = 2 + hash(k, 31) * 4
			if add(rock(`Rock{rocks + 1}`, pos, s, k), pos, s) then
				rocks += 1
			end
		end
	end
	-- then the ground decor in the other spots, clear of every rock and of each other
	local decorCount = 0
	for k = 1, 120 do
		if hash(k, 30) >= 0.6 then
			local kind = WorldLayout.GROUND_DECOR[decorCount % #WorldLayout.GROUND_DECOR + 1]
			local size = meshSize(kind.mesh, 0.95 + hash(k, 32) * 0.25)
			local radius = math.sqrt(size[1] ^ 2 + size[3] ^ 2) / 2
			local pos = spot(k)
			if clearSpot(pos, radius) and apart(pos, radius) then
				decorCount += 1
				local slot = block(
					`{kind.label}{decorCount}`,
					size,
					{ pos[1], size[2] / 2, pos[3] },
					kind.look,
					"SmoothPlastic",
					{ 0, hash(k, 33) * 360, 0 }
				)
				slot.canCollide = false
				add(meshSlot(slot, kind.mesh), pos, radius)
			end
		end
	end
	return children, placed
end

-- Meadow clusters in the grass band behind the plots (Meadow), clear of the
-- same ground as the scatter (plots, spoke paths, prop spots, kit props) and
-- of the scattered rocks themselves.
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

-- Tree meshes stay decor (a hull of a tree is an invisible cone round the canopy); an invisible upright post per trunk
-- is the collision, so the leaves stay walk-through. Each post runs the tree's full height, so nobody jumps onto a post
-- top hidden in the leaves. Per mesh: { x, z, diameter } in the slot's own axes at the mesh's native size (scaled with
-- the slot), measured on the uploaded meshes at their trunk bases.
WorldLayout.TREE_TRUNKS = table.freeze({
	ranch_border_oak_round = { { -0.97, 0.17, 2.4 } },
	ranch_border_pine_broad = { { 0.23, -0.33, 2 } },
	ranch_border_pine_tall = { { 0.18, -0.33, 1.8 } },
	ranch_border_sapling_trio = { { 3.87, -0.28, 1.4 }, { 0.07, -1.88, 1.2 }, { -3.33, 0.12, 1.3 } },
} :: { [string]: { { number } } })

local function trunkPosts(prop: RanchProp): { WorldNode }
	local posts: { WorldNode } = {}
	local trunks = WorldLayout.TREE_TRUNKS[prop.mesh]
	if not trunks then
		return posts
	end
	local at = frame(prop.pos, prop.yaw)
	for _, t in trunks do
		local base = at({ t[1] * prop.scale, -prop.size[2] / 2, t[2] * prop.scale })
		local height = prop.size[2]
		local post = disc("Trunk", height, t[3] * prop.scale, { base[1], height / 2, base[3] }, WOOD)
		post.transparency = 1
		post.canTouch = false -- queryable: slime walk sweeps (WorldView, RespectCanCollide) route round it
		table.insert(posts, post)
	end
	return posts
end

local function decor(): WorldNode
	local children = scatter()
	table.insert(children, Meadow.build(WorldLayout.meadowClusters()) :: any)
	-- Kit ranch props (RanchProps table, PropClearance keeps them off the
	-- lanes); the rocks above already stepped round them.
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
			if string.sub(prop.mesh, 1, 13) == "ranch_border_" and MeshAssets.collision(prop.mesh) ~= nil then
				-- the yard's solid rocks, fences and hedge: slime walk sweeps and ground rays see them, like the trunk posts
				slot.attributes.MeshCanQuery = true
			end
			slot.color = prop.tint or slot.color
		end
		table.insert(children, meshSlot(slot, prop.mesh))
		for i, post in trunkPosts(prop) do
			post.name = `{prop.name}_Trunk{i}`
			table.insert(children, post)
		end
	end
	-- The map edge (walls + edge decor) is WorldBorder, built as Map.Border.
	return { name = "Decor", class = "Folder", children = children }
end

-- Plaza showpieces between the drop ring (62) and the ring path, as kit mesh
-- slots. The Top Earners board and shop stands skin the live WorldProps models
-- (ItemShopStand / UpgradeShopStand / LeaderboardBoard, MeshAsset on the Model).
local function plazaProp(name: string, mesh: string, yaw: number, r: number, scale: number)
	return { name = name, mesh = mesh, yaw = yaw, r = r, size = meshSize(mesh, scale) }
end
-- A podium on the Hall of Fame stage as a plaza prop: its bearing and radius from the map centre (it faces the fountain,
-- which from the plaza is straight back down the path to within 2 degrees).
local function podiumProp(rank: number, mesh: string): any
	local spot = WorldLayout.HALL_OF_FAME.podiums[rank]
	local pos = WorldLayout.hallPoint(spot.x, spot.y)
	local bearing = math.deg(math.atan2(pos[1], pos[3])) % 360
	local r = math.sqrt(pos[1] ^ 2 + pos[3] ^ 2)
	return plazaProp(`Podium_{rank}`, mesh, bearing, r, 0.7)
end
WorldLayout.PLAZA_PROPS = table.freeze({
	plazaProp("Signpost", "ranch_plaza_signpost", 124.5, 68, 0.62), -- off the Exclusive Shop's sight line from the fountain (it stands at 112.5)
	podiumProp(1, "phoenix_plaza_podium_1"),
	podiumProp(2, "phoenix_plaza_podium_2"),
	podiumProp(3, "phoenix_plaza_podium_3"),
})
local propMeshes: { [string]: string } = {
	ItemShopStand = WorldLayout.SHOP_STANDS.ItemShopStand.mesh,
	UpgradeShopStand = WorldLayout.SHOP_STANDS.UpgradeShopStand.mesh,
	TutorialNpc = "ranch_guide",
	[Constants.PROFESSOR_GOO] = "guide_professor",
	[WorldLayout.EVENT_BOARD.model] = "phoenix_top_earners_board", -- the Hall of Fame board frame
}
for _, def in Leaderboards.BOARDS do
	propMeshes[def.model] = "phoenix_top_earners_board"
end
WorldLayout.PROP_MESHES = table.freeze(propMeshes)

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

-- The Hall of Fame's dressing as kit mesh slots (Map.Plaza.HallOfFame): lanterns round the rim between the boards,
-- benches facing the boards and flower planters along both sides of the path. `HALL_DECOR` rows: mesh, plaza-local
-- x / y (WorldLayout.hallPoint), scale and what the kit front faces ("centre" of the plaza or "path").
export type HallDecor = { mesh: string, x: number, y: number, scale: number, face: string }
WorldLayout.HALL_DECOR = table.freeze((function(): { HallDecor }
	local hall = WorldLayout.HALL_OF_FAME
	local rows: { HallDecor } = {}
	local rim = hall.radius - 1.5
	for _, deg in { -145, -120, -71, -24, 24, 71, 120, 145 } do
		local a = math.rad(deg)
		table.insert(
			rows,
			{ mesh = "ranch_lantern_post", x = math.sin(a) * rim, y = math.cos(a) * rim, scale = 1, face = "centre" }
		)
	end
	for _, deg in { -150, -128, 128, 150 } do
		local a = math.rad(deg)
		table.insert(
			rows,
			{ mesh = "ranch_bench", x = math.sin(a) * 34, y = math.cos(a) * 34, scale = 1.2, face = "centre" }
		)
	end
	local side = hall.pathWidth / 2 + 4
	for _, y in { -62, -84, -106 } do
		for _, x in { -side, side } do
			table.insert(rows, { mesh = "ranch_flower_planter", x = x, y = y, scale = 1.2, face = "path" })
		end
	end
	return rows
end)())

local function hallDecor(): WorldNode
	local children: { WorldNode } = {}
	local centre = WorldLayout.hallPoint(0, 0)
	for i, row in WorldLayout.HALL_DECOR do
		local mesh = row.mesh
		local size = meshSize(mesh, row.scale)
		local pos = WorldLayout.hallPoint(row.x, row.y)
		local target = if row.face == "path" then WorldLayout.hallPoint(0, row.y) else centre
		local yaw = math.deg(math.atan2(target[1] - pos[1], target[3] - pos[3])) % 360 -- kit front (+Z) at the target
		local slot = block(`Hall_{mesh}_{i}`, size, { pos[1], size[2] / 2, pos[3] }, STONE, "Slate", { 0, yaw, 0 })
		if MeshAssets.collision(mesh) == nil then
			slot.canCollide = false
		end
		table.insert(children, meshSlot(slot, mesh))
	end
	return { name = "HallOfFame", class = "Folder", children = children }
end

local function plaza(): WorldNode
	local children: { WorldNode } = { hallDecor() }
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
			hall = WorldLayout.hallFloor(),
			obbyPath = WorldLayout.obbyPath(),
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
-- floors fill the ring; floor 1's pads spread evenly over FLOOR1_PAD_ARC (degrees from the door), so the front either
-- side of the door stays free for the vat and the lock button.
function WorldLayout.padAngle(j: number): number
	local n = Config.PADS_PER_FLOOR
	local k = (j - 1) % n
	local gap = 360 / n / 2
	if WorldLayout.padFloor(j) > 1 then
		return WorldLayout.DOOR.angle + gap + k * 2 * gap
	end
	local arc = WorldLayout.FLOOR1_PAD_ARC
	return WorldLayout.DOOR.angle + arc[1] + k * (arc[2] - arc[1]) / (n - 1)
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
	local turn = 360 -- one full turn per floor: the next stair goes on from where this one arrives
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

-- The door bridge's look: flat cross planks in cork and light wood with a gap (the Bridge's own top shows through)
-- and a darker rail down each long edge, like the boardwalk spokes (kit ranch_floor_paths). Decor on top of the
-- Bridge collider; PlotDecor tints it with the plot skin's trim like the Bridge.
WorldLayout.BRIDGE_LOOK = table.freeze({
	pitch = 1.8, -- studs per plank along the bridge, gap included
	gap = 0.2,
	rail = 0.8, -- rail width
	plankRise = 0.08, -- plank top above the Bridge top
	railRise = 0.12,
	colors = table.freeze({ { 214, 170, 116 }, { 196, 138, 86 } }), -- cork, light wood (kit ranch_wood)
	shades = table.freeze({ 1, 0.97, 1.03, 0.98, 1.02 }),
	railColor = { 112, 72, 42 }, -- the boardwalk's and the gate ramp's rails (kit TRIM_DARK)
})
function WorldLayout.bridgeLook(bridge: WorldNode): WorldNode
	local look = WorldLayout.BRIDGE_LOOK
	local size, pos = bridge.size :: Vec, bridge.pos :: Vec
	local yaw = ((bridge.rot or { 0, 0, 0 }) :: Vec)[2]
	local a = math.rad(yaw)
	local function place(x: number, z: number): (number, number)
		-- bridge-local (x across, z along) to world, turned like the Bridge (CFrame.Angles(0, a, 0))
		return pos[1] + x * math.cos(a) + z * math.sin(a), pos[3] - x * math.sin(a) + z * math.cos(a)
	end
	local top = pos[2] + size[2] / 2
	local children: { WorldNode } = {}
	local count = math.max(1, math.floor(size[3] / look.pitch + 0.5))
	local pitch = size[3] / count
	for k = 1, count do
		local z = -size[3] / 2 + pitch * (k - 0.5)
		local base = look.colors[k % 2 + 1]
		local shade = look.shades[k % #look.shades + 1]
		local color = {}
		for c = 1, 3 do
			color[c] = math.clamp(math.floor(base[c] * shade + 0.5), 0, 255)
		end
		local x, wz = place(0, z)
		local thick = 0.1
		table.insert(
			children,
			ghost(
				block(
					`Plank_{k}`,
					{ size[1] - 2 * look.rail, thick, pitch - look.gap },
					{ x, top + look.plankRise - thick / 2, wz },
					color,
					"SmoothPlastic",
					{ 0, yaw, 0 }
				)
			)
		)
	end
	for side, sx in { -1, 1 } do
		local x, wz = place(sx * (size[1] / 2 - look.rail / 2), 0)
		local thick = 0.16
		table.insert(
			children,
			ghost(
				block(
					`Rail_{side}`,
					{ look.rail, thick, size[3] },
					{ x, top + look.railRise - thick / 2, wz },
					look.railColor,
					"SmoothPlastic",
					{ 0, yaw, 0 }
				)
			)
		)
	end
	return { name = "BridgeLook", class = "Model", children = children }
end

-- The doorway through jar 1's glass (plot-local, door at -Z). The stopper's collider (LockBarrier.Stopper) fills it
-- from DOOR_OUTER_PAD outside the glass to DOOR_INNER_INSET in from the glass.
WorldLayout.DOOR_OUTER_PAD = 0.5
WorldLayout.DOOR_INNER_INSET = 2 -- the stopper reaches this far inside the glass
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

export type DoorSwing = {
	shut: Vec, -- the goo_jar_stopper mesh's anchor (bottom of its inner face) with the door shut in the doorway
	open: Vec, -- the same anchor with the door swung DOOR_SWING.angle out of the jar round its hinge pin
	-- The open door's collider: a Roblox cylinder (its axis along the part's X) of `diameter` and `thickness` at
	-- `centre`, turned `yaw` degrees (plot-local) so its axis is the swung door's normal.
	collider: { centre: Vec, yaw: number, diameter: number, thickness: number },
}

-- Jar 1's round door, shut and swung open round its hinge pin (plot-local).
function WorldLayout.doorSwing(): DoorSwing
	local plate, swing = WorldLayout.DOOR_DISC, WorldLayout.DOOR_SWING
	local doorY = WorldLayout.floorTop(1) + WorldLayout.DOOR.height / 2 + 0.1 - plate.radius
	local doorZ = WorldLayout.doorway().zOuter + 0.9
	local hx, hz = swing.hinge[1], doorZ + swing.hinge[2]
	local t = math.rad(swing.angle)
	-- turned round the pin: plot-local (dx, dz) from the pin goes to (dx cos t + dz sin t, -dx sin t + dz cos t)
	local function turn(dx: number, dz: number): (number, number)
		return hx + dx * math.cos(t) + dz * math.sin(t), hz - dx * math.sin(t) + dz * math.cos(t)
	end
	local ox, oz = turn(-hx, doorZ - hz)
	-- the collider: the door's disc trimmed at its hinge edge (hingeClear off the pin), centred on the door's middle
	local far = -hx + plate.radius -- the door's far edge, out from the pin
	local diameter = far - plate.hingeClear
	local cx, cz = turn(plate.hingeClear + diameter / 2, 0)
	return {
		shut = { 0, doorY, doorZ },
		open = { ox, doorY, oz },
		collider = {
			centre = { cx, doorY + plate.radius, cz },
			yaw = swing.angle - 90,
			diameter = diameter,
			thickness = plate.thickness,
		},
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
WorldLayout.JAR_GLASS_MESH_TRANSPARENCY = 0.8
-- The glass meshes wear SmoothPlastic, not Glass: Roblox draws nothing partly see-through behind a Glass part, so a
-- faded slime (an "In vat" pad copy, a steal ghost, a Move ghost) and the signs inside a jar vanished from outside it.
WorldLayout.JAR_GLASS_MATERIAL = "SmoothPlastic"
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
	return block(name, size, at({ x, y, z }), JAR_GLASS, WorldLayout.JAR_GLASS_MATERIAL, { 0, yaw + 90 - deg, 0 })
end

-- Attribute-driven plot cosmetics (PlotDecor; VisualsClient shows / hides them locally): the stopper lock and the
-- lock sign. Shipped in their neutral state: free plot, unlocked. Rebirths never change the base.
local function cosmetics(at: (Vec) -> Vec, yaw: number): { WorldNode }
	local r = { 0, yaw, 0 }
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

	-- The sign's cradle by the bridge: a rail the nameplate (Sign) sits in, gripping its bottom edge, on two short
	-- stubs from the ground, one under each end. All in the sign's own plane, so neither face is covered.
	local sx, sz = WorldLayout.signCentre()
	local board, legs, rail = WorldLayout.NAME_BOARD, WorldLayout.SIGN_LEGS, WorldLayout.SIGN_RAIL
	local railTop = board.y - board.height / 2 + rail.grip
	local legH = railTop - rail.height - 1 -- from the ground (y 1) up to the rail
	table.insert(
		nodes,
		ghost(
			block(
				"SignRail",
				{ rail.width, rail.height, rail.depth },
				at({ sx, railTop - rail.height / 2, sz }),
				FENCE,
				"Wood",
				r
			)
		)
	)
	for i, side in { -1, 1 } do
		local lx = sx + side * (board.width / 2 - legs.inset)
		table.insert(
			nodes,
			ghost(
				block(`SignLeg_{i}`, { legs.width, legH, legs.depth }, at({ lx, 1 + legH / 2, sz }), FENCE, "Wood", r)
			)
		)
	end

	return nodes
end

-- Pad_<j> on its floor: the Pad stays the gameplay part (prompt, slimes rest on its top, raycasts) from the floor up
-- to the stand's seat, but it doesn't collide. The stand mesh sits on the floor at native size and is what players
-- walk into and stand on (a Hull, MeshAssets.COLLISION) and ground rays land on (MeshCanQuery), so the stand collides
-- as round as it looks; until it lands its Stand slot box does both instead and the Pad shows.
-- Pad j at plot-local (x, z) on its floor, its box turned padYaw degrees (BaseShapes builds the other bases' pads).
local function padNodeAt(
	j: number,
	x: number,
	z: number,
	padYaw: number,
	at: (Vec) -> Vec,
	yaw: number,
	color: Vec
): WorldNode
	local y = WorldLayout.floorTop(WorldLayout.padFloor(j))
	local turn = { 0, yaw + padYaw, 0 }
	local look = WorldLayout.PAD_MESH
	local seat = WorldLayout.PAD_SEAT_Y
	local ps = WorldLayout.PAD_SIZE
	local pad = block(`Pad_{j}`, { ps, seat, ps }, at({ x, y + seat / 2, z }), color, "SmoothPlastic", turn)
	pad.attributes = { PadIndex = j }
	pad.canCollide = false
	standIn(pad, look)
	local size = meshSize(look, 1)
	local stand = meshSlot(block("Stand", size, at({ x, y + size[2] / 2, z }), color, nil, turn), look, true)
	stand.canCollide = true
	stand.canQuery = true -- ground rays land dropped slimes on it (then on the mesh: MeshCanQuery)
	local attributes = stand.attributes :: { [string]: any } -- meshSlot set MeshAsset
	attributes.MeshCanQuery = true
	pad.children = { stand }
	return pad
end
WorldLayout.padNodeAt = padNodeAt

local function padNode(j: number, at: (Vec) -> Vec, yaw: number, color: Vec): WorldNode
	local x, z = WorldLayout.padOffset(j)
	return padNodeAt(j, x, z, WorldLayout.padYaw(j), at, yaw, color)
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

-- Jar f's glass wall collision: JAR_WALL_SEGMENTS collidable segments round the glass (the glass mesh is the look; they
-- show as glass until it lands), up to the top jar's glass height (jarWall) and from there up to the next deck once a
-- jar stands on it (jarUpperWalls). Jar 1's segment at DOOR.angle is the door: two jambs either side of the opening
-- and the lintel over it. Glass never blocks prompts or raycasts.
-- Height above floor f of jar f's straight glass while it is the top jar (the kit's wall_top): its dome starts here.
-- Jar 1's clears its door.
function WorldLayout.jarTopWallHeight(f: number): number
	local wall = 0.2 + WorldLayout.JAR_SHAPE.topWall
	if f == 1 then
		wall = math.max(wall, WorldLayout.DOOR.height + 0.3)
	end
	return wall
end

-- Jar f's wall colliders, from `from` to `to` studs above floor f (`suffix` on the names): the segments round the
-- glass, and on jar 1 the door's lintel and jambs where they reach.
local function wallBand(
	f: number,
	from: number,
	to: number,
	suffix: string,
	at: (Vec) -> Vec,
	yaw: number
): { WorldNode }
	local out = {}
	local n = WorldLayout.JAR_WALL_SEGMENTS
	local r = WorldLayout.jarWallRadius(f)
	local width = 2 * (r + WorldLayout.JAR_WALL / 2) * math.tan(math.pi / n) + 0.3
	local base = WorldLayout.floorTop(f)
	local t = WorldLayout.JAR_WALL
	for k = 1, n do
		local deg = WorldLayout.DOOR.angle + (k - 1) * 360 / n
		local nodes = {}
		if f == 1 and k == 1 then
			local dh, dw = WorldLayout.DOOR.height, WorldLayout.DOOR.width
			local jw = (width - dw) / 2
			local x, z = polar(r, deg)
			local tx, tz = -math.sin(math.rad(deg)), math.cos(math.rad(deg))
			local turn = { 0, yaw + 90 - deg, 0 }
			local off = dw / 2 + jw / 2
			local lo = math.max(from, dh)
			if to > lo then
				table.insert(
					nodes,
					radial(`DoorLintel{suffix}`, { width, to - lo, t }, r, deg, base + lo + (to - lo) / 2, at, yaw)
				)
			end
			local top = math.min(to, dh)
			if top > from then
				local h = top - from
				local y = base + from + h / 2
				table.insert(
					nodes,
					block(
						`DoorJambL{suffix}`,
						{ jw, h, t },
						at({ x - tx * off, y, z - tz * off }),
						JAR_GLASS,
						WorldLayout.JAR_GLASS_MATERIAL,
						turn
					)
				)
				table.insert(
					nodes,
					block(
						`DoorJambR{suffix}`,
						{ jw, h, t },
						at({ x + tx * off, y, z + tz * off }),
						JAR_GLASS,
						WorldLayout.JAR_GLASS_MATERIAL,
						turn
					)
				)
			end
		else
			nodes =
				{ radial(`Wall{suffix}_{k}`, { width, to - from, t }, r, deg, base + from + (to - from) / 2, at, yaw) }
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

-- Jar f's walls above the top jar's glass height, up to the deck of jar f + 1: they only stand while a jar sits on
-- jar f, so they are built with that jar (WorldLayout.floor), and a top jar's dome has no invisible fence round it.
local function jarUpperWalls(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	return wallBand(f, WorldLayout.jarTopWallHeight(f) + 0.5, WorldLayout.FLOOR_HEIGHT - 1, "Upper", at, yaw)
end

local function jarWall(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	-- up to the top jar's glass height, a little into its dome colliders (WorldLayout.topColliders)
	return wallBand(f, 0, WorldLayout.jarTopWallHeight(f) + 0.5, "", at, yaw)
end

-- Floor f's deck (f >= 2): DECK_SEGMENTS boxes making a ring from the stair hole out over jar f - 1's glass, so it is
-- also that jar's lid. Its top is floor f's walking surface. The boxes reach in to the polygon inscribed in the hole,
-- so the round hole edge has no gap between two boxes.
local function jarDeck(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	local out = {}
	local n = WorldLayout.DECK_SEGMENTS
	local inner = WorldLayout.STAIR.hole * math.cos(math.pi / n)
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

-- The spiral stair from floor f up to floor f + 1: the centre post, the sloped ramp boxes (the next floor's ramp
-- goes on from the top, at the same angle) and the rail along the outer edge (WorldLayout.RAMP). Plot-local yaw: a box's local X runs along the ring towards lower
-- angles, so a negative Z tilt makes it climb as the angle grows.
local function jarStair(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	local st = WorldLayout.STAIR
	local base = WorldLayout.floorTop(f)
	local h = WorldLayout.FLOOR_HEIGHT
	local ramp = WorldLayout.RAMP
	local out = { disc("StairPost", h, st.post * 2, at({ 0, base + h / 2, 0 }), JAR_GOO, "SmoothPlastic", yaw) }
	local mid = (st.post + st.outer) / 2
	local width = st.outer - st.post + 0.4
	local start = WorldLayout.treadAngle(f, 1) - st.angle
	local span = st.angle * WorldLayout.stairSteps()
	local n = ramp.segments
	local seg, rise = span / n, h / n
	local slope = math.atan(rise / (math.rad(seg) * ramp.walk))
	-- long enough to cover the outer edge's chord along the slope, overlapping the next box a little
	local length = 2 * st.outer * math.sin(math.rad(seg) / 2) / math.cos(slope) + 0.3
	local function sloped(name: string, size: Vec, r: number, deg: number, y: number): WorldNode
		local node = radial(name, size, r, deg, y, at, yaw)
		local rot = node.rot :: Vec
		node.rot = { rot[1], rot[2], -math.deg(slope) }
		return node
	end
	for i = 1, n do
		-- the top face's middle sits on the helix: centre half a box lower, along the box's own up
		local deg = start + (i - 0.5) * seg
		local node = sloped(`Ramp_{i}`, { length, 1, width }, mid, deg, base + (i - 0.5) * rise - 0.5 / math.cos(slope))
		node.color = JAR_CORK
		node.material = "Wood"
		table.insert(out, node)
	end
	-- the rail: upright wall pieces two ramp boxes wide along the outer edge, from railStart to railEnd degrees before
	-- the top, each from just under the ramp at its low end to railHeight above it at its high end
	local railR = st.outer + 0.15
	local pair = 2 * seg
	local railLength = 2 * (railR + 0.15) * math.sin(math.rad(pair) / 2) + 0.2
	local function surface(d: number): number
		return (d - start) / span * h
	end
	local k = 0
	local deg = start + ramp.railStart + pair / 2
	while deg + pair / 2 <= start + span - ramp.railEnd + 1e-6 do
		k += 1
		local bottom = math.max(0, surface(deg - pair / 2) - 1.5)
		local top = math.min(surface(deg + pair / 2) + ramp.railHeight, h - 1)
		local railHeight = top - bottom
		local rail =
			radial(`RampRail_{k}`, { railLength, railHeight, 0.3 }, railR, deg, base + bottom + railHeight / 2, at, yaw)
		rail.transparency = 1
		rail.canQuery = false
		rail.canTouch = false
		table.insert(out, rail)
		deg += pair
	end
	return out
end

-- Jar f's lid: the roof while jar f is the top jar (server/BaseFloors hides it while jar f + 1 stands).
local function jarLid(f: number, at: (Vec) -> Vec, yaw: number): WorldNode
	local r = WorldLayout.jarRadius(f) + WorldLayout.JAR_WALL
	local lid = disc("Lid", 1, r * 2, at({ 0, WorldLayout.floorTop(f + 1) - 0.5, 0 }), JAR_CORK, "Wood", yaw)
	lid.attributes = { JarLid = f }
	lid.transparency = 1 -- the roof's look is the jar trim mesh (cork lid or stopper)
	lid.canCollide = false -- the top jar's roof is its dome colliders (WorldLayout.topColliders), shaped like the glass
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

-- Glass slots: the mesh wears JAR_GLASS_MATERIAL at the mesh glass transparency (or `clear`) and casts no shadow, so
-- the jars and the tube stay light inside (server/MeshSwap reads these).
local function glassy(node: WorldNode, clear: number?): WorldNode
	local a = node.attributes or {}
	a.MeshMaterial = WorldLayout.JAR_GLASS_MATERIAL
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

-- The top of the stair that arrives on floor f (WorldLayout.STAIR_TOP): the flat landing's and the post stub's
-- (WorldLayout.STAIR_NEWEL) colliders, shown and solid only while jar f is the top jar (JarCollide: server/BaseFloors
-- turns them off once a jar stands on it, because the next stair goes on from here). Their look is the top jar's trim
-- mesh.
local function stairTop(f: number, at: (Vec) -> Vec, yaw: number): { WorldNode }
	local st, top = WorldLayout.STAIR, WorldLayout.STAIR_TOP
	local deck = WorldLayout.floorTop(f)
	local start = WorldLayout.treadAngle(f - 1, 1) - st.angle
	local out = {}
	local function add(node: WorldNode)
		node.transparency = 1
		node.canTouch = false
		local a = node.attributes or {}
		a.JarCollide = true
		node.attributes = a
		table.insert(out, variant(node, f, "top"))
	end
	-- flat boxes from the post out to the hole's edge, on round from where the ramp arrives
	local step = top.step
	local width = st.hole - st.post
	for k = 1, top.landing // step do
		local deg = start + (k - 0.5) * step
		local chord = 2 * st.hole * math.sin(math.rad(step) / 2) + 0.3
		add(radial(`StairLanding_{k}`, { chord, 1, width }, (st.post + st.hole) / 2, deg, deck - 0.5, at, yaw))
	end
	-- the post's capped stub standing up from the deck
	local newel = WorldLayout.STAIR_NEWEL
	add(disc("StairNewel", newel.height, newel.radius * 2, at({ 0, deck + newel.height / 2, 0 }), JAR_GOO, nil, yaw))
	return out
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
		-- the stair mesh is built on floor 1's treads (today every floor's stair starts at the same angle)
		local turn = -(WorldLayout.treadAngle(f - 1, 1) - WorldLayout.treadAngle(1, 1))
		table.insert(out, noShadow(jarLook("StairLook", "goo_jar_stair", below, at, yaw, turn)))
		local ground = { 0, WorldLayout.floorTop(1) - 1, 0 }
		local tubeGlass = jarLook("TubeGlass", `goo_drop_tube_glass_{f}`, ground, at, yaw)
		table.insert(out, variant(glassy(tubeGlass, WorldLayout.DROP_TUBE_GLASS_TRANSPARENCY), f, "top"))
		table.insert(out, variant(jarLook("TubeGoo", `goo_drop_tube_goo_{f}`, ground, at, yaw), f, "top"))
	end
	return out
end

-- Plot-local middle (x, y, z) of the drop tube's splash pool: in the goo moat behind the tower, under the tube's foot.
function WorldLayout.dropPool(): Vec
	local x, z = polar((WorldLayout.MOAT.inner + WorldLayout.MOAT.outer) / 2, WorldLayout.DROP_ANGLE)
	return { x, WorldLayout.PLOT_FLOOR_TOP, z }
end

-- Plot-local landing point (x, y, z) of the drop tube: on the splash pool, DROP_TUBE.landSide along the moat from the
-- pool's middle, so the player lands beside the tube's solid foot instead of inside it.
function WorldLayout.dropLanding(): Vec
	local pool = WorldLayout.dropPool()
	local a = math.rad(WorldLayout.DROP_ANGLE)
	local side = WorldLayout.DROP_TUBE.landSide
	return { pool[1] - math.sin(a) * side, WorldLayout.PLOT_FLOOR_TOP + 3, pool[3] + math.cos(a) * side }
end

-- The plot-local angles of the glass segments either side of the drop hatch (the DropShield's segments).
function WorldLayout.dropShieldAngles(): { number }
	local step = 360 / WorldLayout.JAR_WALL_SEGMENTS
	local below = WorldLayout.DOOR.angle + math.floor((WorldLayout.DROP_ANGLE - WorldLayout.DOOR.angle) / step) * step
	return { below, below + step }
end

-- WorldLayout.TOP_DOME_ROWS tilted boxes per wall segment make the top jar's dome: they follow the kit's quarter
-- ellipse (glass_profile) from the top of the straight glass in to the neck, their outer face on the glass. Above the
-- neck the cork stopper (or the last jar's lid) is a cylinder and the mascot on it a ball. Like the fountain's profile
-- colliders, checked against the kit's numbers (tests/JarTower.spec).
WorldLayout.TOP_DOME_ROWS = 3

-- The dome profile of jar f as the top jar, (radius, height above floor f): row edges from the glass wall top to the
-- neck (WorldLayout.TOP_DOME_ROWS + 1 points).
function WorldLayout.topDomeProfile(f: number): { { number } }
	local sh = WorldLayout.JAR_SHAPE
	local r = WorldLayout.jarRadius(f)
	local nk = r * sh.topNeck
	local wt = WorldLayout.jarTopWallHeight(f)
	local out = {}
	for i = 0, WorldLayout.TOP_DOME_ROWS do
		local t = i / WorldLayout.TOP_DOME_ROWS * math.pi / 2
		table.insert(out, { nk + (r - nk) * math.cos(t), wt + sh.topDome * math.sin(t) })
	end
	return out
end

-- The roof of plot i's tower while jar f is its top jar: one TopColliders folder (TopFloor = f) of invisible solid
-- parts, the dome facets, the stopper and the mascot. server/BaseFloors keeps one per plot on its current top jar, so
-- the map holds a single roof per plot, not one per jar.
function WorldLayout.topColliders(i: number, f: number): WorldNode
	local centre, yaw = WorldLayout.plotCentre(i)
	local at = frame(centre, yaw)
	local out = {}
	local function add(node: WorldNode)
		node.transparency = 1
		node.canQuery = false
		node.canTouch = false
		table.insert(out, node)
	end
	local base = WorldLayout.floorTop(f)
	local n = WorldLayout.JAR_WALL_SEGMENTS
	local half = math.pi / n
	local profile = WorldLayout.topDomeProfile(f)
	for row = 1, #profile - 1 do
		local a, b = profile[row], profile[row + 1]
		local dr, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dr * dr + dz * dz)
		local nr, nz = dz / len, -dr / len -- outward (and up) normal of the glass
		local rc = (a[1] + b[1]) / 2 - nr * 0.5 -- the box centre: its outer face on the glass
		local yc = (a[2] + b[2]) / 2 - nz * 0.5
		local tilt = math.deg(math.atan2(-dr, dz)) -- from upright, leaning in towards the jar's axis
		local width = 2 * a[1] * math.tan(half) + 0.3
		for k = 1, n do
			local deg = WorldLayout.DOOR.angle + (k - 1) * 360 / n
			-- a flat facet between the inscribed and the round glass, like the wall polygon
			local node =
				radial(`Dome_{row}_{k}`, { width, len + 0.4, 1 }, rc * math.cos(half / 2), deg, base + yc, at, yaw)
			local rot = node.rot :: Vec
			node.rot = { -tilt, rot[2], rot[3] }
			add(node)
		end
	end
	-- the stopper (or the last jar's lid) from the neck up to the mascot's seat
	local sh = WorldLayout.JAR_SHAPE
	local last = f >= #Config.BASE_FLOORS
	local nk = WorldLayout.jarRadius(f) * sh.topNeck
	local neck = base + WorldLayout.jarTopWallHeight(f) + sh.topDome - 0.5
	local seat = base + jarNeckY(f) + (if last then sh.lid else sh.cork)
	add(
		disc(
			"Cork",
			seat - neck,
			2 * (nk + (if last then 0.4 else 0.7)),
			at({ 0, (neck + seat) / 2, 0 }),
			JAR_CORK,
			"Wood",
			yaw
		)
	)
	-- the mascot on the seat: a ball as tall as the mesh (goo_jar_mascot is 1.567 tall, centre 0.778 up, at size 1)
	local m = WorldLayout.MASCOT
	local size = m.base + m.grow * f
	local d = 1.567 * size
	local ball = { name = "Mascot", class = "Part", shape = "Ball", size = { d, d, d } } :: WorldNode
	ball.pos, ball.rot, ball.color, ball.material =
		at({ 0, seat + 0.778 * size, 0 }), { 0, yaw, 0 }, JAR_CORK, "Plastic"
	add(ball)
	return { name = "TopColliders", class = "Folder", attributes = { TopFloor = f }, children = out }
end

-- Upper jar f (2..#BASE_FLOORS) of plot i, as the nodes the server adds under Plot_<i>: a Floor_<f> Model (deck,
-- glass wall, jar f - 1's upper walls, the stair up from floor f - 1, the lid, the drop-tube hatch) and the jar's
-- Pad_<j>.
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
	-- jar f - 1's walls above its top-jar height stand while this jar does
	-- jar f - 1's walls above its top-jar height: their look is that jar's covered glass, so they hide once it loads
	local upper = jarUpperWalls(f - 1, at, yaw)
	standIns(upper, `goo_jar_glass_{f - 1}_mid`)
	for _, list in { deck, wall, upper, stair, stairTop(f, at, yaw), jarLooks(f, at, yaw) } do
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
	-- The DropShield: invisible, never collides, but queryable, just outside the glass segments either side of the
	-- hatch, so the DropPrompt's line of sight is blocked from outside the jar (glass never blocks prompts) and only
	-- a player inside sees "Drop down". It covers the ledge round the glass on this floor's deck within the prompt's
	-- reach.
	for k, deg in WorldLayout.dropShieldAngles() do
		local n = WorldLayout.JAR_WALL_SEGMENTS
		local r = WorldLayout.jarWallRadius(f) + WorldLayout.JAR_WALL
		local width = 2 * r * math.tan(math.pi / n) + 0.3
		local h = WorldLayout.FLOOR_HEIGHT - 1
		local shield = radial(`DropShield_{k}`, { width, h, 0.2 }, r, deg, WorldLayout.floorTop(f) + h / 2, at, yaw)
		shield.canCollide = false
		shield.canTouch = false
		shield.transparency = 1
		table.insert(children, shield)
	end
	-- The goo tube: an arm from the hatch out through the glass, and this floor's length of the upright tube down to the
	-- next arm below (floor 2's reaches the ground and its splash pool). The arm is decor (out of reach); the upright is
	-- solid so nobody stands inside the tube, and smooth and straight up so nobody climbs it.
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
		WorldLayout.JAR_GLASS_MATERIAL,
		yaw
	)
	for _, node in { arm, pipe } do
		node.color, node.material, node.transparency =
			JAR_GOO, WorldLayout.JAR_GLASS_MATERIAL, WorldLayout.JAR_GLASS_TRANSPARENCY
		table.insert(children, standIn(ghost(node, WorldLayout.JAR_GLASS_TRANSPARENCY), `goo_drop_tube_goo_{f}`))
	end
	pipe.canCollide = true
	if f == 2 then
		local land = WorldLayout.dropPool()
		table.insert(
			children,
			ghost(
				disc(
					"SplashPool",
					0.2,
					6,
					at({ land[1], WorldLayout.PLOT_FLOOR_TOP + 0.1, land[3] }),
					JAR_GOO,
					WorldLayout.JAR_GLASS_MATERIAL,
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
		-- the plot's anchor (PrimaryPart, every plot-local frame): invisible and never collides; the round floor is
		-- PlotFloor (collider) under the goo_jar_foot mesh
		ghost(block("Base", { s, 1, s }, at({ 0, 0.5, 0 }), { 232, 214, 178 }, "Sand", r), 1),
	}
	local floor =
		disc("PlotFloor", 1, WorldLayout.PLOT_FLOOR_RADIUS * 2, at({ 0, 0.5, 0 }), { 232, 214, 178 }, "Sand", yaw)
	standIn(floor, "goo_jar_foot") -- the foot mesh is the whole round floor's look
	table.insert(children, floor)
	for j = 1, Config.PADS_PER_FLOOR do
		table.insert(children, padNode(j, at, yaw, color))
	end

	local zone = block("HomeZone", { s, 14, s }, at({ 0, 8, 0 }), color, "SmoothPlastic", r)
	zone.transparency = 1
	zone.canCollide = false
	zone.canQuery = false
	-- The zone check reaches up over every upper floor and is the round plot floor, not the square (CONTRACT.md §5.3):
	-- the corners outside the jar, by the Hall of Fame path, are no one's home.
	zone.attributes = {
		ReachUp = (#Config.BASE_FLOORS - 1) * WorldLayout.FLOOR_HEIGHT,
		Radius = WorldLayout.PLOT_FLOOR_RADIUS,
	}
	table.insert(children, zone)

	-- Jar 1 (the static part of the tower): the goo moat and the cork floor inside it (decor on the Base, which stays
	-- the walking surface), the bridge to the door, the glass wall with the door, and the lid.
	local moat = WorldLayout.MOAT
	local moatDisc =
		ghost(disc("Moat", 0.2, moat.outer * 2, at({ 0, 1, 0 }), JAR_GOO, WorldLayout.JAR_GLASS_MATERIAL, yaw))
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
		"SmoothPlastic",
		r
	)
	bridge.canQuery = false
	table.insert(children, bridge)
	table.insert(children, WorldLayout.bridgeLook(bridge))
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
	local door = WorldLayout.doorSwing()
	table.insert(children, jarLook("StopperShut", "goo_jar_stopper", door.shut, at, yaw))
	-- open: the same door swung out of the jar round its hinge pin (DOOR_SWING)
	table.insert(
		children,
		jarLook("StopperParked", "goo_jar_stopper", door.open, at, yaw, WorldLayout.DOOR_SWING.angle)
	)
	-- The open door's collider: solid while the plot is open (the server turns it off while locked, when the door is
	-- shut), for everyone, the owner too; never queried, so it blocks no prompt or raycast.
	local c = door.collider
	local collider = block(
		"OpenDoorCollider",
		{ c.thickness, c.diameter, c.diameter },
		at(c.centre),
		JAR_CORK,
		"Wood",
		{ 0, yaw + c.yaw, 0 }
	)
	collider.shape = "Cylinder"
	collider.transparency = 1
	collider.canQuery = false
	collider.canTouch = false
	table.insert(children, collider)

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

	-- Sign = the plot's sign in its cradle by the bridge (PlotSigns draws on both faces; Front looks out of the plot).
	local board = WorldLayout.NAME_BOARD
	local sx, sz = WorldLayout.signCentre()
	local sign = block("Sign", { board.width, board.height, 0.3 }, at({ sx, board.y, sz }), SIGN, "WoodPlanks", r)
	sign.canQuery = false
	sign.transparency = 1 -- only the sign PlotSigns draws shows: no square board behind the mascot and nameplate
	table.insert(children, sign)

	for _, node in cosmetics(at, yaw) do
		table.insert(children, node)
	end

	table.insert(children, { name = WorldLayout.SLIMES_FOLDER, class = "Folder" })

	return {
		name = `Plot_{i}`,
		class = "Model",
		primaryPart = "Base",
		attributes = { PlotIndex = i, OwnerUserId = 0, LockUntil = 0 },
		children = children,
	}
end

-- Plot i's own nodes (WorldLayout.build's Plot_<i>), its plot-local frame (at, yaw) and its colour: BaseShapes builds
-- the other bases on the same frame.
WorldLayout.plotNode = plot
function WorldLayout.plotFrame(i: number): ((Vec) -> Vec, number)
	local centre, yaw = WorldLayout.plotCentre(i)
	return frame(centre, yaw), yaw
end
function WorldLayout.plotColor(i: number): Vec
	return PLOT_COLORS[(i - 1) % #PLOT_COLORS + 1]
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
