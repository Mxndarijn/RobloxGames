--!strict
--[[
	Meadow (owner: Archer)

	Meadow.clusters(clear): { Cluster }
	Meadow.build(clusters): Node   -- Map.Decor.Meadow

	Clustered wild-meadow decor for the grass band between the back of the
	plots (outer corners r ~185) and the WorldBorder (walls r 292): flowers,
	tall grass tufts and small rocks, all primitives (no mesh slots).
	Everything comes from one Rng (SEED), so every build is identical:
	cluster kind, size, spacing and position, and per piece scale, yaw, tilt
	and colour. Clusters are of several kinds with their own size ranges,
	sometimes spawn a small satellite cluster next to them (meadows grow in
	drifts, not on a grid), and keep a random gap from their neighbours.

	`clear(x, z, radius)` is the caller's keep-clear test (WorldLayout: plots,
	paths, entrances, props, prop spots, other decor); the band limits
	INNER..OUTER are applied here. The parade lane (r 64.75..71.25), ring
	path and spokes all sit far inside INNER.

	Decor only: nothing collides, is queried or touched. Every piece rests on
	(or sinks into) the Ground top at y = 0; tests/Meadow.spec checks that,
	the clearances and PART_BUDGET.
]]

local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
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

export type Cluster = {
	kind: string,
	x: number,
	z: number,
	radius: number, -- every piece's footprint stays inside this circle
	parts: { Node },
}

local Meadow = {}

Meadow.SEED = 20261017
Meadow.INNER = 192 -- past the plots' outer corners (r 184.4) and their fences
Meadow.OUTER = 270 -- cluster edge; the border's edge pieces start at r 290
Meadow.PART_BUDGET = 400 -- of WorldLayout.PART_BUDGET (1400)
Meadow.SECTORS = 26 -- cells per ring (two rings)
Meadow.LAWN = 0.12 -- chance a cell stays open lawn
Meadow.SATELLITE = 0.3 -- chance of a small drift beside a cluster

local STEM = { 92, 150, 64 }
local BLADES = { { 86, 150, 60 }, { 108, 172, 72 }, { 128, 170, 70 }, { 150, 176, 84 }, { 76, 136, 58 } }
local PETALS = {
	{ 250, 150, 182 }, -- pink
	{ 255, 214, 92 }, -- butter
	{ 248, 244, 236 }, -- daisy white
	{ 186, 150, 236 }, -- lavender
	{ 255, 136, 104 }, -- coral
	{ 120, 182, 246 }, -- cornflower
}
local STONES = { { 150, 140, 128 }, { 132, 120, 108 }, { 168, 160, 148 } }

-- Cluster kinds: pick weight, radius range, piece count ranges (flowers on
-- stems, leafy flower bunches, tall-grass tufts, rocks). No ground patch discs: at eye level their edge read as a mat.
type Kind = {
	weight: number,
	radius: { number },
	flowers: { number },
	bunches: { number },
	tufts: { number },
	rocks: { number },
}
local KINDS: { [string]: Kind } = {
	flowers = {
		weight = 3,
		radius = { 3.5, 6.5 },
		flowers = { 2, 5 },
		bunches = { 1, 2 },
		tufts = { 0, 1 },
		rocks = { 0, 0 },
	},
	grass = {
		weight = 3,
		radius = { 3.5, 6 },
		flowers = { 0, 2 },
		bunches = { 0, 0 },
		tufts = { 2, 3 },
		rocks = { 0, 1 },
	},
	rocks = {
		weight = 1.5,
		radius = { 3, 5.5 },
		flowers = { 0, 1 },
		bunches = { 0, 0 },
		tufts = { 1, 1 },
		rocks = { 2, 3 },
	},
	mixed = {
		weight = 2,
		radius = { 5, 8.5 },
		flowers = { 1, 3 },
		bunches = { 1, 2 },
		tufts = { 1, 2 },
		rocks = { 0, 1 },
	},
}
local KIND_ORDER = { "flowers", "grass", "rocks", "mixed" }

local function ghost(node: Node): Node
	node.canCollide = false
	node.canQuery = false
	node.canTouch = false
	return node
end

local function part(name: string, shape: string, size: Vec, pos: Vec, rot: Vec, color: Vec, material: string): Node
	return ghost({
		name = name,
		class = "Part",
		shape = shape,
		size = size,
		pos = pos,
		rot = rot,
		color = color,
		material = material,
	})
end

local function shadeOf(c: Vec, k: number): Vec
	return {
		math.clamp(math.round(c[1] * k), 0, 255),
		math.clamp(math.round(c[2] * k), 0, 255),
		math.clamp(math.round(c[3] * k), 0, 255),
	}
end

local function range(rng: Rng.Rng, r: { number }): number
	return r[1] + (r[2] - r[1]) * rng:float()
end

-- Lowest point of a (tilted) block above y = 0.
local function blockBottom(size: Vec, pos: Vec, rot: Vec): number
	local m = LayoutMath.orientation(rot)
	local low = math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local c = LayoutMath.apply(m, { sx * size[1] / 2, sy * size[2] / 2, sz * size[3] / 2 })
				low = math.min(low, pos[2] + c[2])
			end
		end
	end
	return low
end
Meadow.blockBottom = blockBottom

-- A flower: green stem + petal ball head, slightly leaning.
local function flower(rng: Rng.Rng, name: string, x: number, z: number, petal: Vec, out: { Node })
	local h = 1.2 + rng:float() * 1.3
	local lean = { rng:float() * 12 - 6, rng:float() * 360, rng:float() * 12 - 6 }
	local m = LayoutMath.orientation(lean)
	-- Stem: a Cylinder runs along local X, so roll it upright first.
	local stemRot = { lean[1], lean[2], lean[3] + 90 }
	local mid = LayoutMath.apply(m, { 0, h / 2, 0 })
	local stemSize = { h + 0.3, 0.22, 0.22 }
	-- sunk 0.15 so the leaning foot never lifts
	table.insert(
		out,
		part(`{name}Stem`, "Cylinder", stemSize, { x + mid[1], mid[2] - 0.15, z + mid[3] }, stemRot, STEM, "Grass")
	)
	local top = LayoutMath.apply(m, { 0, h, 0 })
	local d = 0.7 + rng:float() * 0.45
	table.insert(
		out,
		part(
			`{name}Head`,
			"Ball",
			{ d, d, d },
			{ x + top[1], top[2] - 0.15 + d * 0.2, z + top[3] },
			{ 0, 0, 0 },
			shadeOf(petal, 0.92 + rng:float() * 0.16),
			"SmoothPlastic"
		)
	)
end

-- A flower bunch: a low leafy dome with 2-4 petal heads on its crown.
local function bunch(rng: Rng.Rng, name: string, x: number, z: number, petal: Vec, out: { Node })
	local d = 2.2 + rng:float() * 1.4
	local sink = d * (0.3 + rng:float() * 0.1)
	table.insert(
		out,
		part(
			`{name}Leaves`,
			"Ball",
			{ d, d, d },
			{ x, d / 2 - sink, z },
			{ 0, 0, 0 },
			shadeOf(STEM, 0.85 + rng:float() * 0.2),
			"Grass"
		)
	)
	local top = d - sink
	local heads = rng:int(2, 4)
	local spin = rng:float() * math.pi * 2
	for h = 1, heads do
		local a = spin + h * math.pi * 2 / heads + rng:float() * 0.6
		local r = d * (0.18 + rng:float() * 0.14)
		local hd = 0.7 + rng:float() * 0.4
		-- on the dome's surface at radius r, sunk a little into it
		local y = (d / 2 - sink) + math.sqrt(math.max(0, (d / 2) ^ 2 - r * r)) - hd * 0.2
		table.insert(
			out,
			part(
				`{name}Head{h}`,
				"Ball",
				{ hd, hd, hd },
				{ x + math.cos(a) * r, math.min(y, top + hd * 0.3), z + math.sin(a) * r },
				{ 0, 0, 0 },
				shadeOf(petal, 0.9 + rng:float() * 0.2),
				"SmoothPlastic"
			)
		)
	end
end

-- A tall-grass tuft: 4-5 narrow blades from one foot, fanned all round,
-- each bending out (tilted about its thin axis, so the flat face shows).
local function tuft(rng: Rng.Rng, name: string, x: number, z: number, out: { Node })
	local blades = if rng:float() < 0.4 then 5 else 4
	local h0 = 2.4 + rng:float() * 2.4
	local spin = rng:float() * 360
	for b = 1, blades do
		local h = h0 * (0.75 + rng:float() * 0.3)
		local size = { 0.38 + rng:float() * 0.18, h, 0.12 }
		local rot = { 6 + rng:float() * 14, spin + b * 360 / blades + rng:float() * 50 - 25, rng:float() * 8 - 4 }
		local m = LayoutMath.orientation(rot)
		local c = LayoutMath.apply(m, { 0, h / 2, 0 })
		local pos = { x + c[1], c[2], z + c[3] }
		pos[2] -= blockBottom(size, pos, rot) + 0.12
		local col = BLADES[rng:int(1, #BLADES)]
		table.insert(
			out,
			part(`{name}Blade{b}`, "Block", size, pos, rot, shadeOf(col, 0.94 + rng:float() * 0.12), "Grass")
		)
	end
end

-- A small rock: a sunk boulder dome or a flat stone (a wider ball sunk to
-- its top sixth). Blocks read as paving slabs from the plots, so no slabs.
local function stone(rng: Rng.Rng, name: string, x: number, z: number, s: number, out: { Node })
	local col = shadeOf(STONES[rng:int(1, #STONES)], 0.92 + rng:float() * 0.14)
	local d, show
	if rng:float() < 0.55 then
		d = s * (1 + rng:float() * 0.5)
		show = 0.2 + rng:float() * 0.12
	else
		d = s * (1.2 + rng:float() * 0.4)
		show = 0.12 + rng:float() * 0.06
	end
	table.insert(out, part(name, "Ball", { d, d, d }, { x, d * (show - 0.5), z }, { 0, 0, 0 }, col, "Rock"))
end

-- Piece spot inside a cluster: centre-weighted darts, each piece keeping
-- its own clearance `c` from the ones already placed.
local function spot(rng: Rng.Rng, taken: { { number } }, radius: number, c: number): (number?, number?)
	for _ = 1, 16 do
		local a = rng:float() * math.pi * 2
		local r = (radius - c) * rng:float() ^ 0.8
		local x, z = math.cos(a) * r, math.sin(a) * r
		local ok = true
		for _, p in taken do
			if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < (p[3] + c) ^ 2 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(taken, { x, z, c })
			return x, z
		end
	end
	return nil, nil
end

local function fill(rng: Rng.Rng, kind: string, cx: number, cz: number, radius: number, id: number): { Node }
	local k = KINDS[kind]
	local out: { Node } = {}
	local prefix = `M{id}`
	-- a dominant petal colour, sometimes a second accent
	local main = PETALS[rng:int(1, #PETALS)]
	local accent = PETALS[rng:int(1, #PETALS)]
	local function petal(): Vec
		return if rng:float() < 0.8 then main else accent
	end
	local taken: { { number } } = {}
	local n = 0
	-- big pieces first, the carpet fills round them; c = footprint clearance
	for _, what in { "rocks", "bunches", "tufts", "flowers" } do
		local c = ({ rocks = 1.9, bunches = 1.8, tufts = 1.6, flowers = 0.7 } :: any)[what]
		local counts = (k :: any)[what]
		for _ = 1, rng:int(counts[1], counts[2]) do
			local x, z = spot(rng, taken, radius, c)
			if not x then
				break
			end
			n += 1
			local px, pz = cx + x, cz + (z :: number)
			if what == "rocks" then
				stone(rng, `{prefix}Rock{n}`, px, pz, 1.1 + rng:float() * 1.5, out)
			elseif what == "bunches" then
				bunch(rng, `{prefix}Bunch{n}`, px, pz, petal(), out)
			elseif what == "tufts" then
				tuft(rng, `{prefix}Tuft{n}`, px, pz, out)
			else
				flower(rng, `{prefix}Flower{n}`, px, pz, petal(), out)
			end
		end
	end
	return out
end

local function pickKind(rng: Rng.Rng): string
	local total = 0
	for _, name in KIND_ORDER do
		total += KINDS[name].weight
	end
	local roll = rng:float() * total
	for _, name in KIND_ORDER do
		roll -= KINDS[name].weight
		if roll < 0 then
			return name
		end
	end
	return KIND_ORDER[#KIND_ORDER]
end

function Meadow.clusters(clear: (number, number, number) -> boolean): { Cluster }
	local rng = Rng.new(Meadow.SEED)
	local out: { Cluster } = {}
	local parts = 0
	local function fits(x: number, z: number, radius: number, gap: number, skip: Cluster?): boolean
		local r = math.sqrt(x * x + z * z)
		if r - radius < Meadow.INNER or r + radius > Meadow.OUTER then
			return false
		end
		for _, c in out do
			if c ~= skip and (c.x - x) ^ 2 + (c.z - z) ^ 2 < (c.radius + radius + gap) ^ 2 then
				return false
			end
		end
		return clear(x, z, radius)
	end
	local function add(kind: string, x: number, z: number, radius: number): Cluster?
		local nodes = fill(rng, kind, x, z, radius, #out + 1)
		if parts + #nodes > Meadow.PART_BUDGET then
			return nil
		end
		local c = { kind = kind, x = x, z = z, radius = radius, parts = nodes }
		table.insert(out, c)
		parts += #nodes
		return c
	end
	-- Cells: SECTORS slices of the band in two rings, the outer ring turned
	-- half a slice, visited in shuffled order. Each cell gets one cluster
	-- somewhere inside it (or stays lawn), so the whole band is covered
	-- without a visible grid or period.
	local mid = (Meadow.INNER + Meadow.OUTER) / 2
	local cells: { { number } } = {}
	for ring = 0, 1 do
		for k = 0, Meadow.SECTORS - 1 do
			table.insert(cells, { (k + ring * 0.5) / Meadow.SECTORS, ring })
		end
	end
	for i = #cells, 2, -1 do
		local j = rng:int(1, i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	for _, cell in cells do
		if parts >= Meadow.PART_BUDGET - 6 then
			break
		end
		if rng:float() < Meadow.LAWN then
			continue
		end
		local kind = pickKind(rng)
		local radius = range(rng, KINDS[kind].radius)
		local lo = if cell[2] == 0 then Meadow.INNER + radius else mid - radius * 0.5
		local hi = if cell[2] == 0 then mid + radius * 0.5 else Meadow.OUTER - radius
		-- uneven spacing: some clusters sit close, others leave a wide lawn
		local gap = 2 + rng:float() ^ 2 * 14
		for _ = 1, 8 do
			local a = (cell[1] + rng:float() / Meadow.SECTORS) * math.pi * 2
			local r = math.sqrt(lo ^ 2 + (hi ^ 2 - lo ^ 2) * rng:float())
			local x, z = math.sin(a) * r, math.cos(a) * r
			if fits(x, z, radius, gap) then
				local c = add(kind, x, z, radius)
				-- a drift: sometimes a small satellite cluster just beside it
				if c and rng:float() < Meadow.SATELLITE then
					local sk = if rng:float() < 0.5 then "flowers" else "grass"
					local sr = range(rng, { 3.5, 5.5 })
					local sa = rng:float() * math.pi * 2
					local d = c.radius + sr + 1 + rng:float() * 3
					local sx, sz = x + math.cos(sa) * d, z + math.sin(sa) * d
					if fits(sx, sz, sr, 1, c) then
						add(sk, sx, sz, sr)
					end
				end
				break
			end
		end
	end
	return out
end

function Meadow.build(clusters: { Cluster }): Node
	local children: { Node } = {}
	for i, c in clusters do
		table.insert(children, { name = `Cluster{i}_{c.kind}`, class = "Model", children = c.parts })
	end
	return { name = "Meadow", class = "Folder", children = children }
end

return Meadow
