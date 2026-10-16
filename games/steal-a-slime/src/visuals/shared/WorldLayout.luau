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
	           (rocks, mushrooms, ranch props), Border (WorldBorder: the
	           invisible wall ring + seeded hedges, fences, pines, hills,
	           rocks along the edge). Kit meshes go on MeshAsset slots via
	           server/MeshSwap.
	  Plots    Plot_1..PLOT_COUNT in a ring around the fountain, each facing
	           it (entrance at local -Z): Base, Pad_1..PADS_MAX, HomeZone,
	           MergeVat, LockButton, Sign, walls, Slimes folder, and the
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
local PlotDecor = if script then require(script.Parent.PlotDecor) else require("./PlotDecor")
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
-- Legacy name: the fountain still answers to Map.Volcano(.Crater) (CONTRACT §5.3).
WorldLayout.VOLCANO_HEIGHT = WorldLayout.FOUNTAIN_HEIGHT
-- The live ride is WorldLayout.SLIDE_PATH (mesh spiral, end r 35.5 on +Z).
-- The old straight chute bearing was yaw 22.5; that slide is gone.
WorldLayout.RING_PATH_RADIUS = 78
WorldLayout.RING_PATH_WIDTH = 8
WorldLayout.GATE_SLOT = 20 -- fence gap at the entrance
WorldLayout.GATE_CLEAR = 14 -- walkable opening inside the slot
WorldLayout.WALL_HEIGHT = 8
-- Pad stand looks (Phoenix kit), cycled per pad.
WorldLayout.PAD_MESHES =
	table.freeze({ "phoenix_pad_crate", "phoenix_pad_hay", "phoenix_pad_goo", "phoenix_pad_stool" })
-- Where a slime sits on each stand at native size (kit model headers): the Pad
-- top goes here, so slimes rest on the mesh instead of sinking into it.
WorldLayout.PAD_SEAT = table.freeze({
	phoenix_pad_crate = 2.4,
	phoenix_pad_hay = 1.0,
	phoenix_pad_goo = 1.5,
	phoenix_pad_stool = 3.0,
})
-- phoenix_gate's cream name board at native size (models/phoenix_gate.py
-- "Sign": 9 x 2.4, centre 10.5 up, front face 1.1 in front of the wall line).
WorldLayout.GATE_BOARD = table.freeze({ width = 9, height = 2.4, centreY = 10.5, front = 1.1 })

-- Suggested placements for Props (pivot CFrame = CFrame.new(pos) *
-- CFrame.Angles(0, math.rad(yaw), 0)), just outside the ring path between
-- two spokes. Shop and board face outward (local -Z towards the plots); the
-- tutorial NPC stands behind the hub SpawnLocation (scripts/StaticWorld,
-- same bearing) and faces it.
local function propSpot(angle: number, faceVolcano: boolean?): { pos: Vec, yaw: number }
	-- Ring path outer edge is r 82 (78 + 8/2). 90 keeps a shop-sized prop off it.
	local r, a = 90, math.rad(angle)
	return { pos = { math.sin(a) * r, 0, math.cos(a) * r }, yaw = if faceVolcano then angle else angle + 180 }
end
WorldLayout.PROP_SPOTS = table.freeze({
	ShopStand = propSpot(67.5),
	LeaderboardBoard = propSpot(157.5),
	TutorialNpc = propSpot(247.5, true),
}) :: { [string]: { pos: Vec, yaw: number } }

-- Spiral the polished slime_fountain slide follows (models/slime_fountain.py):
-- 1.75 turns, end r 35.5 at the front. Kit (x, y, z-up) -> Roblox (x, z, -y),
-- silo axis at the world origin. Wilds ride this; the primitive chute copies it
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
		local p = xy[k]
		table.insert(path, { p[1], z, -p[2] })
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

-- Map --------------------------------------------------------------------

-- Slime fountain (kit slime_fountain), kept under the contract name
-- Map.Volcano with Crater (the goo pool on top) as the drop origin.
local function volcano(): WorldNode
	local h = WorldLayout.FOUNTAIN_HEIGHT
	local d = WorldLayout.FOUNTAIN_DIAMETER
	local M = "slime_fountain"
	local children: { WorldNode } = {
		standIn(disc("Rock1", 3, d, { 0, 1.5, 0 }, STONE, "Slate"), M),
		standIn(disc("BasinRim", 1, d + 1, { 0, 3.5, 0 }, STONE_TRIM, "Slate"), M),
		standIn(disc("Pool", 0.4, d - 3, { 0, 3.1, 0 }, POOL, "Glass"), M),
		standIn(disc("Column", h - 8, 6, { 0, 3 + (h - 8) / 2, 0 }, STONE, "Slate"), M),
		standIn(disc("Bowl", 3, 14, { 0, h - 3.5, 0 }, STONE_TRIM, "Slate"), M),
	}
	local pool = children[3]
	pool.canCollide = false
	-- Stand-in too: once the mesh is in, a d11 neon plate poked out round the
	-- mesh's own goo crown. It keeps its place as the drop origin and emitter host.
	local crater = standIn(disc("Crater", 0.6, 11, { 0, h - 1.7, 0 }, POOL, "Neon"), M)
	crater.canCollide = false
	-- Client emitters attach here (VisualsClient); the glow keeps the pool lit.
	crater.children = { light("CraterGlow") }
	table.insert(children, crater)
	-- The fountain's collision, shaped like the mesh (FOUNTAIN_PROFILE): a
	-- walkable plinth (ground to its 1.5-stud top) and the silo wall from the
	-- plinth top to the eave. Both invisible and anchored, tagged
	-- MeshCollider = M and off until the mesh loads: MeshSwap flips them on
	-- and the stand-ins off in one step (MeshStandInsCollide). While loading
	-- or failed the visible stand-ins are the only collision.
	local fp = WorldLayout.FOUNTAIN_PROFILE
	local wallHeight = fp.eaveTop - fp.plinthTop
	local plinth = disc("BasinCollider", fp.plinthTop, fp.plinthRadius * 2, { 0, fp.plinthTop / 2, 0 }, STONE_TRIM)
	local wall = disc("SiloCollider", wallHeight, fp.wallRadius * 2, { 0, fp.plinthTop + wallHeight / 2, 0 }, STONE)
	for _, c in { plinth, wall } do
		c.attributes = { MeshCollider = M }
		c.transparency = 1
		c.canCollide = false
		c.canQuery = false
		c.canTouch = false
		table.insert(children, c)
	end
	-- Native bbox of the polished slime_fountain (stats size, no squash).
	-- Silo axis is kit (-6.52, 7.75) from the bbox centre (FOUNTAIN_SIZES)
	-- = Roblox X/Z (-6.52, -7.75) with Z = -kit y. The slot sits on the
	-- opposite point so the silo axis is the world origin and the base is y = 0.
	local fountainSize: Vec = { 54.45, 43.316, 63.851 }
	local fountainCentre: Vec = { 6.52, fountainSize[2] / 2, 7.75 }
	local slot = meshSlot(block("FountainMesh", fountainSize, fountainCentre, STONE), M, true)
	slot.attributes = slot.attributes or {}
	slot.attributes.MeshStandInsCollide = false
	table.insert(children, slot)
	-- Emerge slimes, split out of the fountain (FOUNTAIN_SIZES). Offset is
	-- the emerge bbox centre minus the fountain bbox centre, Roblox axes.
	-- Invisible until its mesh id is filled; bobbing can hook this slot later.
	local emergePos: Vec = {
		fountainCentre[1] - 11.2,
		fountainCentre[2] + 18.94,
		fountainCentre[3] - 8.25,
	}
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

local function paths(): WorldNode
	local children: { WorldNode } = {}
	local from, to = WorldLayout.PLAZA_RADIUS, WorldLayout.PLOT_RING_RADIUS - WorldLayout.PLOT_SIZE / 2
	for i = 1, Config.PLOT_COUNT do
		local yaw = plotYaw(i)
		local at = frame({ 0, 0, 0 }, yaw)
		local tile = block(
			`Path{i}`,
			{ 8, 0.2, to - from },
			at({ 0, 0.1, (from + to) / 2 }),
			SAND,
			"Pavement",
			{ 0, yaw, 0 }
		)
		table.insert(children, tile)
	end
	-- Landing plaza (flat sand disc) the drops land on, under the fountain.
	table.insert(children, disc("Plaza", 0.2, WorldLayout.PLAZA_RADIUS * 2, { 0, 0.05, 0 }, PLAZA, "Sand"))
	-- Ring path outside the drop ring (62), linking every spoke.
	local segments, ringR = 32, WorldLayout.RING_PATH_RADIUS
	local length = 2 * math.pi * ringR / segments + 1
	for k = 1, segments do
		local yaw = (k - 0.5) * 360 / segments
		local n = LayoutMath.direction(yaw, 0)
		table.insert(
			children,
			block(
				`Ring{k}`,
				{ length, 0.2, WorldLayout.RING_PATH_WIDTH },
				{ n[1] * ringR, 0.12, n[3] * ringR },
				SAND,
				"Pavement",
				{
					0,
					yaw,
					0,
				}
			)
		)
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

-- Decor rocks are plain ranch Rock (no basalt).
local function rock(name: string, pos: Vec, s: number, salt: number): WorldNode
	return block(
		name,
		{ s * (1 + hash(salt, 4) * 0.6), s * (0.6 + hash(salt, 5) * 0.5), s * (1 + hash(salt, 6) * 0.6) },
		{ pos[1], s * 0.25, pos[3] },
		ROCK,
		"Rock",
		{ hash(salt, 7) * 20 - 10, hash(salt, 8) * 360, hash(salt, 9) * 20 - 10 }
	)
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
	return true
end

local function decor(): WorldNode
	local children: { WorldNode } = {}
	local function add(node: WorldNode, pos: Vec, radius: number): boolean
		if clearSpot(pos, radius) then
			table.insert(children, node)
			return true
		end
		return false
	end
	-- Scattered rocks and mushrooms between and behind the plots.
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
	-- Sparse ranch props behind the plots, between neighbours (kit meshes).
	local RANCH = {
		{ "ranch_hay_bale", meshSize("ranch_hay_bale", 1.25), { 228, 196, 110 }, "Fabric" },
		{ "ranch_crate", meshSize("ranch_crate", 4 / 3), WOOD, "WoodPlanks" },
		{ "ranch_feed_trough", meshSize("ranch_feed_trough", 1.3), WOOD, "Wood" },
		{ "ranch_crate_goo", meshSize("ranch_crate_goo", 4 / 3), { 120, 220, 140 }, "WoodPlanks" },
	}
	for k = 1, Config.PLOT_COUNT do
		local yaw = plotYaw(k) + 360 / Config.PLOT_COUNT / 2
		local def = RANCH[(k - 1) % #RANCH + 1]
		local size = def[2] :: Vec
		local pos = onPolar(yaw, 200, size[2] / 2)
		local node =
			meshSlot(block(`Ranch{k}`, size, pos, def[3] :: Vec, def[4] :: string, { 0, yaw, 0 }), def[1] :: string)
		add(node, pos, 4)
	end
	for k, yaw in { 90, 270 } do
		local size = meshSize("ranch_shed", 1.4)
		local pos = onPolar(yaw + 22.5, 245, size[2] / 2)
		add(
			meshSlot(block(`Shed{k}`, size, pos, { 176, 92, 72 }, "WoodPlanks", { 0, yaw + 22.5, 0 }), "ranch_shed"),
			pos,
			10
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
	ShopStand = "ranch_shop_stand",
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
		-- face the fountain
		table.insert(children, meshSlot(block(def.name, size, pos, STONE, "Slate", { 0, def.yaw, 0 }), def.mesh))
	end
	local tiles: { WorldNode } = {}
	local y = LANDING_SIZE[2] / 2
	for i = 0, LANDING_TILES - 1 do
		local yaw = i * (360 / LANDING_TILES)
		local a = math.rad(yaw)
		local pos = { math.sin(a) * LANDING_BBOX, y, math.cos(a) * LANDING_BBOX }
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
		visualMesh(block("GooDrain", drainSize, { 0, drainSize[2] / 2, 52 }, PLAZA, "Slate"), "ranch_goo_drain")
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
-- them locally): lock barrier + lock sign, "Free plot" stand, rebirth
-- trim / pillars / banners / crown, SlimeDex board. Shipped in their neutral
-- state: free plot (stand visible), unlocked, no rebirths, empty dex.
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

	-- Lock sign next to the LockButton, facing the entrance (Front face).
	local lockSign = ghost(block("LockSign", { 7, 2.6, 0.3 }, at({ 19, 7.2, -17.2 }), { 60, 60, 70 }, "Metal", r))
	lockSign.children = {
		ghost(block("Post", { 0.5, 5.6, 0.5 }, at({ 19, 3.8, -16.8 }), { 80, 80, 95 }, "Metal", r)),
		ghost(disc("Lamp", 0.4, 1.3, at({ 19, 8.7, -17.2 }), { 90, 220, 110 }, "Neon", yaw)),
	}
	table.insert(nodes, lockSign)

	-- "Free plot" stand on the grass just outside the entrance, left of the
	-- path and clear of the Sign (shown while OwnerUserId == 0). The Coin is
	-- an upright cylinder facing the volcano.
	local bx, bz = -13, -h - 5
	local coin = block(
		"Coin",
		{ 0.4, 1.8, 1.8 },
		at({ bx, 10.1, bz + 0.55 }),
		{ 255, 205, 60 },
		"Neon",
		{ 0, yaw + 90, 0 }
	)
	coin.shape = "Cylinder"
	table.insert(nodes, {
		name = "BuyStand",
		class = "Model",
		primaryPart = "Counter",
		children = {
			ghost(block("Counter", { 6, 3, 2.5 }, at({ bx, 1.5, bz }), WOOD, "WoodPlanks", r)),
			ghost(block("CounterTop", { 6.6, 0.3, 3 }, at({ bx, 3.15, bz }), { 240, 200, 70 }, "SmoothPlastic", r)),
			ghost(block("PostL", { 0.4, 5.6, 0.4 }, at({ bx - 3.6, 6, bz + 0.8 }), WOOD, "Wood", r)),
			ghost(block("PostR", { 0.4, 5.6, 0.4 }, at({ bx + 3.6, 6, bz + 0.8 }), WOOD, "Wood", r)),
			ghost(block("Board", { 8, 3.2, 0.3 }, at({ bx, 7.4, bz + 0.55 }), { 40, 150, 70 }, "SmoothPlastic", r)),
			ghost(coin),
		},
	})

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

	-- SlimeDex board on the back wall, facing the entrance.
	local dex: WorldNode = {
		name = "DexBoard",
		class = "Model",
		primaryPart = "Board",
		children = {
			ghost(block("Board", { 14, 6, 0.4 }, at({ 0, 9.2, h - 1.2 }), { 46, 52, 70 }, "SmoothPlastic", r)),
			ghost(block("Frame", { 14.8, 6.8, 0.3 }, at({ 0, 9.2, h - 1 }), WOOD, "Wood", r)),
			ghost(block("LegL", { 0.6, 9, 0.6 }, at({ -6.8, 5.5, h - 0.9 }), WOOD, "Wood", r)),
			ghost(block("LegR", { 0.6, 9, 0.6 }, at({ 6.8, 5.5, h - 0.9 }), WOOD, "Wood", r)),
			ghost(block("Shelf", { 14, 0.4, 1.8 }, at({ 0, 5.4, h - 2 }), WOOD, "WoodPlanks", r)),
			ghost(block("BarBack", { 12, 0.9, 0.2 }, at({ 0, 7.2, h - 1.5 }), { 25, 25, 35 }, "SmoothPlastic", r)),
			ghost(block("BarFill", { 12, 0.7, 0.2 }, at({ 0, 7.2, h - 1.6 }), GOO, "Neon", r), 1),
		},
	}
	for k = 1, #Config.RARITIES do
		local gem = { name = `Gem_{k}`, class = "Part", shape = "Ball", size = { 1.3, 1.3, 1.3 } } :: WorldNode
		-- Front faces read along local -X, so tier 1 sits at +X (the viewer's left).
		gem.pos, gem.rot = at({ (3.5 - k) * 2.1, 6.25, h - 2 }), r
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
	button.children =
		{ block("Pedestal", { 5, 1.5, 5 }, at({ 19, 1.75, -14 }), { 80, 80, 95 }, "Metal", { 0, yaw, 0 }) }
	table.insert(children, button)

	-- Sign = the gate mesh's cream name board (PlotSigns writes on it), its
	-- bottom edge >= 9 above the walkway. Deep enough to come out just in front
	-- of the board and just behind the beam, so both text faces stay readable.
	-- Board, posts and beam are stand-ins: the mesh draws them once it lands.
	local wallZ = -s / 2 + 0.5
	local board = WorldLayout.GATE_BOARD
	local signY = 1 + board.centreY
	local signFront, signBack = wallZ - board.front - 0.05, wallZ + 0.55
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
	-- of the GATE_SLOT, so the gate is the only way in. Walls stay primitives
	-- (MeshPart budget, THEME.md: <= 150 per map); corner posts and the gate
	-- are kit mesh slots.
	local wh, r = WorldLayout.WALL_HEIGHT, { 0, yaw, 0 }
	local wy = 1 + wh / 2
	local slot, clear = WorldLayout.GATE_SLOT, WorldLayout.GATE_CLEAR
	local front = (s - slot) / 2
	local F = "phoenix_fence_segment"
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
		node.attributes = { FenceMesh = F } -- 10-stud segments once the budget allows
		table.insert(children, node)
	end
	local postSize = meshSize("phoenix_corner_post", (wh + 1) / (MeshAssets.get("phoenix_corner_post") :: any).size[2])
	for k, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local inset = postSize[1] / 2
		local post = block(
			`CornerPost_{k}`,
			postSize,
			at({ c[1] * (s / 2 - inset), 1 + (wh + 1) / 2, c[2] * (s / 2 - inset) }),
			WOOD,
			"Wood",
			r
		)
		table.insert(children, meshSlot(post, "phoenix_corner_post"))
	end
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

return table.freeze(WorldLayout)
