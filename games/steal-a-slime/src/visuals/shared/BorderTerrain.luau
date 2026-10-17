--!strict
--[[
	BorderTerrain (pure, no Roblox APIs)

	BorderTerrain.field(seed?): Field        -- the seeded hill data
	field.height(x, z): number               -- terrain surface above the Ground top (0 = none)
	field.material(x, z): string             -- "Grass" | "LeafyGrass" | "Rock"
	BorderTerrain.tiles(): { Tile }          -- 32 x 32 column tiles that hold any terrain
	BorderTerrain.chunks(chunkCells?): { Chunk } -- 16 x 16 column chunks (64 studs), nearest the play area first
	BorderTerrain.voxels(field, chunk, materialOf, air): Voxels -- pure per-chunk voxel arrays (the view only WriteVoxels them)
	BorderTerrain.runBudgeted(count, step, budget, clock, yield) -- frame time-budget scheduler (pure, injectable clock)
	BorderTerrain.sample(field, step): Grid  -- heights + materials on a grid (render export, tests)

	The land behind the Slime Ranch border. The 640-stud Ground ends in a
	straight edge; past it the server writes voxel terrain (server/
	BorderTerrainView, Workspace.Terrain: zero parts, zero mesh slots):

	  base    a low rolling skirt flush with the Ground top at its edge
	  near    hills just past the Ground edge, behind the border decor
	  mid     broader, taller hills further out
	  ridge   a ring of backdrop hills round the whole horizon, each bearing
	          its own height, width and distance
	  peak    v4: a ring of tall mountains layered behind all of that, each
	          with its own height, width, depth and ridged flanks; rock on
	          the upper slopes, grass below

	Every hill rolls its own height, width and spacing from the seed; no
	window of WINDOW neighbours repeats the same (height, width) profile.
	Nothing exists inside the Ground square (INNER studs from the centre,
	Chebyshev), so paths, plots, plaza, slide and parade lane are never
	covered; everything within PEAK_CLEAR studs of the Ground edge is no taller
	than MAX_HEIGHT and the mountains stand further out (peak base starts past
	it, up to PEAK_MAX_HEIGHT); the 80-stud invisible walls of WorldBorder sit
	at r 292, inside the Ground, out of reach of all of it.
	The top surface is a heightfield: columns are filled from FLOOR up.
]]

local Rng = if script then require(script.Parent.Parent.Shared.Rng) else require("../../shared/Rng")

export type Hill = {
	layer: string, -- "near" | "mid" | "peak"
	order: number, -- 1-based, in ring order within its layer
	x: number,
	z: number,
	d: number, -- Chebyshev offset of the centre from the map centre
	yaw: number, -- tangent heading in degrees (the long axis)
	along: number, -- half extent along the edge
	across: number, -- half extent away from the map
	height: number,
	hBucket: number,
	wBucket: number,
	ripple: number, -- phase offset of its surface noise
}

export type Tile = { x: number, z: number } -- minimum corner, studs (multiples of CELL)

export type Chunk = { x: number, z: number, size: number } -- minimum corner and side, studs (multiples of CELL)

export type Voxels = {
	layers: number,
	materials: { { { any } } }, -- [i (x)][j (layer)][k (z)]
	occupancy: { { { number } } },
}

export type Grid = {
	step: number,
	min: number, -- x and z of cell (1, 1)
	n: number, -- cells per side
	heights: { number }, -- row-major, z outer
	materials: { string },
}

export type Field = {
	seed: number,
	hills: { Hill },
	height: (x: number, z: number) -> number,
	material: (x: number, z: number) -> string,
}

local BorderTerrain = {}

BorderTerrain.SEED = 20261019
BorderTerrain.INNER = 320 -- Chebyshev studs; nothing at or inside it (the Ground edge)
BorderTerrain.EDGE_RAMP = 40 -- studs past INNER over which the land rises from flush
BorderTerrain.EXTENT = 960 -- half size of the box the server writes
BorderTerrain.CELL = 4 -- voxel size
BorderTerrain.TILE_CELLS = 32
BorderTerrain.CHUNK_CELLS = 16 -- columns per chunk side (64 studs); the server writes one chunk at a time
BorderTerrain.FLOOR = -8 -- columns are filled from here up (a multiple of CELL)
BorderTerrain.MAX_HEIGHT = 68 -- soft ceiling; the walls are 80 (WorldBorder.WALL_HEIGHT)
BorderTerrain.PEAK_MAX_HEIGHT = 230 -- soft ceiling of the mountains (nobody can reach them)
BorderTerrain.PEAK_CLEAR = 90 -- Chebyshev studs past INNER where only the low land (<= MAX_HEIGHT) exists
BorderTerrain.WINDOW = 3
BorderTerrain.H_BUCKETS = 5
BorderTerrain.W_BUCKETS = 4

-- Slime Ranch palette (Terrain:SetMaterialColor); Grass is the soft pastel of the ground terrain (GroundTerrain.COLORS;
-- the SlimeGrass variant darkens it into patches).
BorderTerrain.COLORS = table.freeze({
	Grass = { 146, 206, 84 },
	LeafyGrass = { 82, 146, 66 },
	Rock = { 136, 126, 112 },
} :: { [string]: { number } })

local SOFT_KNEE = 46
local PEAK_KNEE = 180

-- near / mid hill layers. d: centre offset past the Ground edge is
-- `lead * across + jitter`.
local LAYERS = {
	near = {
		along = { 42, 130 },
		across = { 30, 70 },
		height = { 12, 46 },
		gap = { 0.1, 1.1 },
		lead = 0.85,
		jitter = 26,
	},
	mid = {
		along = { 90, 230 },
		across = { 70, 140 },
		height = { 22, 56 },
		gap = { 0, 0.9 },
		lead = 0.95,
		jitter = 90,
	},
	-- tall mountains behind the ridge ring: `offset` keeps their feet past PEAK_CLEAR
	peak = {
		along = { 120, 280 },
		across = { 90, 190 },
		height = { 85, 200 },
		gap = { 0, 0.5 },
		lead = 0.9,
		jitter = 150,
		offset = 130,
		sideAligned = true, -- long axis parallel to its side of the square: the foot never swings inward at the corners
	},
}

local function lerp(range: { number }, t: number): number
	return range[1] + (range[2] - range[1]) * t
end

local function smoothstep(a: number, b: number, v: number): number
	local t = math.clamp((v - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Hashed lattice value in [0, 1).
local M32 = 4294967296
local function lattice(ix: number, iz: number, seed: number): number
	local h = bit32.bxor((ix * 73856093) % M32, (iz * 19349663) % M32, (seed * 83492791) % M32)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = (h * 40503) % M32
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 40503) % M32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / M32
end

-- Smooth value noise in [0, 1) (cell size 1).
local function noise2(x: number, z: number, seed: number): number
	local ix, iz = math.floor(x), math.floor(z)
	local fx, fz = x - ix, z - iz
	fx = fx * fx * (3 - 2 * fx)
	fz = fz * fz * (3 - 2 * fz)
	local a = lattice(ix, iz, seed)
	local b = lattice(ix + 1, iz, seed)
	local c = lattice(ix, iz + 1, seed)
	local d = lattice(ix + 1, iz + 1, seed)
	return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fz
end

-- A closed ring of `count` random values, cosine-interpolated by angle.
local function ringNoise(rng: Rng.Rng, count: number): (number) -> number
	local values = {}
	for i = 1, count do
		values[i] = rng:float()
	end
	return function(angle: number): number
		local f = (angle % 360) / 360 * count
		local i = math.floor(f)
		local t = f - i
		t = (1 - math.cos(t * math.pi)) / 2
		local a, b = values[i % count + 1], values[(i + 1) % count + 1]
		return a + (b - a) * t
	end
end

local function bucket(range: { number }, v: number, count: number): number
	return math.clamp(math.floor((v - range[1]) / (range[2] - range[1]) * count), 0, count - 1)
end

-- Point on the square of half size `d` at fraction f of the way round.
local function squarePoint(f: number, d: number): (number, number)
	f = f % 1
	local side = math.floor(f * 4)
	local t = (f * 4 - side) * 2 - 1
	if side == 0 then
		return t * d, d
	elseif side == 1 then
		return d, -t * d
	elseif side == 2 then
		return -t * d, -d
	end
	return -d, t * d
end

local function signature(h: Hill): string
	return `{h.hBucket}|{h.wBucket}`
end

-- Rolls one layer's hills: sizes first (a window of WINDOW neighbours never
-- repeats a (height, width) profile seen before), then spreads them round
-- the ring so the last meets the first.
local function rollLayer(rng: Rng.Rng, name: string): { Hill }
	local cfg = LAYERS[name]
	local perimeter = 8 * (BorderTerrain.INNER + (cfg.offset or 0) + cfg.across[2] * 1.2 + cfg.jitter)
	local avg = (cfg.along[1] + cfg.along[2]) / 2
	local want = math.floor(perimeter / (2 * avg * (1 + (cfg.gap[1] + cfg.gap[2]) / 2 - 0.2)))
	local hills: { Hill } = {}
	local seen: { [string]: boolean } = {}
	local sigs: { string } = {}
	local W = BorderTerrain.WINDOW
	for i = 1, want do
		local hill: Hill
		for _ = 1, 60 do
			local along = lerp(cfg.along, rng:float())
			local across = lerp(cfg.across, rng:float() ^ 1.3)
			local height = lerp(cfg.height, rng:float())
			hill = {
				layer = name,
				order = i,
				x = 0,
				z = 0,
				d = BorderTerrain.INNER + (cfg.offset or 0) + cfg.lead * across + rng:float() * cfg.jitter,
				yaw = 0,
				along = along,
				across = across,
				height = height,
				hBucket = bucket(cfg.height, height, BorderTerrain.H_BUCKETS),
				wBucket = bucket(cfg.along, along, BorderTerrain.W_BUCKETS),
				ripple = rng:float() * 100,
			}
			if #sigs < W - 1 then
				break
			end
			local key = table.concat(sigs, "/", #sigs - W + 2, #sigs) .. "/" .. signature(hill)
			if not seen[key] then
				break
			end
		end
		table.insert(hills, hill)
		table.insert(sigs, signature(hill))
		if #sigs >= W then
			seen[table.concat(sigs, "/", #sigs - W + 1, #sigs)] = true
		end
	end
	-- The seam: windows across the last/first hills must be new too.
	local n = #hills
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
		local last = hills[n]
		last.height = lerp(cfg.height, rng:float())
		last.hBucket = bucket(cfg.height, last.height, BorderTerrain.H_BUCKETS)
		sigs[n] = signature(last)
	end
	-- Spread round the ring: random gaps, scaled so the loop closes.
	local advances: { number } = {}
	local total = 0
	for i = 1, n do
		local nextHill = hills[i % n + 1]
		local a = (hills[i].along + nextHill.along) * lerp(cfg.gap, rng:float())
			+ 0.4 * (hills[i].along + nextHill.along)
		advances[i] = a
		total += a
	end
	local start = rng:float()
	local s = 0
	for i, hill in hills do
		local f = start + s / total
		local d = hill.d
		hill.x, hill.z = squarePoint(f, d)
		-- long axis tangent to the ring
		local r = math.sqrt(hill.x * hill.x + hill.z * hill.z)
		hill.yaw = math.deg(math.atan2(-hill.x / r, hill.z / r)) % 360
		if cfg.sideAligned then
			hill.yaw = if math.abs(hill.z) >= math.abs(hill.x) then 90 else 0
		end
		s += advances[i]
	end
	return hills
end

-- 'p-norm' union of the hills so overlaps merge instead of stacking.
local function softCap(h: number, knee: number, top: number): number
	if h <= knee then
		return h
	end
	return knee + (top - knee) * math.tanh((h - knee) / (top - knee))
end

function BorderTerrain.field(seed: number?): Field
	local base = seed or BorderTerrain.SEED
	local hills: { Hill } = {}
	for i, name in { "near", "mid", "peak" } do
		for _, hill in rollLayer(Rng.new(base + i * 7919), name) do
			table.insert(hills, hill)
		end
	end
	-- backdrop ridge ring (polar): crest height, width and distance all vary
	local ridgeRng = Rng.new(base + 104729)
	local crest = ringNoise(ridgeRng, 13)
	local crestFine = ringNoise(ridgeRng, 41)
	local distance = ringNoise(ridgeRng, 9)
	local width = ringNoise(ridgeRng, 17)

	local boxes = {}
	local cosYaw, sinYaw = {}, {}
	for i, hill in hills do
		local reach = math.max(hill.along, hill.across)
		boxes[i] = { hill.x - reach, hill.x + reach, hill.z - reach, hill.z + reach }
		local a = math.rad(hill.yaw)
		cosYaw[i], sinYaw[i] = math.cos(a), math.sin(a)
	end
	local INNER, RAMP = BorderTerrain.INNER, BorderTerrain.EDGE_RAMP

	local function height(x: number, z: number): number
		local d = math.max(math.abs(x), math.abs(z))
		if d <= INNER then
			return 0
		end
		local ramp = smoothstep(INNER, INNER + RAMP, d)
		local sum, peakSum = 0, 0
		for i, hill in hills do
			local box = boxes[i]
			if x > box[1] and x < box[2] and z > box[3] and z < box[4] then
				local dx, dz = x - hill.x, z - hill.z
				local a = (dx * sinYaw[i] + dz * cosYaw[i]) / hill.along
				local c = (dx * cosYaw[i] - dz * sinYaw[i]) / hill.across
				local u = a * a + c * c
				if u < 1 then
					local b = (1 - u) * (1 - u)
					local h = hill.height * b
					if hill.layer == "peak" then
						-- steeper crown, ridged flanks (ridge lines run down the slope)
						h = hill.height * b * (1 - u * 0.35)
						local ridge = 1 - math.abs(2 * noise2(x / 64 + hill.ripple, z / 64, 21) - 1)
						h *= 0.78 + 0.34 * ridge
						peakSum += h * h * h
					else
						-- surface ripple, strongest on the flanks
						h *= 0.88 + 0.24 * noise2(x / 38 + hill.ripple, z / 38, 5)
						sum += h * h * h
					end
				end
			end
		end
		local r = math.sqrt(x * x + z * z)
		local angle = math.deg(math.atan2(x, z))
		local centre = 600 + 90 * distance(angle)
		local half = 150 + 90 * width(angle)
		local u = (r - centre) / half
		if u > -1 and u < 1 then
			local e = 24 + 36 * crest(angle) + 10 * (crestFine(angle) - 0.5)
			local b = (1 - u * u) * (1 - u * u)
			local h = e * b * (0.9 + 0.2 * noise2(x / 52, z / 52, 9))
			sum += h * h * h
		end
		local rolling = 2.5 + 5 * noise2(x / 80, z / 80, 3) + 2 * noise2(x / 23, z / 23, 4)
		local low = softCap(sum ^ (1 / 3) + rolling, SOFT_KNEE, BorderTerrain.MAX_HEIGHT)
		local peak = softCap(peakSum ^ (1 / 3), PEAK_KNEE, BorderTerrain.PEAK_MAX_HEIGHT)
		-- the mountains rise out of the low land: p-norm union
		local h = (low ^ 3 + peak ^ 3) ^ (1 / 3)
		return h * ramp
	end

	local function material(x: number, z: number): string
		local h = height(x, z)
		local e = 4
		local slope = (math.abs(height(x + e, z) - h) + math.abs(height(x, z + e) - h)) / e
		if h < 3 then
			return "Grass"
		end
		-- rock above a wandering snow-free line, or on cliffs (the mountains' flanks are steeper, so the cliff slope grows with height)
		local rockLine = 48 + 36 * noise2(x / 90, z / 90, 13)
		local cliff = 0.95 + 1.5 * smoothstep(30, 80, h)
		if slope > cliff or h > rockLine then
			return "Rock"
		end
		if noise2(x / 52, z / 52, 11) > 0.6 then
			return "LeafyGrass"
		end
		return "Grass"
	end

	return { seed = base, hills = hills, height = height, material = material }
end

-- Tiles (TILE_CELLS x TILE_CELLS columns) with terrain in them.
function BorderTerrain.tiles(): { Tile }
	local out: { Tile } = {}
	local size = BorderTerrain.TILE_CELLS * BorderTerrain.CELL
	local E = BorderTerrain.EXTENT
	local x = -E
	while x < E do
		local z = -E
		while z < E do
			-- Chebyshev distance of the tile's nearest point to the centre
			local nearest = math.max(math.max(x, -(x + size), 0), math.max(z, -(z + size), 0))
			if nearest + size > BorderTerrain.INNER and nearest < BorderTerrain.EXTENT then
				table.insert(out, { x = x, z = z })
			end
			z += size
		end
		x += size
	end
	return out
end

-- Chunks (chunkCells x chunkCells columns, aligned to the CELL grid and so to
-- FLOOR) covering the same terrain as tiles(): every column of a tile that
-- reaches past INNER. Chunks wholly inside INNER (air only) are dropped.
-- Sorted nearest-first by the Euclidean distance of the chunk's nearest point
-- to the centre (the play area), ties by x then z.
function BorderTerrain.chunks(chunkCells: number?): { Chunk }
	local size = (chunkCells or BorderTerrain.CHUNK_CELLS) * BorderTerrain.CELL
	local E = BorderTerrain.EXTENT
	local out: { Chunk } = {}
	local dist: { [Chunk]: number } = {}
	local x = -E
	while x < E do
		local z = -E
		while z < E do
			local nx = math.max(x, -(x + size), 0)
			local nz = math.max(z, -(z + size), 0)
			if math.max(nx, nz) + size > BorderTerrain.INNER then
				local chunk = { x = x, z = z, size = size }
				dist[chunk] = nx * nx + nz * nz
				table.insert(out, chunk)
			end
			z += size
		end
		x += size
	end
	table.sort(out, function(a, b)
		if dist[a] ~= dist[b] then
			return dist[a] < dist[b]
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.z < b.z
	end)
	return out
end

-- Voxel arrays for a chunk, ready for Terrain:WriteVoxels at the chunk's
-- region (x, FLOOR, z) .. (x + size, FLOOR + layers * CELL, z + size).
-- materialOf maps "Grass" | "LeafyGrass" | "Rock" to the caller's material;
-- air is its Air. Each voxel depends only on its own column and layer, never
-- on the chunk, so any chunking writes identical voxels; `layers` only sets
-- how much air sits above the chunk's tallest column.
function BorderTerrain.voxels(field: Field, chunk: Chunk, materialOf: { [string]: any }, air: any): Voxels
	local cell, floor = BorderTerrain.CELL, BorderTerrain.FLOOR
	local count = math.floor(chunk.size / cell)
	local heights: { number } = {}
	local tops: { string } = {}
	local tallest = 0
	for i = 1, count do
		local x = chunk.x + (i - 0.5) * cell
		for k = 1, count do
			local z = chunk.z + (k - 0.5) * cell
			local h = field.height(x, z)
			local inside = math.max(math.abs(x), math.abs(z)) <= BorderTerrain.INNER
			-- -1: no column here (inside the Ground square)
			heights[(i - 1) * count + k] = if inside then -1 else h
			tops[(i - 1) * count + k] = if h > 0 then field.material(x, z) else "Grass"
			tallest = math.max(tallest, h)
		end
	end
	local layers = math.ceil((tallest - floor) / cell) + 1
	local materials = table.create(count)
	local occupancy = table.create(count)
	for i = 1, count do
		local mx = table.create(layers)
		local ox = table.create(layers)
		for j = 1, layers do
			local mj = table.create(count, air)
			local oj = table.create(count, 0)
			local bottom = floor + (j - 1) * cell
			for k = 1, count do
				local h = heights[(i - 1) * count + k]
				if h >= 0 then
					local filled = math.clamp((h - bottom) / cell, 0, 1)
					if filled > 0.02 then
						mj[k] = materialOf[tops[(i - 1) * count + k]]
						oj[k] = filled
					end
				end
			end
			mx[j] = mj
			ox[j] = oj
		end
		materials[i] = mx
		occupancy[i] = ox
	end
	return { layers = layers, materials = materials, occupancy = occupancy }
end

-- Runs step(1..count) in order, yielding whenever clock() - frameStart has
-- reached budget (at least one step per frame, so it always progresses).
-- Returns the number of yields.
function BorderTerrain.runBudgeted(
	count: number,
	step: (number) -> (),
	budget: number,
	clock: () -> number,
	yield: () -> ()
): number
	local yields = 0
	local frameStart = clock()
	for n = 1, count do
		step(n)
		if n < count and clock() - frameStart >= budget then
			yield()
			yields += 1
			frameStart = clock()
		end
	end
	return yields
end

-- Heights and materials at the centres of an n x n grid covering the box.
function BorderTerrain.sample(field: Field, step: number): Grid
	local E = BorderTerrain.EXTENT
	local n = math.floor(2 * E / step)
	local heights, materials = {}, {}
	for j = 0, n - 1 do
		local z = -E + (j + 0.5) * step
		for i = 0, n - 1 do
			local x = -E + (i + 0.5) * step
			local h = field.height(x, z)
			heights[j * n + i + 1] = h
			materials[j * n + i + 1] = if h > 0 then field.material(x, z) else "Grass"
		end
	end
	return { step = step, min = -E + step / 2, n = n, heights = heights, materials = materials }
end

return table.freeze(BorderTerrain)
