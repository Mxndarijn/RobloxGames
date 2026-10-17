--!strict
--[[
	WorldBorder (pure, no Roblox APIs)

	WorldBorder.build(seed?): Node        -- Map.Border (Walls + Decor)
	WorldBorder.colliders(): { Collider } -- the invisible wall ring
	WorldBorder.pieces(seed?): { Piece }  -- decor along the edge

	The Slime Ranch edge of the 640-stud Ground. Two layers:

	  Walls    WALL_SEGMENTS invisible, anchored, CanCollide blocks whose
	           inner faces form a closed polygon at RADIUS, WALL_HEIGHT tall
	           so nobody jumps out. CanQuery/CanTouch off: drop raycasts,
	           prompts and the camera ignore them.
	  Decor    single kit pieces scattered in three layers just outside the
	           wall line, each walked round the ring by its own seeded Rng:
	             inner  fences and hedges hugging the wall, with openings
	                    (+ a few uploaded ranch props as accents)
	             mid    groves: clusters of pines, oaks, saplings and rocks
	                    (a pine grove, a meadow or a rocky patch each),
	                    open ground between them, depth jittered
	             outer  backdrop hills (ridge, dome, twin) closing the horizon
	           plus CORNER_CHUNKS deep groves per Ground corner (the square
	           reaches r 452 on the diagonals) from the old chunk meshes.
	         Every piece rolls its own scale, yaw and spacing. A piece never
	         repeats either of the two before it, and no window of
	         WINDOW consecutive pieces of a layer repeats the same
	         (mesh, rotation bucket, scale bucket) pattern anywhere in the
	         ring, so no stretch looks copy-pasted. Every build is identical.

	GIANTS (border v5, v6): a ring of GIANT_COUNT huge trees of six NEW kit
	meshes (v5 giant_broadleaf, giant_pine_layered, giant_round_canopy; v6
	giant_elder_oak, giant_sequoia_spire, giant_cloud_tree), 3-8x the height of
	the border pines, stand on the Terrain hills beyond the fence and in front
	of the mountains, in three overlapping radial depth bands, with irregular
	gaps, deck-dealt species and tints.

	Decor never collides; the walls are the only collision. Every decor piece
	is one MeshAsset slot (MeshSwap skins it); the pieces and giants add up
	to WorldLayout.BORDER_SLOT_COUNT.
]]

local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")
local Rng = if script then require(script.Parent.Parent.Shared.Rng) else require("../../shared/Rng")
local BorderTerrain = if script then require(script.Parent.BorderTerrain) else require("./BorderTerrain")

type Vec = LayoutMath.Vec

-- Same shape as WorldLayout.WorldNode (WorldLayout requires this module).
export type Node = {
	name: string,
	class: string,
	shape: string?,
	size: Vec?,
	pos: Vec?,
	rot: Vec?,
	color: Vec?,
	material: string?,
	transparency: number?,
	canCollide: boolean?,
	canQuery: boolean?,
	canTouch: boolean?,
	attributes: { [string]: any }?,
	primaryPart: string?,
	children: { Node }?,
}

export type Collider = { pos: Vec, size: Vec, yaw: number }

export type Piece = {
	kind: string,
	mesh: string, -- MeshAssets name (chunk design + "_m" when mirrored)
	row: string, -- "inner" | "mid" | "outer" | "corner"
	order: number, -- position in its layer's walk (1-based; corner groves 0)
	turn: number, -- yaw off facing the map, -180..180 degrees
	rotBucket: number, -- turn / ROT_BUCKET, 0-based (0 for corner groves)
	scaleBucket: number, -- 0..SCALE_BUCKETS - 1 across the def's scale range
	angle: number, -- polar bearing in degrees (0 = +Z, 90 = +X)
	radius: number, -- slot centre distance from the map centre
	pos: Vec, -- slot centre; y = half height, so it stands on the ground
	size: Vec, -- native mesh size x scale
	yaw: number,
	scale: number,
	mirrored: boolean,
	uploaded: boolean, -- MeshAssets has a meshId (MeshSwap can skin the slot)
	tilt: { number }?, -- giants: lean about X and Z in degrees
	tint: Vec?, -- giants: MeshPart.Color the slot hands the swapped mesh (0-255)
	band: number?, -- giants: radial depth band, 1 = nearest the fence
}

type Chunk = {
	kind: string,
	mesh: string, -- base design; "<mesh>_m" is its mirrored twin
	corner: number, -- placements in the corner set (half plain, half mirrored)
}

-- One kit mesh scattered along a layer. weights: per theme (the mid layer's
-- clusters pick a theme; inner and outer use "all"). turn: largest yaw
-- jitter in degrees off facing the map (180 = any heading).
type Def = {
	kind: string,
	mesh: string,
	layer: string,
	weights: { [string]: number },
	scale: { number },
	turn: number,
}

local WorldBorder = {}

WorldBorder.SEED = 20261018
WorldBorder.GROUND_HALF = 320 -- WorldLayout Ground is 640 x 640, centred
-- Inner face of the wall ring. The plots end at r ~197, the sheds at
-- ~253; WorldLayout keeps scattered decor inside RADIUS - 10.
WorldBorder.RADIUS = 292
WorldBorder.WALL_SEGMENTS = 48
WorldBorder.WALL_THICKNESS = 4
WorldBorder.WALL_HEIGHT = 80 -- a default jump is ~7.2 studs
WorldBorder.WALL_OVERLAP = 1 -- extra length past the outer polygon corner
WorldBorder.MAX_AXIS = 64 -- v17 decor (CONTRACT §10): no axis over 64 studs

-- Corner groves: the old chunk meshes (shared/modeling-kit
-- models/ranch_border_chunk_*.py), each with a mirrored "_m" twin (a
-- MeshPart can't take a negative scale). Front (-Y in the kit) faces the map.
WorldBorder.CHUNKS = table.freeze({
	{ kind = "HillRocks", mesh = "ranch_border_chunk_b", corner = 2 },
	{ kind = "PineGrove", mesh = "ranch_border_chunk_d", corner = 2 },
	{ kind = "CornerGrove", mesh = "ranch_border_chunk_h", corner = 4 },
} :: { Chunk })
WorldBorder.CORNER_CHUNKS = 1 -- per Ground corner
WorldBorder.CORNER_SCALE = { 0.85, 1.0 }
WorldBorder.CORNER_TUCK = 24 -- corner groves start this far past the wall, over the back of the hills

-- Scatter pieces (shared/modeling-kit models/ranch_border_*.py). Footprints
-- are shallow (fence 3, hedge 5, trees 9-16) so the layers fit the 28 studs
-- of ground past the wall on the axes; only the hills are deep.
WorldBorder.DEFS = table.freeze({
	{
		kind = "Fence",
		mesh = "ranch_border_fence_straight",
		layer = "inner",
		weights = { all = 2.4 },
		scale = { 1, 1.4 },
		turn = 7,
	},
	{
		kind = "HedgeLong",
		mesh = "ranch_border_hedge_long",
		layer = "inner",
		weights = { all = 3 },
		scale = { 1, 1.4 },
		turn = 6,
	},
	{
		kind = "HedgeRound",
		mesh = "ranch_border_hedge_round",
		layer = "inner",
		weights = { all = 0.8 },
		scale = { 1, 1.5 },
		turn = 6,
	},
	{
		kind = "FenceLong",
		mesh = "ranch_border_fence_long",
		layer = "inner",
		weights = { all = 3.2 },
		scale = { 1, 1.2 },
		turn = 5,
	},
	{
		kind = "HedgeXL",
		mesh = "ranch_border_hedge_xl",
		layer = "inner",
		weights = { all = 3.2 },
		scale = { 1, 1.25 },
		turn = 5,
	},
	{
		kind = "PineTall",
		mesh = "ranch_border_pine_tall",
		layer = "mid",
		weights = { pines = 3, meadow = 0.3, rocky = 0.6 },
		scale = { 0.9, 1.45 },
		turn = 180,
	},
	{
		kind = "PineBroad",
		mesh = "ranch_border_pine_broad",
		layer = "mid",
		weights = { pines = 2.5, meadow = 0.6 },
		scale = { 0.9, 1.5 },
		turn = 180,
	},
	{
		kind = "Oak",
		mesh = "ranch_border_oak_round",
		layer = "mid",
		weights = { pines = 0.4, meadow = 3 },
		scale = { 0.9, 1.45 },
		turn = 180,
	},
	{
		kind = "Saplings",
		mesh = "ranch_border_sapling_trio",
		layer = "mid",
		weights = { pines = 1.5, meadow = 2, rocky = 1 },
		scale = { 0.95, 1.5 },
		turn = 180,
	},
	{
		kind = "Boulder",
		mesh = "ranch_border_rock_boulder",
		layer = "mid",
		weights = { pines = 0.5, meadow = 1, rocky = 2 },
		scale = { 0.7, 1.5 },
		turn = 180,
	},
	{
		kind = "Slab",
		mesh = "ranch_border_rock_slab",
		layer = "mid",
		weights = { pines = 0.3, meadow = 1.2, rocky = 1.5 },
		scale = { 0.75, 1.5 },
		turn = 180,
	},
	{
		kind = "RockHeap",
		mesh = "ranch_border_rock_cluster",
		layer = "mid",
		weights = { meadow = 0.3, rocky = 2.5 },
		scale = { 0.75, 1.4 },
		turn = 180,
	},
	{
		kind = "GrovePine",
		mesh = "ranch_border_grove_pine",
		layer = "mid",
		weights = { pines = 12, meadow = 3, rocky = 3 },
		scale = { 1, 1.35 },
		turn = 15,
	},
	{
		kind = "GroveMixed",
		mesh = "ranch_border_grove_mixed",
		layer = "mid",
		weights = { pines = 4, meadow = 12, rocky = 1.5 },
		scale = { 1, 1.35 },
		turn = 15,
	},
	{
		kind = "GroveRocky",
		mesh = "ranch_border_grove_rocky",
		layer = "mid",
		weights = { pines = 3, meadow = 3, rocky = 11 },
		scale = { 1, 1.35 },
		turn = 15,
	},
	{
		kind = "HillRidge",
		mesh = "ranch_border_hill_ridge",
		layer = "outer",
		weights = { all = 2 },
		scale = { 0.85, 1.1 },
		turn = 30,
	},
	{
		kind = "HillDome",
		mesh = "ranch_border_hill_dome",
		layer = "outer",
		weights = { all = 1.5 },
		scale = { 0.85, 1.0 },
		turn = 35,
	},
	{
		kind = "HillTwin",
		mesh = "ranch_border_hill_twin",
		layer = "outer",
		weights = { all = 1.6 },
		scale = { 0.85, 1.15 },
		turn = 30,
	},
} :: { Def })

-- Layers, innermost first. base = mean offset past the wall (sets the arc
-- length it is walked at), cap = most pieces, gap = studs between
-- neighbours along the edge (< 0 overlaps), o = offset of a piece's inner
-- edge past the wall line (a piece is pulled in to stay on the Ground).
WorldBorder.LAYERS = table.freeze({
	inner = { base = 4, cap = 28, gap = { -1.5, 2.5 }, o = { 0.5, 2.5 }, opening = { 8, 22 }, openingChance = 0.1 },
	mid = { base = 14, cap = 32, gap = { -4, 1 }, o = { 5, 22 }, open = { 20, 80 }, cluster = { 3, 6 } },
	outer = { base = 34, cap = 8, gap = { 30, 120 }, o = { 14, 40 } },
})
WorldBorder.THEMES = table.freeze({
	{ name = "pines", weight = 4 },
	{ name = "meadow", weight = 3 },
	{ name = "rocky", weight = 2 },
})
-- Giants (border v5 + v6): six NEW tree meshes (shared/modeling-kit models/giant_*.py: the v5 three at
-- 78-87 studs native, the v6 elder oak, sequoia spire and cloud tree at 100-160; the border pines are
-- 25 native, 22-36 placed) scaled to 90-215 studs, set on the terrain in three overlapping radial depth
-- bands with irregular gaps round the ring. Each is one MeshAsset slot (BORDER_SLOT_COUNT 72 + GIANT_COUNT).
WorldBorder.GIANT_COUNT = 30
WorldBorder.GIANT_MAX_AXIS = 215
-- Studs past the Ground edge, along the bearing: near the hills, mid, and far
-- (still ahead of the mountains' feet, which start PEAK_CLEAR past the edge). The bands overlap, so the
-- depths of neighbours never fall into three obvious rows.
WorldBorder.GIANT_BANDS = table.freeze({ { 34, 74 }, { 66, 124 }, { 112, 176 } })
WorldBorder.GIANT_TILT = 4 -- degrees, most lean about each horizontal axis
WorldBorder.GIANT_CLEAR = 10 -- studs of canopy clearance between a giant's reach and the wall ring
WorldBorder.GIANT_SINK = 1.5 -- studs the trunk base is set below the terrain
WorldBorder.GIANT_GAP = { 0.45, 1.55 } -- neighbour gap, in sectors (360 / GIANT_COUNT); the ring is rescaled to close
WorldBorder.GIANT_TRUNK_ROOM = 34 -- studs: no two trunks closer than this (the later one is pushed out)
WorldBorder.GIANT_SPECIES_WINDOW = 3 -- no species repeats within this many neighbours, the ring's seam included
-- MeshPart.Color multiplies the vertex colours (MeshSwap copies the slot colour when the slot has the
-- MeshTint attribute). v6: six canopy moods, further apart than v5's (every pair >= GIANT_TINT_APART apart
-- in RGB) and none bluer than it is green, so no purple or cold cast in the aerial; each rolled only a little off.
WorldBorder.GIANT_TINT_APART = 45
WorldBorder.GIANT_TINTS = table.freeze({
	{ 255, 255, 255 }, -- as modelled
	{ 206, 255, 160 }, -- fresh lime
	{ 255, 238, 150 }, -- butter gold
	{ 255, 198, 122 }, -- amber
	{ 168, 224, 150 }, -- sage
	{ 128, 196, 112 }, -- deep meadow
})
WorldBorder.GIANT_DEFS = table.freeze({
	{ kind = "GiantBroadleaf", mesh = "giant_broadleaf", scale = { 1.15, 1.6 } },
	{ kind = "GiantPine", mesh = "giant_pine_layered", scale = { 1.05, 1.45 } },
	{ kind = "GiantRound", mesh = "giant_round_canopy", scale = { 1.12, 1.55 } },
	{ kind = "GiantElderOak", mesh = "giant_elder_oak", scale = { 0.85, 1.2 } },
	{ kind = "GiantSequoia", mesh = "giant_sequoia_spire", scale = { 0.95, 1.3 } },
	{ kind = "GiantCloud", mesh = "giant_cloud_tree", scale = { 0.9, 1.25 } },
})
WorldBorder.WINDOW = 4 -- no run of this many pieces repeats its (mesh, rotation, scale) pattern
WorldBorder.ROT_BUCKET = 30 -- degrees
WorldBorder.SCALE_BUCKETS = 4
WorldBorder.SPILL = 1.5 -- studs a footprint may hang over the Ground

-- Uploaded ranch props mixed into the inner layer as accents:
-- ACCENT_COUNT of them, each mesh once.
WorldBorder.ACCENTS = table.freeze({
	"ranch_windmill",
	"ranch_scarecrow",
	"ranch_sunflower_patch",
	"ranch_pumpkin_patch",
	"ranch_log_pile",
	"ranch_fence_stile",
})
WorldBorder.ACCENT_COUNT = 4
WorldBorder.ACCENT_SPACING = 60 -- degrees between accents, at least

local HILL = { 108, 172, 90 }
local FOLIAGE = { 88, 150, 80 }
local WOOD = { 150, 104, 68 }

local function native(mesh: string): Vec
	local entry = MeshAssets.get(mesh)
	assert(entry and entry.size, `MeshAssets has no size for {mesh}`)
	return entry.size :: Vec
end

local function lerp(range: { number }, t: number): number
	return range[1] + (range[2] - range[1]) * t
end

local function polar(angle: number, r: number, y: number): Vec
	local a = math.rad(angle)
	return { math.sin(a) * r, y, math.cos(a) * r }
end

-- Farthest distance from the centre that is still on the square Ground.
function WorldBorder.groundRadius(angle: number): number
	local a = math.rad(angle)
	return WorldBorder.GROUND_HALF / math.max(math.abs(math.sin(a)), math.abs(math.cos(a)))
end

-- Walls ------------------------------------------------------------------

function WorldBorder.colliders(): { Collider }
	local n, t = WorldBorder.WALL_SEGMENTS, WorldBorder.WALL_THICKNESS
	local h, r = WorldBorder.WALL_HEIGHT, WorldBorder.RADIUS
	-- Polygon side at the OUTER face, so neighbours still meet at the
	-- outside corner (they overlap on the inside).
	local length = 2 * (r + t) * math.tan(math.pi / n) + WorldBorder.WALL_OVERLAP
	local out = {}
	for k = 0, n - 1 do
		local angle = k * 360 / n
		table.insert(out, { pos = polar(angle, r + t / 2, h / 2), size = { length, h, t }, yaw = angle })
	end
	return out
end

-- Pieces -----------------------------------------------------------------

local function newPiece(kind: string, mesh: string, row: string, scale: number, mirrored: boolean): Piece
	local name = if mirrored then mesh .. "_m" else mesh
	local n = native(name)
	-- Wide pieces stay within MAX_AXIS whatever the roll.
	scale = math.min(scale, WorldBorder.MAX_AXIS / math.max(n[1], n[2], n[3]))
	local size = { n[1] * scale, n[2] * scale, n[3] * scale }
	return {
		kind = kind,
		mesh = name,
		row = row,
		order = 0,
		turn = 0,
		rotBucket = 0,
		scaleBucket = 0,
		angle = 0,
		radius = 0,
		pos = { 0, size[2] / 2, 0 },
		size = size,
		yaw = 0,
		scale = scale,
		mirrored = mirrored,
		uploaded = MeshAssets.meshId(name) ~= nil,
	}
end

local function place(p: Piece, angle: number, r: number)
	p.angle = angle % 360
	p.radius = r
	p.pos = polar(p.angle, r, p.size[2] / 2)
end

-- Footprint corners on the ground plane (x, z), slot turned p.yaw.
function WorldBorder.corners(p: Piece): { Vec }
	local m = LayoutMath.orientation({ 0, p.yaw, 0 })
	local out = {}
	for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local v = LayoutMath.apply(m, { s[1] * p.size[1] / 2, 0, s[2] * p.size[3] / 2 })
		table.insert(out, { p.pos[1] + v[1], 0, p.pos[3] + v[3] })
	end
	return out
end

-- Studs the footprint's worst corner sticks out past the square Ground.
local function overhang(p: Piece): number
	local worst = -math.huge
	for _, c in WorldBorder.corners(p) do
		worst = math.max(worst, math.abs(c[1]) - WorldBorder.GROUND_HALF, math.abs(c[3]) - WorldBorder.GROUND_HALF)
	end
	return worst
end

-- Pulls the slot in along its bearing until at most `spill` studs hang over.
local function clampToGround(p: Piece, spill: number, floor: number)
	while overhang(p) > spill and p.radius - 0.5 >= floor do
		place(p, p.angle, p.radius - 0.5)
	end
end

-- Radial half extent of a slot turned `turn` degrees from tangential.
local function radialHalf(size: Vec, turn: number): number
	local a = math.rad(turn)
	return (math.abs(math.sin(a)) * size[1] + math.abs(math.cos(a)) * size[3]) / 2
end

-- Half extent along the edge of a slot turned `turn` degrees.
local function tangentHalf(size: Vec, turn: number): number
	local a = math.rad(turn)
	return (math.abs(math.cos(a)) * size[1] + math.abs(math.sin(a)) * size[3]) / 2
end

-- Studs of Ground past the wall line: the least over `half` degrees either
-- side of `angle` (the Ground is narrowest on the axes).
local function groundDepth(angle: number, half: number): number
	local least = math.huge
	for i = -2, 2 do
		least = math.min(least, WorldBorder.groundRadius(angle + half * i / 2))
	end
	if math.abs(angle - math.floor((angle + 45) / 90) * 90) <= half then
		least = math.min(least, WorldBorder.GROUND_HALF)
	end
	return least - WorldBorder.RADIUS
end

local function bucketOfTurn(turn: number): number
	return math.floor(((turn + 180) % 360) / WorldBorder.ROT_BUCKET)
end

local function signature(p: Piece): string
	return `{p.mesh}|{p.rotBucket}|{p.scaleBucket}`
end

-- One piece of `def` with its own scale and turn.
local function roll(rng: Rng.Rng, def: Def): Piece
	local p = newPiece(def.kind, def.mesh, def.layer, lerp(def.scale, rng:float()), false)
	p.turn = (rng:float() * 2 - 1) * def.turn
	p.rotBucket = bucketOfTurn(p.turn)
	local t = (p.scale - def.scale[1]) / (def.scale[2] - def.scale[1])
	p.scaleBucket = math.max(0, math.min(WorldBorder.SCALE_BUCKETS - 1, math.floor(t * WorldBorder.SCALE_BUCKETS)))
	return p
end

type Draft = { piece: Piece, def: Def?, gap: number, o: number }

local function advance(prev: Draft, d: Draft): number
	return tangentHalf(prev.piece.size, prev.piece.turn) + d.gap + tangentHalf(d.piece.size, d.piece.turn)
end

-- Walks one layer round the ring: the sequence of pieces with their gaps
-- and radial offsets, in arc order. Never repeats a piece's design within
-- two neighbours, and never completes a WINDOW-run pattern seen before.
local function draftLayer(rng: Rng.Rng, name: string): ({ Draft }, number)
	local cfg = (WorldBorder.LAYERS :: any)[name]
	local circumference = 2 * math.pi * (WorldBorder.RADIUS + cfg.base)
	local W = WorldBorder.WINDOW
	local defs: { Def } = {}
	for _, d in WorldBorder.DEFS do
		if d.layer == name then
			table.insert(defs, d)
		end
	end
	local themeWeights = {}
	for i, t in WorldBorder.THEMES do
		themeWeights[i] = t.weight
	end
	local drafts: { Draft } = {}
	local sigs: { string } = {}
	local seen: { [string]: boolean } = {}
	local total = 0
	local last, beforeLast = 0, 0
	local uses: { number } = {}
	local left, theme = 0, "all"
	local accentsLeft = if name == "inner" then WorldBorder.ACCENT_COUNT else 0
	local accentPool = table.clone(WorldBorder.ACCENTS) :: { string }
	local nextAccent = (0.3 + rng:float() * 0.4) * WorldBorder.ACCENT_SPACING
	while total < circumference and #drafts < cfg.cap do
		local gap = lerp(cfg.gap, rng:float())
		if cfg.opening and rng:float() < cfg.openingChance then
			gap += lerp(cfg.opening, rng:float())
		end
		if cfg.cluster then
			if left == 0 then
				theme = WorldBorder.THEMES[Rng.weightedIndex(themeWeights, rng:float())].name
				left = rng:int(cfg.cluster[1], cfg.cluster[2])
				if #drafts > 0 then
					gap = lerp(cfg.open, rng:float())
				end
			end
			left -= 1
		end
		local draft: Draft
		if accentsLeft > 0 and total / circumference * 360 >= nextAccent then
			local mesh = table.remove(accentPool, rng:int(1, #accentPool)) :: string
			local p = newPiece("Accent", mesh, name, lerp({ 1.15, 1.5 }, rng:float()), false)
			p.turn = (rng:float() * 2 - 1) * 10
			p.rotBucket = bucketOfTurn(p.turn)
			p.scaleBucket =
				math.min(WorldBorder.SCALE_BUCKETS - 1, math.floor((p.scale - 1.15) / 0.35 * WorldBorder.SCALE_BUCKETS))
			draft = { piece = p, def = nil, gap = 0.5 + rng:float() * 1.5, o = lerp({ 2, 6 }, rng:float()) }
			accentsLeft -= 1
			nextAccent = total / circumference * 360 + WorldBorder.ACCENT_SPACING * (1 + rng:float() * 0.6)
		else
			local weights = {}
			local any = 0
			for i, d in defs do
				local w = d.weights[theme] or d.weights.all or 0
				-- never the design of either of the two before it (just the
				-- last one when there are too few designs to dodge both)
				if i == last or (#defs > 3 and i == beforeLast) then
					w = 0
				end
				-- a design not yet on this layer is three times as likely
				weights[i] = if (uses[i] or 0) == 0 then w * 3 else w
				any += w
			end
			if any <= 0 then
				for i, d in defs do
					weights[i] = if i == last then 0 else d.weights[theme] or d.weights.all or 0.1
				end
			end
			local i, p
			for _ = 1, 40 do
				i = Rng.weightedIndex(weights, rng:float())
				p = roll(rng, defs[i])
				if #sigs < W - 1 then
					break
				end
				local key = table.concat(sigs, "/", #sigs - W + 2, #sigs) .. "/" .. signature(p)
				if not seen[key] then
					break
				end
			end
			beforeLast, last = last, i
			uses[i] = (uses[i] or 0) + 1
			draft = { piece = p, def = defs[i], gap = gap, o = lerp(cfg.o, rng:float()) }
		end
		local prev = drafts[#drafts]
		if prev then
			total += advance(prev, draft)
		end
		table.insert(drafts, draft)
		table.insert(sigs, signature(draft.piece))
		if #sigs >= W then
			seen[table.concat(sigs, "/", #sigs - W + 1, #sigs)] = true
		end
	end
	-- Windows across the seam (the last pieces followed by the first) must be
	-- new too: re-roll the last piece until they are.
	local n = #drafts
	local lastDraft = drafts[n]
	if n > W and lastDraft.def then
		for _ = 1, 40 do
			local clash = false
			for start = n - W + 2, n do
				local run = {}
				for j = 0, W - 1 do
					table.insert(run, sigs[(start + j - 1) % n + 1])
				end
				if seen[table.concat(run, "/")] then
					clash = true
				end
			end
			if not clash then
				break
			end
			local p = roll(rng, lastDraft.def)
			lastDraft.piece = p
			sigs[n] = signature(p)
		end
	end
	return drafts, circumference
end

-- Spreads a layer's drafts round the ring (closing the loop: every advance
-- is scaled so the last piece meets the first), turns each to face the
-- map, and keeps it on the Ground.
local function placeLayer(rng: Rng.Rng, name: string, drafts: { Draft }, circumference: number): { Piece }
	local R = WorldBorder.RADIUS
	local cfg = (WorldBorder.LAYERS :: any)[name]
	local first, final = drafts[1], drafts[#drafts]
	local total = 0
	for i = 2, #drafts do
		total += advance(drafts[i - 1], drafts[i])
	end
	total += tangentHalf(final.piece.size, final.piece.turn) + first.gap + tangentHalf(
		first.piece.size,
		first.piece.turn
	)
	local k = circumference / total
	-- A layer cut short by its cap (fewer slots than the ring needs) has ring
	-- left over. Clustered layers hand it to the open ground between
	-- clusters, so a grove stays a grove; the others stretch every advance.
	local extra: { number } = {}
	if cfg.cluster and k > 1 then
		local openTotal = 0
		for i = 2, #drafts do
			openTotal += math.max(0, drafts[i].gap - cfg.open[1] * 0.5)
		end
		if openTotal > 0 then
			for i = 2, #drafts do
				extra[i] = math.max(0, drafts[i].gap - cfg.open[1] * 0.5) / openTotal * (circumference - total)
			end
			extra[1] = math.max(0, first.gap - cfg.open[1] * 0.5) / openTotal * (circumference - total)
			k = 1
		end
	end
	local start = rng:float() * 360
	local s = 0
	local pieces = {}
	for idx, d in drafts do
		if idx > 1 then
			s += advance(drafts[idx - 1], d) * k + (extra[idx] or 0)
		end
		local p = d.piece
		p.order = idx
		local angle = start + s / circumference * 360
		-- Kit fronts face Roblox +Z: turn 180 so the front faces the centre.
		p.yaw = (angle + 180 + p.turn) % 360
		local half = radialHalf(p.size, p.turn)
		local span = math.deg(tangentHalf(p.size, p.turn) / (R + cfg.base))
		local room = groundDepth(angle % 360, span) + WorldBorder.SPILL - 2 * half
		place(p, angle, R + math.max(0, math.min(d.o, room)) + half)
		-- a hill's rim is low and tapered: it may reach back over the wall line
		clampToGround(p, 2, R + half * (if name == "outer" then 0.55 else 1))
		table.insert(pieces, p)
	end
	return pieces
end

-- Corner groves: CORNER_CHUNKS per Ground corner, deep in the square past
-- the hills, either side of the diagonal. The placements are the corner set
-- (every chunk design, then mirrored twins) dealt out in order.
local function cornerRow(rng: Rng.Rng): { Piece }
	-- One plain piece of every design first (so a short corner set still shows
	-- each design), shuffled; then the mirrored twins, the design with the most
	-- placements first.
	local set: { { def: Chunk, mirrored: boolean } } = {}
	for _, c in WorldBorder.CHUNKS do
		table.insert(set, { def = c, mirrored = false })
	end
	for i = #set, 2, -1 do
		local j = rng:int(1, i)
		set[i], set[j] = set[j], set[i]
	end
	local twins = table.clone(WorldBorder.CHUNKS :: { Chunk })
	table.sort(twins, function(x, y)
		return x.corner > y.corner
	end)
	for _, c in twins do
		table.insert(set, { def = c, mirrored = true })
	end
	local out = {}
	for corner = 0, 3 do
		local diagonal = 45 + corner * 90
		local side = if rng:float() < 0.5 then -1 else 1
		for k = 1, WorldBorder.CORNER_CHUNKS do
			local pick = set[corner * WorldBorder.CORNER_CHUNKS + k]
			local def = pick.def
			local p = newPiece(def.kind, def.mesh, "corner", lerp(WorldBorder.CORNER_SCALE, rng:float()), pick.mirrored)
			-- Alternate sides of the diagonal, 3-8 degrees off it (the corner is a narrow wedge).
			local angle = diagonal + side * (3 + rng:float() * 5)
			side = -side
			p.turn = (rng:float() * 2 - 1) * 12
			p.yaw = (angle + 180 + p.turn) % 360
			local inner = WorldBorder.RADIUS + WorldBorder.CORNER_TUCK + p.size[3] / 2
			place(p, angle, inner + (WorldBorder.groundRadius(angle) - inner) * (0.1 + rng:float() * 0.5))
			clampToGround(p, 1, inner)
			table.insert(out, p)
		end
	end
	return out
end

-- Giants: GIANT_COUNT huge trees round the ring. Species and tints are dealt from shuffled decks (every species
-- about equally often) and re-dealt until no species repeats within GIANT_SPECIES_WINDOW neighbours and no tint
-- within two, seam included; the gaps between neighbours roll anywhere in GIANT_GAP sectors (rescaled so the ring
-- closes) and the depth bands are rolled independently, never the same band three in a row, so no period shows
-- from the eye camera or the aerial. Each stands on the border terrain (lowest of five footprint samples, sunk
-- GIANT_SINK so no root floats), leans a few degrees and wears its own tint; a trunk closer than GIANT_TRUNK_ROOM
-- to an earlier one is pushed outward.
local function dealDeck(rng: Rng.Rng, count: number, kinds: number, window: number): { number }
	for _ = 1, 400 do
		local left: { number } = {}
		for k = 1, kinds do
			left[k] = math.floor(count / kinds) + (if k <= count % kinds then 1 else 0)
		end
		local deck: { number } = {}
		local stuck = false
		for k = 1, count do
			local options: { number } = {}
			for kind = 1, kinds do
				local clash = left[kind] == 0
				for j = 1, window - 1 do
					-- the last window - 1 dealt, and for the final positions the first ones too (the seam)
					if deck[k - j] == kind or (k > count - window + 1 and deck[k + j - count] == kind) then
						clash = true
					end
				end
				if not clash then
					table.insert(options, kind)
				end
			end
			if #options == 0 then
				stuck = true
				break
			end
			local pick = options[rng:int(1, #options)]
			left[pick] -= 1
			deck[k] = pick
		end
		if not stuck then
			return deck
		end
	end
	error("WorldBorder.giants: no deal found")
end

function WorldBorder.giants(seed: number?): { Piece }
	local rng = Rng.new((seed or WorldBorder.SEED) + 15485863)
	local field = BorderTerrain.field()
	local count = WorldBorder.GIANT_COUNT
	local defs = WorldBorder.GIANT_DEFS
	local bands = WorldBorder.GIANT_BANDS
	local tilt = WorldBorder.GIANT_TILT
	local order = dealDeck(rng, count, #defs, WorldBorder.GIANT_SPECIES_WINDOW)
	local moods = dealDeck(rng, count, #WorldBorder.GIANT_TINTS, 3)
	-- irregular gaps that still close the ring
	local gaps: { number } = {}
	local total = 0
	for k = 1, count do
		gaps[k] = lerp(WorldBorder.GIANT_GAP, rng:float())
		total += gaps[k]
	end
	local start = rng:float() * 360
	local walked = 0
	local bandOf: { number } = {}
	for k = 1, count do
		local b
		repeat
			b = rng:int(1, #bands)
		until not (k > 2 and bandOf[k - 1] == b and bandOf[k - 2] == b)
		bandOf[k] = b
	end
	local out: { Piece } = {}
	local placed: { { number } } = {}
	for k = 1, count do
		local def = defs[order[k]]
		local n = native(def.mesh)
		local scale = math.min(lerp(def.scale, rng:float()), WorldBorder.GIANT_MAX_AXIS / math.max(n[1], n[2], n[3]))
		local size = { n[1] * scale, n[2] * scale, n[3] * scale }
		walked += gaps[k]
		local angle = start + (walked - gaps[k] * (0.2 + 0.6 * rng:float())) / total * 360
		local band = bandOf[k]
		local r = WorldBorder.groundRadius(angle) + lerp(bands[band], rng:float())
		-- the canopy never hangs over the walls
		r = math.max(
			r,
			WorldBorder.RADIUS + WorldBorder.WALL_THICKNESS + WorldBorder.GIANT_CLEAR + math.max(size[1], size[3]) / 2
		)
		local x, z = 0, 0
		for _ = 1, 8 do
			x, z = polar(angle, r, 0)[1], polar(angle, r, 0)[3]
			local crowded = false
			for _, q in placed do
				if math.sqrt((q[1] - x) ^ 2 + (q[2] - z) ^ 2) < WorldBorder.GIANT_TRUNK_ROOM then
					crowded = true
				end
			end
			if not crowded then
				break
			end
			r += WorldBorder.GIANT_TRUNK_ROOM * 0.6
		end
		table.insert(placed, { x, z })
		local reach = math.min(size[1], size[3]) * 0.1
		local ground = math.huge
		for _, o in { { 0, 0 }, { reach, 0 }, { -reach, 0 }, { 0, reach }, { 0, -reach } } do
			ground = math.min(ground, field.height(x + o[1], z + o[2]))
		end
		local turn = (rng:float() * 2 - 1) * 180
		local mood = WorldBorder.GIANT_TINTS[moods[k]]
		local fade = 1 - rng:float() * 0.05
		local p: Piece = {
			kind = def.kind,
			mesh = def.mesh,
			row = "giant",
			order = k,
			turn = turn,
			rotBucket = bucketOfTurn(turn),
			scaleBucket = 0,
			angle = angle % 360,
			radius = r,
			pos = { x, ground - WorldBorder.GIANT_SINK + size[2] / 2, z },
			size = size,
			yaw = (angle + 180 + turn) % 360,
			scale = scale,
			mirrored = false,
			uploaded = MeshAssets.meshId(def.mesh) ~= nil,
			tilt = { (rng:float() * 2 - 1) * tilt, (rng:float() * 2 - 1) * tilt },
			tint = { math.floor(mood[1] * fade), math.floor(mood[2] * fade), math.floor(mood[3] * fade) },
			band = band,
		}
		table.insert(out, p)
	end
	return out
end

function WorldBorder.pieces(seed: number?): { Piece }
	local base = seed or WorldBorder.SEED
	local all: { Piece } = {}
	for i, name in { "inner", "mid", "outer" } do
		local rng = Rng.new(base + i * 7919)
		local drafts, circumference = draftLayer(rng, name)
		for _, p in placeLayer(rng, name, drafts, circumference) do
			table.insert(all, p)
		end
	end
	for _, p in cornerRow(Rng.new(base + 104729)) do
		table.insert(all, p)
	end
	return all
end

-- Nodes ------------------------------------------------------------------

-- One MeshAsset slot per piece, never colliding. Chunk slots are invisible
-- until MeshSwap lands their mesh (a 55-stud primitive box would read as a
-- wall); accents keep a wood placeholder like the other ranch prop slots.
local function pieceNode(p: Piece, name: string): Node
	local accent = p.kind == "Accent"
	local tint = p.tint
	return {
		name = name,
		class = "Part",
		shape = "Block",
		size = p.size,
		pos = p.pos,
		rot = if p.tilt then { p.tilt[1], p.yaw, p.tilt[2] } else { 0, p.yaw, 0 },
		color = if accent then WOOD else tint or FOLIAGE,
		material = if accent then "WoodPlanks" else "Grass",
		transparency = if accent then nil else 1,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		attributes = if tint then { MeshAsset = p.mesh, MeshTint = true } else { MeshAsset = p.mesh },
	}
end

function WorldBorder.build(seed: number?): Node
	local walls: { Node } = {}
	for k, c in WorldBorder.colliders() do
		table.insert(walls, {
			name = `Wall{k}`,
			class = "Part",
			shape = "Block",
			size = c.size,
			pos = c.pos,
			rot = { 0, c.yaw, 0 },
			color = HILL,
			material = "SmoothPlastic",
			transparency = 1,
			canCollide = true,
			canQuery = false,
			canTouch = false,
		})
	end
	local decor: { Node } = {}
	local counts: { [string]: number } = {}
	for _, p in WorldBorder.pieces(seed) do
		counts[p.kind] = (counts[p.kind] or 0) + 1
		table.insert(decor, pieceNode(p, `{p.kind}{counts[p.kind]}`))
	end
	for _, p in WorldBorder.giants(seed) do
		counts[p.kind] = (counts[p.kind] or 0) + 1
		table.insert(decor, pieceNode(p, `{p.kind}{counts[p.kind]}`))
	end
	return {
		name = "Border",
		class = "Folder",
		children = {
			{ name = "Walls", class = "Folder", children = walls },
			{ name = "Decor", class = "Folder", children = decor },
		},
	}
end

return table.freeze(WorldBorder)
