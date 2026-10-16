--!strict
--[[
	WorldLayout (owner: Archer)

	WorldLayout.build(): { WorldNode }

	Pure description of the world in CONTRACT.md §5.3, as a tree of nodes
	(Folder / Model / Part / PointLight) in world space. WorldBuilder turns it into
	Instances under workspace; the render proof draws it under Lune.

	  Map      Ground (640x640 baseplate), Volcano = the Slime Ranch fountain
	           (kit slime_fountain; contract name kept, Crater = the goo pool
	           on top = the drop origin), Chute (primitive slide, hidden once
	           the fountain mesh loads), Paths (plaza, spokes + ring), Plaza
	           (signpost, podiums, landing-ring tiles, goo drain), Decor
	           (rocks, mushrooms, the RanchProps kit props), Border
	           (WorldBorder: the invisible wall ring + seeded hedges, fences,
	           pines, hills, rocks along the edge). Kit meshes go on MeshAsset
	           slots via server/MeshSwap.
	  Plots    Plot_1..PLOT_COUNT in a ring around the fountain, each facing
	           it (entrance at local -Z): Base, Pad_1..PADS_MAX, HomeZone,
	           MergeVat, LockButton, Sign, walls (invisible colliders) +
	           Fence (ranch_fence_20 + phoenix_fence_segment slots), Slimes
	           folder, and the
	           PlotDecor cosmetics (LockBarrier, LockSign, BuyStand,
	           RebirthDecor, DexBoard)
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
local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local Meadow = if script then require(script.Parent.Meadow) else require("./Meadow")
local PlotDecor = if script then require(script.Parent.PlotDecor) else require("./PlotDecor")
local RanchProps = if script then require(script.Parent.RanchProps) else require("./RanchProps")
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
})
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
WorldLayout.GATE_SLOT = 20 -- fence gap at the entrance
WorldLayout.GATE_CLEAR = 14 -- walkable opening inside the slot
WorldLayout.WALL_HEIGHT = 8
-- Plot fence look: kit ranch_fence_20 panels on a 20-stud grid, 4 per side.
-- The gate side is 30 + 20 (GATE_SLOT) + 30, so it takes a panel at each
-- corner and a 10-stud phoenix_fence_segment beside each gate post: 14
-- panels + 2 segments per plot. Both kit pieces are 11 native studs per 10
-- grid studs with one post, at their -X end (the neighbour's post closes the
-- +X end), so one uniform scale of 10/11 tiles them on the grid at the same
-- 8.2 height. Until ranch_fence_20
-- is uploaded each panel slot is a Model tagged FenceMesh = FENCE_MESH holding
-- two FENCE_SEGMENT halves (the same look: the panel is two segments sharing
-- the mid post).
WorldLayout.FENCE_MESH = "ranch_fence_20"
WorldLayout.FENCE_SEGMENT = "phoenix_fence_segment"
-- Closes the fence run that ends at the gate's right stub (GatePost slot).
WorldLayout.GATE_POST_MESH = "phoenix_corner_post"
WorldLayout.FENCE_GRID = 20
WorldLayout.FENCE_SEGMENT_GRID = 10
WorldLayout.FENCE_SCALE = 10 / 11
-- Post centre in from a piece's -X end: the kit post cap is 1.8 wide, and
-- its centre 0.9 in from the bbox edge, at FENCE_SCALE.
WorldLayout.FENCE_POST_INSET = 0.9 * WorldLayout.FENCE_SCALE
-- Mesh slots in the whole world, as the pc-watcher counts MeshParts (MeshAsset + pending BorderMesh / FenceMesh
-- slots + the WorldProps skins), counted with ranch_fence_20 uploaded
-- (tests/WorldBudget.spec), split into caps that add up to MESH_SLOT_BUDGET:
--   fence   panels + gate segments. The target was 15 a plot (120), but the
--           kit pieces are 20 and 10 long: each closed side needs 4 panels
--           (80 / 20) and each 30-stud half of the gate side needs a panel
--           and a segment, so 16 a plot (128) is the minimum with the gate
--           slot centred.
--   posts   one GATE_POST_MESH a plot (8). Panels and segments carry a post
--           at their -X end only, so round the fence loop every joint and
--           corner shows one post; the run that ends at the gate has none
--           there, and this post closes it, mirroring the post beside the
--           other gate stub. Paid for by the border share (112 -> 104).
--   border  Map.Border's share (88). The ring uses BORDER_SLOT_COUNT (80)
--           since border v3 (single hedge, fence, tree, rock and hill
--           pieces scattered in layers; 102 slots / 12 designs more until
--           the pc-watcher perf gate read 414 > 400); #56's chunk ring
--           used 44, main #54's first ring 228.
--   runtime MeshParts the pc-watcher counts in the play world that
--           WorldLayout.build() does not produce: 16, the constant gap
--           between the build count and the watcher's (340 vs 356 at
--           09ea65e, 398 vs 414 at b84f795). RUNTIME_SLOT_ALLOWANCE.
--   decor   everything else: ranch props, pad stands, fountain, plaza,
--           landing ring, gates, plot dex boards, WorldProps
--           skins. Capped at 160 = MESH_SLOT_BUDGET - fence - posts - border
--           share (the plots no longer carry a BuyStand: 8 slots free;
--           the shop skin is the one ranch_shop_stand).
-- The fallback (two segments per panel until the upload) adds one slot per
-- panel: 112.
WorldLayout.MESH_SLOT_BUDGET = 400
WorldLayout.FENCE_SLOT_BUDGET = 128
WorldLayout.GATE_POST_SLOT_BUDGET = 8
WorldLayout.BORDER_SLOT_BUDGET = 88
WorldLayout.BORDER_SLOT_COUNT = 80
WorldLayout.DECOR_SLOT_BUDGET = 160
WorldLayout.RUNTIME_SLOT_ALLOWANCE = 16
WorldLayout.MESH_SLOT_BUDGET_FALLBACK = WorldLayout.MESH_SLOT_BUDGET + 112
-- Parts outside Map.Border (THEME.md asked <= 1200; raised to 1400 for the
-- primitive meadow clusters in the grass band behind the plots). Asserted
-- over the world WorldLayout builds outside Map.Border; the border ring
-- (main #54) is held to its own budget, since its pieces still carry an
-- invisible slot plus primitive stand-ins each.
WorldLayout.PART_BUDGET = 1400
WorldLayout.BORDER_PART_BUDGET = 700

export type FenceSegment = {
	name: string,
	side: string,
	x: number,
	z: number,
	yaw: number,
	length: number, -- FENCE_GRID (a ranch_fence_20 panel) or FENCE_SEGMENT_GRID
}

-- Whether the 20-stud panel mesh is uploaded (read at build time).
function WorldLayout.fenceUploaded(): boolean
	return MeshAssets.meshId(WorldLayout.FENCE_MESH) ~= nil
end

-- Plot-local fence pieces (centre on the wall line, yaw relative to the
-- plot, kit front facing out). The front leaves the gate slot open.
function WorldLayout.fenceSegments(): { FenceSegment }
	local s, g, h = WorldLayout.PLOT_SIZE, WorldLayout.FENCE_GRID, WorldLayout.FENCE_SEGMENT_GRID
	local line = s / 2 - 0.5
	local slot = WorldLayout.GATE_SLOT / 2
	-- Gate side: panels in from each corner, then segments up to the slot.
	local front: { { number } } = {}
	for _, dir in { -1, 1 } do
		local t = s / 2
		while t - g >= slot do
			table.insert(front, { dir * (t - g / 2), g })
			t -= g
		end
		while t - h >= slot do
			table.insert(front, { dir * (t - h / 2), h })
			t -= h
		end
	end
	table.sort(front, function(a, b)
		return a[1] < b[1]
	end)
	local full: { { number } } = {}
	for k = 0, s // g - 1 do
		table.insert(full, { -s / 2 + g / 2 + k * g, g })
	end
	local out: { FenceSegment } = {}
	for _, side in
		{
			{
				"Back",
				0,
				function(t: number): (number, number)
					return t, line
				end,
			},
			{
				"Left",
				270,
				function(t: number): (number, number)
					return -line, t
				end,
			},
			{
				"Right",
				90,
				function(t: number): (number, number)
					return line, t
				end,
			},
			{
				"Front",
				180,
				function(t: number): (number, number)
					return t, -line
				end,
			},
		}
	do
		for n, piece in (if side[1] == "Front" then front else full) do
			local x, z = (side[3] :: any)(piece[1])
			table.insert(out, {
				name = `Segment{side[1]}_{n}`,
				side = side[1] :: string,
				x = x,
				z = z,
				yaw = side[2] :: number,
				length = piece[2],
			})
		end
	end
	return out
end
-- Pad stand looks (Phoenix kit), cycled per pad.
WorldLayout.PAD_MESHES = table.freeze({
	"phoenix_pad_crate",
	"phoenix_pad_hay",
	"phoenix_pad_goo",
	"phoenix_pad_stool",
	"phoenix_pad_barrel_top",
	"phoenix_pad_flower_bed",
	"phoenix_pad_mushroom",
})
-- Where a slime sits on each stand at native size (kit model headers): the Pad
-- top goes here, so slimes rest on the mesh instead of sinking into it.
WorldLayout.PAD_SEAT = table.freeze({
	phoenix_pad_crate = 2.4,
	phoenix_pad_hay = 1.0,
	phoenix_pad_goo = 1.5,
	phoenix_pad_stool = 3.0,
	phoenix_pad_barrel_top = 2.4, -- goo fill inside the sawn rim
	phoenix_pad_flower_bed = 2.4, -- stump top
	phoenix_pad_mushroom = 3.0, -- flat mesa top of the cap
})
-- phoenix_gate's cream name board at native size (models/phoenix_gate.py
-- "Sign": 9 x 2.4, centre 10.5 up, front face 1.1 in front of the wall line;
-- "SignRim" behind it ends 0.4 in front of the wall line).
WorldLayout.GATE_BOARD = table.freeze({ width = 9, height = 2.4, centreY = 10.5, front = 1.1, back = 0.4 })
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
local function propSpot(angle: number, faceVolcano: boolean?): { pos: Vec, yaw: number }
	-- Ring path outer edge is r 82 (78 + 8/2). 90 keeps a shop-sized prop off it.
	local r, a = 90, math.rad(angle)
	return { pos = { math.sin(a) * r, 0, math.cos(a) * r }, yaw = if faceVolcano then angle else angle + 180 }
end
WorldLayout.PROP_SPOTS = table.freeze({
	ShopStand = propSpot(67.5, true),
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

local function buildSlide(): { Vec }
	local samples = 33
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
WorldLayout.SLIDE_PATH = table.freeze(buildSlide())

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
local PLOT_BASE_GREY = { 150, 140, 128 } -- warm grey mixed into the plot accent

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

local function mix(a: Vec, b: Vec, t: number): Vec
	return {
		math.round(a[1] * t + b[1] * (1 - t)),
		math.round(a[2] * t + b[2] * (1 - t)),
		math.round(a[3] * t + b[3] * (1 - t)),
	}
end

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
	for _, collider in { plinth, trim, wall } do
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

-- Path tops (v29 B5): every path part is flush with the Ground (top 0) apart
-- from a hair, so there is no step to trip on and no tile edge to see. The
-- parts overlap (spokes cross the ring, ring segments meet at their ends), and
-- coplanar tops z-fight, so each layer sits 0.005..0.01 above the last: the
-- whole path spans 0.018 (tests/WorldLook "path"). SmoothPlastic, not
-- Pavement: Pavement's texture follows each part's own axes, which showed
-- every tile edge as a seam.
WorldLayout.PATH_TOPS = table.freeze({ plaza = 0.032, ringLow = 0.04, ringHigh = 0.045, spoke = 0.05 })
WorldLayout.PATH_THICK = 0.1 -- sunk into the Ground, so only the top shows
WorldLayout.PATH_RING_SEGMENTS = 32

-- A path block sx x sz (X, Z in its own frame, turned by yaw) centred over (x, z), top at `top`.
local function pathBlock(name: string, sx: number, sz: number, x: number, z: number, top: number, yaw: number)
	local thick = WorldLayout.PATH_THICK
	return block(name, { sx, thick, sz }, { x, top - thick / 2, z }, SAND, "SmoothPlastic", { 0, yaw, 0 })
end

local function paths(): WorldNode
	local children: { WorldNode } = {}
	-- Spokes start 1 stud inside the plaza disc so its round edge never leaves
	-- a sliver between the disc and the spoke's straight end.
	local from, to = WorldLayout.PLAZA_RADIUS - 1, WorldLayout.PLOT_RING_RADIUS - WorldLayout.PLOT_SIZE / 2
	for i = 1, Config.PLOT_COUNT do
		local yaw = plotYaw(i)
		local at = frame({ 0, 0, 0 }, yaw)
		local mid = at({ 0, 0, (from + to) / 2 })
		table.insert(children, pathBlock(`Path{i}`, 8, to - from, mid[1], mid[3], WorldLayout.PATH_TOPS.spoke, yaw))
	end
	-- Landing plaza (flat sand disc) the drops land on, under the fountain.
	local plazaTop, thick = WorldLayout.PATH_TOPS.plaza, WorldLayout.PATH_THICK
	table.insert(
		children,
		disc("Plaza", thick, WorldLayout.PLAZA_RADIUS * 2, { 0, plazaTop - thick / 2, 0 }, PLAZA, "Sand")
	)
	-- Ring path outside the drop ring (62), linking every spoke. Each segment
	-- is long enough that its outer corners meet its neighbour's: no gap on the
	-- outer edge, the overlap falls on the inner edge.
	local segments, ringR = WorldLayout.PATH_RING_SEGMENTS, WorldLayout.RING_PATH_RADIUS
	local width = WorldLayout.RING_PATH_WIDTH
	local length = 2 * (ringR + width / 2) * math.tan(math.pi / segments) + 0.1
	for k = 1, segments do
		local yaw = (k - 0.5) * 360 / segments
		local n = LayoutMath.direction(yaw, 0)
		local top = if k % 2 == 0 then WorldLayout.PATH_TOPS.ringHigh else WorldLayout.PATH_TOPS.ringLow
		table.insert(children, pathBlock(`Ring{k}`, length, width, n[1] * ringR, n[3] * ringR, top, yaw))
	end
	return { name = "Paths", class = "Folder", children = children }
end

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
		table.insert(
			children,
			meshSlot(block(prop.name, prop.size, prop.pos, look[1], look[2], { 0, prop.yaw, 0 }), prop.mesh)
		)
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
	ShopStand = WorldLayout.BUY_STAND_MESH,
	LeaderboardBoard = "phoenix_top_earners_board",
})

-- 20° curb tile. Arc centre (plaza origin) is outside the mesh: at yaw 0 the
-- bbox centre sits on +Z (FBX stake match, ranch_landing_ring). Visual only;
-- the box is deeper than the stones and must not leave an invisible wall.
local LANDING_TILES = 18
local LANDING_SIZE: Vec = { 13.145, 3.145, 10.27 }
local LANDING_BBOX = 38.678

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
	local ground = block("Ground", { 640, 2, 640 }, { 0, -1, 0 }, GRASS, "Grass")
	return {
		name = WorldLayout.MAP_NAME,
		class = "Folder",
		children = { ground, volcano(), chute(), paths(), plaza(), decor(), WorldBorder.build() :: any },
	}
end

-- Plots ------------------------------------------------------------------

-- Local pad centre (x, z) for pad index 1..PADS_MAX: rows of four, front
-- row first, the vat and lock button sit between the pads and the entrance.
function WorldLayout.padOffset(j: number): (number, number)
	local perRow = 4
	local col = (j - 1) % perRow
	local row = (j - 1) // perRow
	return (col - (perRow - 1) / 2) * 16, 2 + row * 16
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

-- Attribute-driven plot cosmetics (PlotDecor; VisualsClient shows / hides
-- them locally): lock barrier + lock sign, rebirth
-- trim / pillars / banners / crown, SlimeDex board. Shipped in their neutral
-- state: free plot, unlocked, no rebirths, empty dex.
local function cosmetics(at: (Vec) -> Vec, yaw: number, s: number): { WorldNode }
	local r = { 0, yaw, 0 }
	local h = s / 2
	local nodes: { WorldNode } = {}

	-- Lock barrier: four ForceField panels around the plot (hidden = unlocked).
	local wall = PlotDecor.BARRIER_HEIGHT
	local barrier: WorldNode = { name = "LockBarrier", class = "Model", children = {} }
	for _, side in
		{
			{ "Front", { s, wall, 0.3 }, { 0, 1 + wall / 2, -h } },
			{ "Back", { s, wall, 0.3 }, { 0, 1 + wall / 2, h } },
			{ "Left", { 0.3, wall, s }, { -h, 1 + wall / 2, 0 } },
			{ "Right", { 0.3, wall, s }, { h, 1 + wall / 2, 0 } },
		}
	do
		local panel = block(side[1], side[2], at(side[3]), PlotDecor.BARRIER_COLOR, "ForceField", r)
		table.insert(barrier.children :: { WorldNode }, ghost(panel, 1))
	end
	table.insert(nodes, barrier)

	-- Lock sign next to the LockButton, facing the entrance (Front face). Wood
	-- like the kit fence, not gunmetal (read as a grey slab: tools/render review).
	local lockSign = ghost(block("LockSign", { 7, 2.6, 0.3 }, at({ 19, 7.2, -17.2 }), SIGN_BOARD, "Wood", r))
	lockSign.children = {
		ghost(block("Post", { 0.5, 5.6, 0.5 }, at({ 19, 3.8, -16.8 }), FENCE, "Wood", r)),
		ghost(disc("Lamp", 0.4, 1.3, at({ 19, 8.7, -17.2 }), { 90, 220, 110 }, "Neon", yaw)),
	}
	table.insert(nodes, lockSign)

	-- Rebirth cosmetics (PlotDecor.band): trim, pillars, banners, crown.
	local rebirth: WorldNode = { name = "RebirthDecor", class = "Model", children = {} }
	local function add(node: WorldNode)
		table.insert(rebirth.children :: { WorldNode }, ghost(node, 1))
	end
	local metal = { 168, 148, 110 } -- ranch_metal (pewter); blue-grey is off the ranch palette
	add(block("Trim_Back", { s, 0.4, 1.3 }, at({ 0, 4.2, h - 0.5 }), metal, "Metal", r))
	add(block("Trim_Left", { 1.3, 0.4, s }, at({ -h + 0.5, 4.2, 0 }), metal, "Metal", r))
	add(block("Trim_Right", { 1.3, 0.4, s }, at({ h - 0.5, 4.2, 0 }), metal, "Metal", r))
	for k, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = corner[1] * (h - 1), corner[2] * (h - 1)
		add(block(`Pillar_{k}`, { 2.2, 10, 2.2 }, at({ x, 6, z }), metal, "Marble", r))
		local cap = { name = `PillarCap_{k}`, class = "Part", shape = "Ball", size = { 2.6, 2.6, 2.6 } } :: WorldNode
		cap.pos, cap.rot, cap.color, cap.material = at({ x, 12.3, z }), r, metal, "Neon"
		add(cap)
	end
	-- Banners hang on both sides of the entrance Sign (posts at x = +-8.4).
	add(block("Banner_L", { 3, 7, 0.15 }, at({ -10.4, 8.5, -h + 0.4 }), metal, "Fabric", r))
	add(block("Banner_R", { 3, 7, 0.15 }, at({ 10.4, 8.5, -h + 0.4 }), metal, "Fabric", r))
	local crown = { name = "Crown", class = "Part", shape = "Ball", size = { 3, 3, 3 } } :: WorldNode
	crown.pos, crown.rot, crown.color, crown.material = at({ 0, 15.5, -h + 0.5 }), r, metal, "Neon"
	add(crown)
	table.insert(nodes, rebirth)

	-- SlimeDex board on the back wall, facing the entrance: a DEX_MESH slot
	-- (kit front turned 180 to face the entrance, back clear of the fence) with
	-- the dark Board (PlotDecor's text), bar and gems on its front panel. Frame,
	-- legs and shelf are the primitive look until the mesh lands.
	local k, a, face = WorldLayout.DEX_SCALE, WorldLayout.DEX_CONTENT_SCALE, WorldLayout.DEX_FACE
	local dexSize = meshSize(WorldLayout.DEX_MESH, k)
	local dexZ = h - 1.4 - dexSize[3] / 2
	local panelZ = dexZ - face.front * k
	-- Content offsets are the old board's (centre 9.2 up, h - 1.2): x, y and
	-- z (toward +Z = the back wall) from the Board centre, scaled by `a`. The
	-- content spans y -3.6..3.4, so the Board sits 0.1 above the panel centre.
	local cx, cy, cz = -face.x * k, 1 + face.y * k + 0.1 * a, panelZ - 0.02 - 0.2 * a
	local function on(x: number, y: number, z: number): Vec
		return at({ cx + x * a, cy + y * a, cz + z * a })
	end
	local legH = cy + 0.8 * a - 1
	local dex: WorldNode = {
		name = "DexBoard",
		class = "Model",
		primaryPart = "Board",
		children = {
			meshSlot(
				block("DexMesh", dexSize, at({ 0, 1 + dexSize[2] / 2, dexZ }), WOOD, nil, { 0, yaw + 180, 0 }),
				WorldLayout.DEX_MESH,
				true
			),
			ghost(block("Board", { 14 * a, 6 * a, 0.4 * a }, on(0, 0, 0), { 46, 52, 70 }, "SmoothPlastic", r)),
			standIn(
				ghost(block("Frame", { 14.8 * a, 6.8 * a, 0.3 * a }, on(0, 0, 0.2), WOOD, "Wood", r)),
				WorldLayout.DEX_MESH
			),
			standIn(
				ghost(
					block(
						"LegL",
						{ 0.6 * a, legH, 0.6 * a },
						at({ cx - 6.8 * a, 1 + legH / 2, cz + 0.3 * a }),
						WOOD,
						"Wood",
						r
					)
				),
				WorldLayout.DEX_MESH
			),
			standIn(
				ghost(
					block(
						"LegR",
						{ 0.6 * a, legH, 0.6 * a },
						at({ cx + 6.8 * a, 1 + legH / 2, cz + 0.3 * a }),
						WOOD,
						"Wood",
						r
					)
				),
				WorldLayout.DEX_MESH
			),
			standIn(
				ghost(block("Shelf", { 14 * a, 0.4 * a, 1.8 * a }, on(0, -3.8, -0.8), WOOD, "WoodPlanks", r)),
				WorldLayout.DEX_MESH
			),
			ghost(block("BarBack", { 12 * a, 0.9 * a, 0.2 * a }, on(0, -2, -0.3), { 25, 25, 35 }, "SmoothPlastic", r)),
			ghost(block("BarFill", { 12 * a, 0.7 * a, 0.2 * a }, on(0, -2, -0.4), GOO, "Neon", r), 1),
		},
	}
	for g = 1, #Config.RARITIES do
		local d = 1.3 * a
		local gem = { name = `Gem_{g}`, class = "Part", shape = "Ball", size = { d, d, d } } :: WorldNode
		-- Front faces read along local -X, so tier 1 sits at +X (the viewer's left).
		gem.pos, gem.rot = on((4 - g) * 1.75, -2.95, -0.8), r
		gem.color, gem.material = PlotDecor.GEM_OFF, "Glass"
		table.insert(dex.children :: { WorldNode }, ghost(gem))
	end
	table.insert(nodes, dex)

	return nodes
end

local function plot(i: number): WorldNode
	local centre, yaw = WorldLayout.plotCentre(i)
	local at = frame(centre, yaw)
	local s = WorldLayout.PLOT_SIZE
	local color = PLOT_COLORS[(i - 1) % #PLOT_COLORS + 1]
	local children: { WorldNode } = {
		block("Base", { s, 1, s }, at({ 0, 0.5, 0 }), mix(color, PLOT_BASE_GREY, 0.55), "Pavement", { 0, yaw, 0 }),
	}
	for j = 1, Config.PADS_MAX do
		local x, z = WorldLayout.padOffset(j)
		local look = WorldLayout.PAD_MESHES[(j + i - 2) % #WorldLayout.PAD_MESHES + 1]
		-- Pad stays the gameplay surface (collision, prompt, slimes rest on its
		-- top) from the Base up to the stand's seat; the stand mesh sits on the
		-- Base at native size and the Pad hides under it once it lands.
		local seat = WorldLayout.PAD_SEAT[look]
		local pad = block(`Pad_{j}`, { 8, seat, 8 }, at({ x, 1 + seat / 2, z }), color, "SmoothPlastic", { 0, yaw, 0 })
		pad.attributes = { PadIndex = j }
		standIn(pad, look)
		local stand = meshSize(look, 1)
		pad.children =
			{ meshSlot(block("Stand", stand, at({ x, 1 + stand[2] / 2, z }), color, nil, { 0, yaw, 0 }), look, true) }
		table.insert(children, pad)
	end

	local zone = block("HomeZone", { s, 14, s }, at({ 0, 8, 0 }), color, "SmoothPlastic", { 0, yaw, 0 })
	zone.transparency = 1
	zone.canCollide = false
	zone.canQuery = false
	table.insert(children, zone)

	local vat = disc("MergeVat", 4, 9, at({ -19, 3, -14 }), { 150, 160, 180 }, "Metal", yaw)
	vat.children = { disc("Goo", 0.4, 7.6, at({ -19, 5.1, -14 }), GOO, "Neon", yaw) }
	table.insert(children, vat)

	local button = disc("LockButton", 0.6, 4, at({ 19, 2.8, -14 }), { 255, 70, 70 }, "Neon", yaw)
	button.children = { block("Pedestal", { 5, 1.5, 5 }, at({ 19, 1.75, -14 }), FENCE, "WoodPlanks", { 0, yaw, 0 }) }
	table.insert(children, button)

	-- Sign = the gate mesh's cream name board (PlotSigns writes on its Front
	-- face), its bottom edge >= 9 above the walkway. Its front face sits just
	-- proud of the board, its back face on the board's rim back: the text
	-- sits on the board, nothing floats behind the beam (v28: "Plot 2 / Empty
	-- plot" hung off the gate's back). Board, posts and beam are stand-ins:
	-- the mesh draws them once it lands.
	local wallZ = -s / 2 + 0.5
	local board = WorldLayout.GATE_BOARD
	local signY = 1 + board.centreY
	local signFront, signBack = wallZ - board.front - 0.05, wallZ - board.back
	local sign = standIn(
		block(
			"Sign",
			{ board.width, board.height, signBack - signFront },
			at({ 0, signY, (signFront + signBack) / 2 }),
			SIGN,
			"WoodPlanks",
			{ 0, yaw, 0 }
		),
		"phoenix_gate"
	)
	local postH = signY + 1.2 - 1
	sign.children = {
		standIn(
			block("PostL", { 0.8, postH, 0.8 }, at({ -8.4, 1 + postH / 2, wallZ }), WOOD, "Wood", { 0, yaw, 0 }),
			"phoenix_gate"
		),
		standIn(
			block("PostR", { 0.8, postH, 0.8 }, at({ 8.4, 1 + postH / 2, wallZ }), WOOD, "Wood", { 0, yaw, 0 }),
			"phoenix_gate"
		),
		standIn(
			block("Beam", { 17.6, 1.2, 0.8 }, at({ 0, signY + 1.2 + 0.6, wallZ }), WOOD, "Wood", { 0, yaw, 0 }),
			"phoenix_gate"
		),
	}
	table.insert(children, sign)

	-- Fence: walls WALL_HEIGHT tall on three sides plus the front either side
	-- of the GATE_SLOT, so the gate is the only way in. The walls are the
	-- collision and are invisible; the look is FENCE_MESH panels on the
	-- 20-stud grid (FENCE_SEGMENT halves until it is uploaded, and beside the
	-- gate), visual only, primitive boxes until the mesh lands.
	-- The gate is a kit mesh slot too.
	local wh, r = WorldLayout.WALL_HEIGHT, { 0, yaw, 0 }
	local wy = 1 + wh / 2
	local slot, clear = WorldLayout.GATE_SLOT, WorldLayout.GATE_CLEAR
	local front = (s - slot) / 2
	for _, w in
		{
			{ "WallBack", { s, wh, 1 }, { 0, wy, s / 2 - 0.5 } },
			{ "WallLeft", { 1, wh, s }, { -s / 2 + 0.5, wy, 0 } },
			{ "WallRight", { 1, wh, s }, { s / 2 - 0.5, wy, 0 } },
			{ "WallFrontL", { front, wh, 1 }, { -(slot + front) / 2, wy, -s / 2 + 0.5 } },
			{ "WallFrontR", { front, wh, 1 }, { (slot + front) / 2, wy, -s / 2 + 0.5 } },
		}
	do
		local node = block(w[1] :: string, w[2] :: Vec, at(w[3] :: Vec), FENCE, "WoodPlanks", r)
		node.transparency = 1
		node.attributes = { FenceCollider = true }
		table.insert(children, node)
	end
	local fence: WorldNode = { name = "Fence", class = "Model", children = {} }
	local panelUp = WorldLayout.fenceUploaded()
	for _, seg in WorldLayout.fenceSegments() do
		local turn = { 0, yaw + seg.yaw, 0 }
		-- One kit slot `offset` studs along the piece (its local +X).
		local function piece(name: string, mesh: string, offset: number): WorldNode
			local a = math.rad(seg.yaw)
			local size = meshSize(mesh, WorldLayout.FENCE_SCALE)
			local pos = at({ seg.x + math.cos(a) * offset, 1 + size[2] / 2, seg.z - math.sin(a) * offset })
			return meshSlot(ghost(block(name, size, pos, FENCE, "WoodPlanks", turn)), mesh)
		end
		local node: WorldNode
		if seg.length == WorldLayout.FENCE_SEGMENT_GRID then
			node = piece(seg.name, WorldLayout.FENCE_SEGMENT, 0)
		elseif panelUp then
			node = piece(seg.name, WorldLayout.FENCE_MESH, 0)
		else
			local q = WorldLayout.FENCE_SEGMENT_GRID / 2
			node = {
				name = seg.name,
				class = "Model",
				primaryPart = "A",
				attributes = { FenceMesh = WorldLayout.FENCE_MESH },
				children = {
					piece("A", WorldLayout.FENCE_SEGMENT, -q),
					piece("B", WorldLayout.FENCE_SEGMENT, q),
				},
			}
		end
		table.insert(fence.children :: { WorldNode }, node)
	end
	-- Each piece has its post at its -X end and the sides run one way round
	-- the loop (Back +X, Right -Z, Front -X, Left +Z), so the next piece's
	-- post closes every joint and corner: one post each, never two. The gate
	-- breaks the loop: the left gate segment starts there (post 0.82 out from
	-- the stub), the right one ends there without a post, so a GATE_POST_MESH
	-- mirrors that post on the right (GATE_POST_SLOT_BUDGET).
	local postSize = meshSize(WorldLayout.GATE_POST_MESH, WorldLayout.FENCE_SCALE)
	local postX = slot / 2 + WorldLayout.FENCE_POST_INSET
	table.insert(
		fence.children :: { WorldNode },
		meshSlot(
			ghost(block("GatePost", postSize, at({ postX, 1 + postSize[2] / 2, wallZ }), FENCE, "Wood", r)),
			WorldLayout.GATE_POST_MESH
		)
	)
	table.insert(children, fence)
	local postW = (slot - clear) / 2
	-- The kit gate is built for this slot (14 clear, stubs to +-10): native size.
	-- Kit FBX fronts face Roblox +Z (LESSONS kit gotcha): turn it 180 so the
	-- name board faces out of the entrance.
	local gateSize = meshSize("phoenix_gate", 1)
	local gate: WorldNode = {
		name = "Gate",
		class = "Model",
		primaryPart = "GateMesh",
		children = {
			meshSlot(
				block("GateMesh", gateSize, at({ 0, 1 + gateSize[2] / 2, wallZ }), WOOD, nil, { 0, yaw + 180, 0 }),
				"phoenix_gate",
				true
			),
			standIn(
				block(
					"GatePostL",
					{ postW, wh + 1, 1.2 },
					at({ -(clear + postW) / 2, 1 + (wh + 1) / 2, -s / 2 + 0.5 }),
					WOOD,
					"Wood",
					r
				),
				"phoenix_gate"
			),
			standIn(
				block(
					"GatePostR",
					{ postW, wh + 1, 1.2 },
					at({ (clear + postW) / 2, 1 + (wh + 1) / 2, -s / 2 + 0.5 }),
					WOOD,
					"Wood",
					r
				),
				"phoenix_gate"
			),
		},
	}
	table.insert(children, gate)

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
