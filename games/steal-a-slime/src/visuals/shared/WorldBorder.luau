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
	  Decor    border chunks: one kit mesh per ~55 studs of edge that already
	           combines hedge / rail fence / pines / hill / rocks / goo
	           (ranch_border_chunk_a..h, each with a mirrored "_m" twin, since
	           a MeshPart can't take a negative scale). A front row of chunks
	           (+ a few uploaded ranch props as accents) closes the ring just
	           outside the wall line, and CORNER_CHUNKS deep groves per Ground
	           corner fill the square past it (it reaches r 452 on the
	           diagonals). Design, mirror, scale, yaw jitter, spacing and inset
	           come from one Rng: every build is identical, no visible period.

	Decor never collides; the walls are the only collision. Every decor piece
	is one MeshAsset slot (MeshSwap skins it): ~43 slots, against ~228 when the
	edge was built from single hedges, fences and pines (THEME.md budget 400).
]]

local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")
local Rng = if script then require(script.Parent.Parent.Shared.Rng) else require("../../shared/Rng")

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
	row: string, -- "front" | "corner"
	angle: number, -- polar bearing in degrees (0 = +Z, 90 = +X)
	radius: number, -- slot centre distance from the map centre
	pos: Vec, -- slot centre; y = half height, so it stands on the ground
	size: Vec, -- native mesh size x scale
	yaw: number,
	scale: number,
	mirrored: boolean,
	uploaded: boolean, -- MeshAssets has a meshId (MeshSwap can skin the slot)
}

type Chunk = {
	kind: string,
	mesh: string, -- base design; "<mesh>_m" is its mirrored twin
	front: number, -- front-row weight
	corner: number, -- corner-grove weight
}

local WorldBorder = {}

WorldBorder.SEED = 20261016
WorldBorder.GROUND_HALF = 320 -- WorldLayout Ground is 640 x 640, centred
-- Inner face of the wall ring. The plots end at r ~197, the sheds at
-- ~253; WorldLayout keeps scattered decor inside RADIUS - 10.
WorldBorder.RADIUS = 292
WorldBorder.WALL_SEGMENTS = 48
WorldBorder.WALL_THICKNESS = 4
WorldBorder.WALL_HEIGHT = 80 -- a default jump is ~7.2 studs
WorldBorder.WALL_OVERLAP = 1 -- extra length past the outer polygon corner
WorldBorder.MAX_AXIS = 64 -- v17 decor (CONTRACT §10): no axis over 64 studs

-- Chunk designs (shared/modeling-kit models/ranch_border_chunk_*.py), each
-- ~53-57 studs along the edge. Front (-Y in the kit) faces the map.
WorldBorder.CHUNKS = table.freeze({
	{ kind = "HedgeFence", mesh = "ranch_border_chunk_a", front = 16, corner = 0 },
	{ kind = "HillRocks", mesh = "ranch_border_chunk_b", front = 14, corner = 2 },
	{ kind = "FenceMound", mesh = "ranch_border_chunk_c", front = 14, corner = 0 },
	{ kind = "PineGrove", mesh = "ranch_border_chunk_d", front = 14, corner = 3 },
	{ kind = "HedgeHill", mesh = "ranch_border_chunk_e", front = 14, corner = 0 },
	{ kind = "Outcrop", mesh = "ranch_border_chunk_f", front = 12, corner = 0 },
	{ kind = "SteppedFence", mesh = "ranch_border_chunk_g", front = 14, corner = 0 },
	{ kind = "CornerGrove", mesh = "ranch_border_chunk_h", front = 0, corner = 8 },
} :: { Chunk })
WorldBorder.FRONT_SCALE = { 1.0, 1.15 }
WorldBorder.FRONT_GAP = { -1, 1.5 } -- studs between neighbours along the edge (< 0 overlaps)
WorldBorder.FRONT_YAW_JITTER = 5
WorldBorder.FRONT_INSET = { -0.15, 0.2 } -- radial offset in slot half-depths past the wall line
WorldBorder.CORNER_CHUNKS = 2 -- per Ground corner
WorldBorder.CORNER_SCALE = { 0.95, 1.1 }
WorldBorder.CORNER_TUCK = 14 -- corner groves start this far past the wall, over the front row's back

-- Uploaded ranch props mixed into the front row as accents:
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
	-- Wide chunks stay within MAX_AXIS whatever the roll.
	scale = math.min(scale, WorldBorder.MAX_AXIS / math.max(n[1], n[2], n[3]))
	local size = { n[1] * scale, n[2] * scale, n[3] * scale }
	return {
		kind = kind,
		mesh = name,
		row = row,
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

type Draft = { piece: Piece, gap: number, yawJitter: number, inset: { number } }

local function frontRow(rng: Rng.Rng): { Piece }
	local R = WorldBorder.RADIUS
	local circumference = 2 * math.pi * R
	local weights = {}
	for i, c in WorldBorder.CHUNKS do
		weights[i] = c.front
	end
	-- 1. The sequence, with each piece's nominal advance along the edge.
	local drafts: { Draft } = {}
	local total, lastKind, kindBefore = 0, 0, 0
	local hands: { boolean } = {} -- mirrored flag of every chunk so far
	local accentsLeft = WorldBorder.ACCENT_COUNT
	local accentPool = table.clone(WorldBorder.ACCENTS) :: { string }
	local nextAccent = (0.3 + rng:float() * 0.4) * WorldBorder.ACCENT_SPACING
	-- total = sum of centre-to-centre advances so far (the first piece has none).
	local function push(d: Draft)
		local prev = drafts[#drafts]
		if prev then
			total += prev.piece.size[1] / 2 + d.gap + d.piece.size[1] / 2
		end
		table.insert(drafts, d)
	end
	while total < circumference do
		local here = total / circumference * 360
		if accentsLeft > 0 and here >= nextAccent then
			local mesh = table.remove(accentPool, rng:int(1, #accentPool)) :: string
			local p = newPiece("Accent", mesh, "front", 1.15 + rng:float() * 0.35, false)
			push({ piece = p, gap = 0.5 + rng:float() * 1.5, yawJitter = 10, inset = { 0.1, 0.5 } })
			accentsLeft -= 1
			nextAccent = here + WorldBorder.ACCENT_SPACING * (1 + rng:float() * 0.6)
		else
			-- Never the design of either of the two chunks before it, so any
			-- three neighbours are three different designs.
			local i
			repeat
				i = Rng.weightedIndex(weights, rng:float())
			until i ~= lastKind and i ~= kindBefore
			kindBefore, lastKind = lastKind, i
			-- Mirror is a coin flip, but never three of one hand in a row.
			local mirrored = rng:float() < 0.5
			local n = #hands
			if n >= 2 and hands[n] == hands[n - 1] then
				mirrored = not hands[n]
			end
			table.insert(hands, mirrored)
			local def = WorldBorder.CHUNKS[i]
			local p = newPiece(def.kind, def.mesh, "front", lerp(WorldBorder.FRONT_SCALE, rng:float()), mirrored)
			push({
				piece = p,
				gap = lerp(WorldBorder.FRONT_GAP, rng:float()),
				yawJitter = WorldBorder.FRONT_YAW_JITTER,
				inset = WorldBorder.FRONT_INSET,
			})
		end
	end
	-- 2. Close the loop: scale every advance so the last piece meets the
	-- first (closing advance = last half + first gap + first half).
	local first, final = drafts[1], drafts[#drafts]
	total += final.piece.size[1] / 2 + first.gap + first.piece.size[1] / 2
	local k = circumference / total
	-- 3. Bearings, radii, yaws.
	local start = rng:float() * 360
	local s = 0
	local pieces = {}
	for idx, d in drafts do
		if idx > 1 then
			local prev = drafts[idx - 1]
			s += (prev.piece.size[1] / 2 + d.gap + d.piece.size[1] / 2) * k
		end
		local p = d.piece
		local jitter = (rng:float() * 2 - 1) * d.yawJitter
		-- Kit fronts face Roblox +Z: turn 180 so the front faces the centre.
		p.yaw = (start + s / circumference * 360 + 180 + jitter) % 360
		-- inset > 0 pushes the slot out past the wall line; < 0 lets its
		-- front reach over it (ghost decor: players brush into it, never onto it).
		local half = radialHalf(p.size, jitter)
		place(p, start + s / circumference * 360, R + half * (1 + 2 * lerp(d.inset, rng:float())))
		clampToGround(p, 2, R - half)
		table.insert(pieces, p)
	end
	return pieces
end

-- Corner groves: CORNER_CHUNKS per Ground corner, tucked over the back of
-- the front row (both are ghost decor), either side of the diagonal.
local function cornerRow(rng: Rng.Rng): { Piece }
	local weights, defs = {}, {}
	for _, c in WorldBorder.CHUNKS do
		if c.corner > 0 then
			table.insert(weights, c.corner)
			table.insert(defs, c)
		end
	end
	local out = {}
	for corner = 0, 3 do
		local diagonal = 45 + corner * 90
		local side = if rng:float() < 0.5 then -1 else 1
		for _ = 1, WorldBorder.CORNER_CHUNKS do
			local def = defs[Rng.weightedIndex(weights, rng:float())]
			local p =
				newPiece(def.kind, def.mesh, "corner", lerp(WorldBorder.CORNER_SCALE, rng:float()), rng:float() < 0.5)
			-- Alternate sides of the diagonal, 5-11 degrees off it.
			local angle = diagonal + side * (5 + rng:float() * 6)
			side = -side
			p.yaw = (angle + 180 + (rng:float() * 2 - 1) * 12) % 360
			local inner = WorldBorder.RADIUS + WorldBorder.CORNER_TUCK + p.size[3] / 2
			place(p, angle, inner + (WorldBorder.groundRadius(angle) - inner) * (0.1 + rng:float() * 0.5))
			clampToGround(p, 1, inner)
			table.insert(out, p)
		end
	end
	return out
end

function WorldBorder.pieces(seed: number?): { Piece }
	local rng = Rng.new(seed or WorldBorder.SEED)
	local all = frontRow(rng)
	for _, p in cornerRow(rng) do
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
	return {
		name = name,
		class = "Part",
		shape = "Block",
		size = p.size,
		pos = p.pos,
		rot = { 0, p.yaw, 0 },
		color = if accent then WOOD else FOLIAGE,
		material = if accent then "WoodPlanks" else "Grass",
		transparency = if accent then nil else 1,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		attributes = { MeshAsset = p.mesh },
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
