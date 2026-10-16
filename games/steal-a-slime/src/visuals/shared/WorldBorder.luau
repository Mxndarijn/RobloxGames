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
	  Decor    seeded-random pieces just outside the wall line: a front row
	           (hedges, log rail fences, pine clusters, hills, rock clusters
	           and a few uploaded ranch props as accents) and a back row of
	           pines and hills that also fills the Ground corners (the square
	           reaches r 452 on the diagonals). Kind, run length, scale, yaw
	           jitter, spacing and inset all come from one Rng: every build
	           is identical and there is no visible period.

	Decor never collides; the walls are the only collision. The new border
	meshes (KINDS[*].mesh) aren't uploaded and the map is at the MeshPart
	budget (THEME.md <= 150, tests/SlimeRanch.spec), so their slots carry
	BorderMesh = <name> instead of MeshAsset, with primitive stand-ins tagged
	MeshStandIn = <name>. Renaming BorderMesh to MeshAsset is the whole switch
	once the budget allows (MeshSwap then hides the stand-ins). Accents use
	already uploaded ranch meshes as real MeshAsset slots.
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
	mesh: string,
	row: string, -- "front" | "back"
	angle: number, -- polar bearing in degrees (0 = +Z, 90 = +X)
	radius: number, -- slot centre distance from the map centre
	pos: Vec, -- slot centre; y = half height, so it stands on the ground
	size: Vec, -- native mesh size x scale
	yaw: number,
	scale: number,
	uploaded: boolean, -- true: a MeshAsset slot (accent); false: BorderMesh
}

type Kind = {
	kind: string,
	mesh: string,
	front: number, -- front-row weight
	back: number, -- back-row weight
	scale: { number },
	run: { number }, -- how many of this kind in a row
	gap: { number }, -- studs between neighbours along the edge (< 0 overlaps)
	yawJitter: number,
	inset: { number }, -- radial offset in slot half-depths past the wall line
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

WorldBorder.KINDS = table.freeze({
	{
		kind = "Hedge",
		mesh = "ranch_hedge_segment",
		front = 26,
		back = 0,
		scale = { 0.9, 1.35 },
		run = { 1, 3 },
		gap = { -2.5, 0.5 },
		yawJitter = 7,
		inset = { -0.2, 0.6 },
	},
	{
		kind = "RailFence",
		mesh = "ranch_rail_fence",
		front = 16,
		back = 0,
		scale = { 0.95, 1.25 },
		run = { 1, 3 },
		gap = { -1.5, 0.5 },
		yawJitter = 9,
		inset = { 0, 0.5 },
	},
	{
		kind = "Pines",
		mesh = "ranch_pine_cluster",
		front = 20,
		back = 55,
		scale = { 0.85, 1.5 },
		run = { 1, 2 },
		gap = { -4, 1 },
		yawJitter = 180,
		inset = { -0.25, 0.9 },
	},
	{
		kind = "Hill",
		mesh = "ranch_border_hill",
		front = 14,
		back = 45,
		scale = { 0.8, 1.45 },
		run = { 1, 1 },
		gap = { -6, -1 },
		yawJitter = 14,
		inset = { -0.3, 0.5 },
	},
	{
		kind = "Rocks",
		mesh = "ranch_border_rocks",
		front = 16,
		back = 0,
		scale = { 0.75, 1.5 },
		run = { 1, 2 },
		gap = { -2, 2 },
		yawJitter = 180,
		inset = { -0.3, 0.8 },
	},
} :: { Kind })

-- Uploaded ranch props mixed into the front row as real MeshAsset slots
-- (they count in the 150 budget): ACCENT_COUNT of them, each mesh once.
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

local FOLIAGE = { 88, 150, 80 }
local FOLIAGE_LIGHT = { 118, 178, 96 }
local PINE = { 62, 128, 84 }
local HILL = { 108, 172, 90 }
local ROCK = { 196, 176, 146 }
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

local function newPiece(kind: string, mesh: string, row: string, scale: number): Piece
	local n = native(mesh)
	local size = { n[1] * scale, n[2] * scale, n[3] * scale }
	return {
		kind = kind,
		mesh = mesh,
		row = row,
		angle = 0,
		radius = 0,
		pos = { 0, size[2] / 2, 0 },
		size = size,
		yaw = 0,
		scale = scale,
		uploaded = MeshAssets.meshId(mesh) ~= nil,
	}
end

local function place(p: Piece, angle: number, r: number)
	p.angle = angle % 360
	p.radius = r
	p.pos = polar(p.angle, r, p.size[2] / 2)
end

-- Footprint radius (conservative: half the larger horizontal side).
local function reach(p: Piece): number
	return math.max(p.size[1], p.size[3]) / 2
end

-- Radial half extent of a slot turned `turn` degrees from tangential.
local function radialHalf(size: Vec, turn: number): number
	local a = math.rad(turn)
	return (math.abs(math.sin(a)) * size[1] + math.abs(math.cos(a)) * size[3]) / 2
end

-- Keeps the slot centre on the Ground, its footprint at most `spill` past the edge.
local function clampToGround(p: Piece, spill: number)
	local limit = WorldBorder.groundRadius(p.angle) - math.max(0, reach(p) - spill)
	if p.radius > limit then
		place(p, p.angle, limit)
	end
end

type Draft = { piece: Piece, gap: number, yawJitter: number, inset: { number } }

local function frontRow(rng: Rng.Rng): { Piece }
	local R = WorldBorder.RADIUS
	local circumference = 2 * math.pi * R
	local weights = {}
	for i, k in WorldBorder.KINDS do
		weights[i] = k.front
	end
	-- 1. The sequence, with each piece's nominal advance along the edge.
	local drafts: { Draft } = {}
	local total, lastKind, kindBefore = 0, 0, 0
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
			local p = newPiece("Accent", mesh, "front", 1.15 + rng:float() * 0.35)
			push({ piece = p, gap = 0.5 + rng:float() * 1.5, yawJitter = 10, inset = { 0.1, 0.5 } })
			accentsLeft -= 1
			nextAccent = here + WorldBorder.ACCENT_SPACING * (1 + rng:float() * 0.6)
		else
			-- A new run, never the kind of either of the two runs before it, so
			-- any 7 pieces in a row show at least three kinds.
			local i
			repeat
				i = Rng.weightedIndex(weights, rng:float())
			until i ~= lastKind and i ~= kindBefore
			kindBefore, lastKind = lastKind, i
			local def = WorldBorder.KINDS[i]
			for _ = 1, rng:int(def.run[1], def.run[2]) do
				local p = newPiece(def.kind, def.mesh, "front", lerp(def.scale, rng:float()))
				push({ piece = p, gap = lerp(def.gap, rng:float()), yawJitter = def.yawJitter, inset = def.inset })
			end
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
		clampToGround(p, 2)
		table.insert(pieces, p)
	end
	return pieces
end

-- Back row: pines and hills behind the front row, denser in the corners.
local function backRow(rng: Rng.Rng, front: { Piece }): { Piece }
	local weights, defs = {}, {}
	for _, k in WorldBorder.KINDS do
		if k.back > 0 then
			table.insert(weights, k.back)
			table.insert(defs, k)
		end
	end
	local placed: { Piece } = {}
	local function free(p: Piece): boolean
		for _, list in { front, placed } do
			for _, q in list do
				local d = math.sqrt((p.pos[1] - q.pos[1]) ^ 2 + (p.pos[3] - q.pos[3]) ^ 2)
				local need = (reach(p) + reach(q)) * (if q.row == "front" then 0.45 else 0.6)
				if d < need then
					return false
				end
			end
		end
		return true
	end
	for _ = 1, 260 do
		local angle = rng:float() * 360
		local def = defs[Rng.weightedIndex(weights, rng:float())]
		local p = newPiece(def.kind, def.mesh, "back", lerp(def.scale, rng:float()) * (1.05 + rng:float() * 0.25))
		local inner = WorldBorder.RADIUS + 10 + p.size[3] / 2
		local outer = WorldBorder.groundRadius(angle) - reach(p) + 2
		if outer > inner then
			local jitter = (rng:float() * 2 - 1) * def.yawJitter
			p.yaw = (angle + 180 + jitter) % 360
			-- Hug the front row; corners spread out towards the Ground edge.
			place(p, angle, inner + (outer - inner) * rng:float() ^ 1.6)
			local edge = math.max(math.abs(p.pos[1]), math.abs(p.pos[3])) + reach(p)
			if edge <= WorldBorder.GROUND_HALF + 2 and free(p) then
				table.insert(placed, p)
			end
		end
	end
	return placed
end

function WorldBorder.pieces(seed: number?): { Piece }
	local rng = Rng.new(seed or WorldBorder.SEED)
	local all = frontRow(rng)
	for _, p in backRow(rng, table.clone(all)) do
		table.insert(all, p)
	end
	return all
end

-- Nodes ------------------------------------------------------------------

local function ghost(name: string, size: Vec, pos: Vec, rot: Vec, color: Vec, material: string, shape: string?): Node
	return {
		name = name,
		class = "Part",
		shape = shape or "Block",
		size = size,
		pos = pos,
		rot = rot,
		color = color,
		material = material,
		canCollide = false,
		canQuery = false,
		canTouch = false,
	}
end

local function ball(name: string, d: number, pos: Vec, rot: Vec, color: Vec): Node
	return ghost(name, { d, d, d }, pos, rot, color, "Grass", "Ball")
end

-- Primitive stand-ins in the slot's own frame: x along the edge, y up from
-- the ground, z through the slot. Cheap on purpose (1-2 parts per piece).
local function standIns(p: Piece, at: (Vec) -> Vec, rot: Vec): { Node }
	local w, h, d = p.size[1], p.size[2], p.size[3]
	local nodes: { Node }
	if p.kind == "Hedge" then
		nodes = { ghost("Body", { w * 0.95, h * 0.9, d * 0.85 }, at({ 0, h * 0.45, 0 }), rot, FOLIAGE, "Grass") }
	elseif p.kind == "RailFence" then
		nodes = {}
		for k, y in { 0.33, 0.64 } do
			table.insert(nodes, ghost(`Rail{k}`, { w, h * 0.13, d * 0.4 }, at({ 0, h * y, 0 }), rot, WOOD, "Wood"))
		end
	elseif p.kind == "Pines" then
		local big, small = w * 0.5, w * 0.38
		nodes = {
			ball("CrownA", big, at({ -w * 0.18, h - big * 0.7, 0 }), rot, PINE),
			ball("CrownB", small, at({ w * 0.22, h * 0.62 - small / 2, -d * 0.1 }), rot, PINE),
		}
	elseif p.kind == "Hill" then
		-- Two sunk domes (cap radius d/2, cap height h and 0.7 h).
		nodes = {}
		for k, x in { -0.18, 0.26 } do
			local cap, a = h * (if k == 1 then 1 else 0.7), d / 2
			local r = (a * a + cap * cap) / (2 * cap)
			table.insert(
				nodes,
				ball(`Dome{k}`, r * 2, at({ x * w, cap - r, 0 }), rot, if k == 1 then HILL else FOLIAGE_LIGHT)
			)
		end
	else
		nodes =
			{ ghost("Boulder", { w * 0.65, h, d * 0.75 }, at({ 0, h / 2, 0 }), { 0, rot[2] + 17, 0 }, ROCK, "Rock") }
	end
	for _, node in nodes do
		node.attributes = { MeshStandIn = p.mesh }
	end
	return nodes
end

local function pieceNode(p: Piece, name: string): Node
	local rot = { 0, p.yaw, 0 }
	if p.uploaded then
		-- Uploaded ranch prop: a visible, non-colliding slot that MeshSwap skins.
		local slot = ghost(name, p.size, p.pos, rot, WOOD, "WoodPlanks")
		slot.attributes = { MeshAsset = p.mesh }
		return slot
	end
	local m = LayoutMath.orientation(rot)
	local base = { p.pos[1], 0, p.pos[3] }
	local function at(v: Vec): Vec
		return LayoutMath.add(base, LayoutMath.apply(m, v))
	end
	local slot = ghost("Slot", p.size, p.pos, rot, FOLIAGE, "SmoothPlastic")
	slot.transparency = 1
	slot.attributes = { BorderMesh = p.mesh }
	local children: { Node } = { slot }
	for _, node in standIns(p, at, rot) do
		table.insert(children, node)
	end
	return { name = name, class = "Model", primaryPart = "Slot", children = children }
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
