--!strict
--[[
	WorldLayout (owner: Archer)

	WorldLayout.build(): { WorldNode }

	Pure description of the world in CONTRACT.md §5.3, as a tree of nodes
	(Folder / Model / Part / PointLight) in world space. WorldBuilder turns it into
	Instances under workspace; the render proof draws it under Lune.

	  Map      Ground (640x640 baseplate), Volcano = the Slime Ranch fountain
	           (kit slime_fountain; contract name kept, Crater = the goo pool
	           on top = the drop origin), Chute (the slide), Paths (plaza,
	           spokes + ring), Plaza (signpost, podiums), Decor (rocks,
	           mushrooms, ranch props, edge boulders). Kit meshes go on
	           MeshAsset slots via server/MeshSwap.
	  Plots    Plot_1..PLOT_COUNT in a ring around the volcano, each facing
	           it (entrance at local -Z): Base, Pad_1..PADS_MAX, HomeZone,
	           MergeVat, LockButton, Sign, walls, Slimes folder, and the
	           PlotDecor cosmetics (LockBarrier, LockSign, BuyStand,
	           RebirthDecor, DexBoard)
	Every Part is anchored (WorldBuilder forces it). PROP_SPOTS suggests
	where Props go.

	Volcano drops land MIN_RADIUS..MAX_RADIUS (34..62) studs from the centre,
	so the volcano foot stays inside 28 studs and plots start past 90.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Constants = if script then require(script.Parent.Parent.Shared.Constants) else require("../../shared/Constants")
local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local PlotDecor = if script then require(script.Parent.PlotDecor) else require("./PlotDecor")

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
WorldLayout.PLAZA_RADIUS = 55
WorldLayout.FOUNTAIN_HEIGHT = 40 -- FOUNTAIN_SIZES 28..48; Effects caps rise at h/2
WorldLayout.FOUNTAIN_DIAMETER = 28
-- Legacy name: the fountain still answers to Map.Volcano(.Crater) (CONTRACT §5.3).
WorldLayout.VOLCANO_HEIGHT = WorldLayout.FOUNTAIN_HEIGHT
WorldLayout.CHUTE_YAW = 22.5 -- slide runs out between Plot_5 and Plot_6
WorldLayout.RING_PATH_RADIUS = 78
WorldLayout.RING_PATH_WIDTH = 8
WorldLayout.GATE_SLOT = 20 -- fence gap at the entrance
WorldLayout.GATE_CLEAR = 14 -- walkable opening inside the slot
WorldLayout.WALL_HEIGHT = 8
-- Pad stand looks (Phoenix kit), cycled per pad.
WorldLayout.PAD_MESHES =
	table.freeze({ "phoenix_pad_crate", "phoenix_pad_hay", "phoenix_pad_goo", "phoenix_pad_stool" })

-- Suggested placements for Props (pivot CFrame = CFrame.new(pos) *
-- CFrame.Angles(0, math.rad(yaw), 0)), just outside the ring path between
-- two spokes. Shop and board face outward (local -Z towards the plots); the
-- tutorial NPC stands behind the hub SpawnLocation (scripts/StaticWorld,
-- same bearing) and faces it.
local function propSpot(angle: number, faceVolcano: boolean?): { pos: Vec, yaw: number }
	local r, a = 84, math.rad(angle)
	return { pos = { math.sin(a) * r, 0, math.cos(a) * r }, yaw = if faceVolcano then angle else angle + 180 }
end
WorldLayout.PROP_SPOTS = table.freeze({
	ShopStand = propSpot(67.5),
	LeaderboardBoard = propSpot(157.5),
	TutorialNpc = propSpot(247.5, true),
}) :: { [string]: { pos: Vec, yaw: number } }

-- "Volcanic meadow" palette (graphics-strategy.md §4.3): plots get their
-- identity from saturated mid-value accents, neutrals are warm (wood, sand,
-- basalt) and Neon is kept for gameplay signals (lava, buttons, goo, torches).
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
local STONE = { 214, 204, 186 } -- fountain stone (soft ranch cream)
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
	local crater = disc("Crater", 0.6, 11, { 0, h - 1.7, 0 }, POOL, "Neon")
	crater.canCollide = false
	-- Client emitters attach here (VisualsClient); the glow keeps the pool lit.
	crater.children = { light("CraterGlow") }
	table.insert(children, crater)
	table.insert(children, meshSlot(block("FountainMesh", { d, h, d }, { 0, h / 2, 0 }, STONE), M, true))
	return { name = "Volcano", class = "Model", primaryPart = "Rock1", children = children }
end

local function chute(): WorldNode
	local h = WorldLayout.VOLCANO_HEIGHT
	local at = frame({ 0, 0, 0 }, WorldLayout.CHUTE_YAW)
	local top: Vec = { 0, h - 4, -8 }
	local bottom: Vec = { 0, 1, -42 }
	local delta = { bottom[1] - top[1], bottom[2] - top[2], bottom[3] - top[3] }
	local length = math.sqrt(delta[1] ^ 2 + delta[2] ^ 2 + delta[3] ^ 2)
	local dir = LayoutMath.scale(delta, 1 / length)
	local mid = LayoutMath.add(top, LayoutMath.scale(delta, 0.5))
	local rot = LayoutMath.facing(dir)
	local partRot = { rot[1], rot[2] + WorldLayout.CHUTE_YAW, rot[3] }
	local tilt = LayoutMath.orientation(rot)
	local function piece(name: string, size: Vec, offset: Vec, color: Vec, material: string): WorldNode
		return block(name, size, at(LayoutMath.add(mid, LayoutMath.apply(tilt, offset))), color, material, partRot)
	end
	local children: { WorldNode } = {
		piece("Floor", { 7, 0.6, length }, { 0, 0, 0 }, { 110, 236, 150 }, "Glass"),
		piece("WallL", { 0.6, 2.4, length }, { -3.8, 0.9, 0 }, { 52, 150, 96 }, "SmoothPlastic"),
		piece("WallR", { 0.6, 2.4, length }, { 3.8, 0.9, 0 }, { 52, 150, 96 }, "SmoothPlastic"),
	}
	for i, t in { 0.4, 0.7 } do
		local p = LayoutMath.add(top, LayoutMath.scale(delta, t))
		local height = p[2] - 0.6
		table.insert(children, block(`Support{i}`, { 1.6, height, 1.6 }, at({ p[1], height / 2, p[3] }), WOOD, "Wood"))
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

-- Decor rocks and edge boulders are plain ranch Rock (no basalt).
local function rock(name: string, pos: Vec, s: number, salt: number, edge: boolean?): WorldNode
	return block(
		name,
		{ s * (1 + hash(salt, 4) * 0.6), s * (0.6 + hash(salt, 5) * 0.5), s * (1 + hash(salt, 6) * 0.6) },
		{ pos[1], s * 0.25, pos[3] },
		if edge then STONE_TRIM else ROCK,
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
-- spoke paths, the chute and the prop spots.
local function clearSpot(pos: Vec, radius: number): boolean
	local r = math.sqrt(pos[1] ^ 2 + pos[3] ^ 2)
	if r < WorldLayout.RING_PATH_RADIUS + 6 + radius then
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
		{ "ranch_hay_bale", { 5, 4, 5 }, { 228, 196, 110 }, "Fabric" },
		{ "ranch_crate", { 4, 4, 4 }, WOOD, "WoodPlanks" },
		{ "ranch_feed_trough", { 8, 3, 3 }, WOOD, "Wood" },
		{ "ranch_crate_goo", { 4, 4, 4 }, { 120, 220, 140 }, "WoodPlanks" },
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
		local pos = onPolar(yaw + 22.5, 245, 6)
		add(
			meshSlot(
				block(`Shed{k}`, { 16, 12, 12 }, pos, { 176, 92, 72 }, "WoodPlanks", { 0, yaw + 22.5, 0 }),
				"ranch_shed"
			),
			pos,
			10
		)
	end
	-- Boulders along the edge of the ground so nobody walks off the world.
	local edge = 36
	for k = 1, edge do
		local yaw = k * 360 / edge
		local pos = onPolar(yaw, 300, 0)
		table.insert(children, rock(`Edge{k}`, pos, 12 + hash(k, 40) * 6, 100 + k, true))
	end
	return { name = "Decor", class = "Folder", children = children }
end

-- Plaza showpieces between the drop ring (62) and the ring path, as kit mesh
-- slots. The Top Earners board and shop stand skin the live WorldProps models
-- (ShopStand / LeaderboardBoard, MeshAsset on the Model).
WorldLayout.PLAZA_PROPS = table.freeze({
	{ name = "Signpost", mesh = "ranch_plaza_signpost", yaw = 112.5, r = 68, size = { 4, 9, 2 } },
	{ name = "Podium_1", mesh = "phoenix_plaza_podium_1", yaw = 157.5, r = 68, size = { 5, 3, 5 } },
	{ name = "Podium_2", mesh = "phoenix_plaza_podium_2", yaw = 150, r = 68, size = { 5, 2.2, 5 } },
	{ name = "Podium_3", mesh = "phoenix_plaza_podium_3", yaw = 165, r = 68, size = { 5, 1.6, 5 } },
})
WorldLayout.PROP_MESHES = table.freeze({
	ShopStand = "ranch_shop_stand",
	LeaderboardBoard = "phoenix_top_earners_board",
})

local function plaza(): WorldNode
	local children: { WorldNode } = {}
	for _, def in WorldLayout.PLAZA_PROPS do
		local size = def.size :: Vec
		local pos = onPolar(def.yaw, def.r, size[2] / 2)
		-- face the fountain
		table.insert(children, meshSlot(block(def.name, size, pos, STONE, "Slate", { 0, def.yaw, 0 }), def.mesh))
	end
	return { name = "Plaza", class = "Folder", children = children }
end

local function map(): WorldNode
	local ground = block("Ground", { 640, 2, 640 }, { 0, -1, 0 }, GRASS, "Grass")
	return {
		name = WorldLayout.MAP_NAME,
		class = "Folder",
		children = { ground, volcano(), chute(), paths(), plaza(), decor() },
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
	local metal = { 200, 200, 210 }
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
		local pad = block(`Pad_{j}`, { 8, 0.6, 8 }, at({ x, 1.3, z }), color, "SmoothPlastic", { 0, yaw, 0 })
		pad.attributes = { PadIndex = j }
		local look = WorldLayout.PAD_MESHES[(j + i - 2) % #WorldLayout.PAD_MESHES + 1]
		-- Pad stays the gameplay surface; the stand mesh fills the same box.
		pad.children = { meshSlot(block("Stand", { 8, 0.6, 8 }, at({ x, 1.3, z }), color), look, true) }
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

	-- Sign spans the gate; its bottom edge stays >= 9 above the walkway.
	local sign = block("Sign", { 16, 5, 0.6 }, at({ 0, 12, -s / 2 + 0.5 }), SIGN, "WoodPlanks", { 0, yaw, 0 })
	sign.children = {
		block("PostL", { 0.8, 13, 0.8 }, at({ -8.4, 7.5, -s / 2 + 0.5 }), WOOD, "Wood", { 0, yaw, 0 }),
		block("PostR", { 0.8, 13, 0.8 }, at({ 8.4, 7.5, -s / 2 + 0.5 }), WOOD, "Wood", { 0, yaw, 0 }),
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
	for k, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local post = block(
			`CornerPost_{k}`,
			{ 2, wh + 1, 2 },
			at({ c[1] * (s / 2 - 1), 1 + (wh + 1) / 2, c[2] * (s / 2 - 1) }),
			WOOD,
			"Wood",
			r
		)
		table.insert(children, meshSlot(post, "phoenix_corner_post"))
	end
	local postW = (slot - clear) / 2
	local gate: WorldNode = {
		name = "Gate",
		class = "Model",
		primaryPart = "GateMesh",
		children = {
			meshSlot(
				block("GateMesh", { slot, wh + 1, 1 }, at({ 0, 1 + (wh + 1) / 2, -s / 2 + 0.5 }), WOOD),
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
