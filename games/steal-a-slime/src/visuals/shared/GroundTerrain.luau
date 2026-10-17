--!strict
--[[
	GroundTerrain (pure, no Roblox APIs; v31 bugs #13-15)

	GroundTerrain.material(x, z): string        -- "Grass" | "Ground" | "Sand" at a world point
	GroundTerrain.grid(): Grid                  -- one material per 4-stud cell of the Ground square
	GroundTerrain.tiles(): { Tile }             -- 32 x 32 cell tiles that tile the Ground square

	The inner ground is voxel terrain (server/GroundTerrainView), not parts:
	  * Ground (Enum.Material.Ground)  the packed-dirt path: the ring (r 78, 8 wide), eight spokes from the
	    plaza edge to the plot gates and are ONE shape (smooth union, rounded fillets at
	    the T-junctions), so there are no tiles and no seams by construction;
	  * Sand     the plaza (r 66), its edge feathered ~7 studs into the grass with a noisy, patchy dither;
	  * Grass    the rest (pastel, with tufts through Terrain.Decoration set in default.project.json).
	The shapes are the concept mock's masks (concept/masks.py): the same signed distances, noise scales and
	feather widths, sampled at the cell centres. Voxels are 4 studs, the finest Terrain allows, so the edges are
	soft only as far as Terrain's own material blending makes them; the path edge is jittered per cell so it
	scatters instead of stair-stepping.
	The surface is flat at y = 0 (the old Ground top) everywhere: columns are filled from FLOOR up to 0.
	Cells under a plot (the Base floor, +-PLOT_SIZE/2) are Ground, never Grass, so no grass tuft ever pokes
	through a plot floor or a pad.
]]

local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Tile = { x: number, z: number } -- minimum corner, studs (multiples of CELL)

export type Grid = {
	cell: number,
	min: number, -- x and z of cell (1, 1)'s centre
	n: number, -- cells per side
	materials: { string }, -- row-major, z outer
}

local GroundTerrain = {}

GroundTerrain.CELL = 4
GroundTerrain.HALF = 320 -- the Ground square, studs from the centre
GroundTerrain.TILE_CELLS = 32
GroundTerrain.FLOOR = -8 -- columns are filled from here up to the surface at y = 0
GroundTerrain.SURFACE = 0

GroundTerrain.RING_RADIUS = WorldLayout.RING_PATH_RADIUS -- 78
GroundTerrain.PATH_HALF_WIDTH = WorldLayout.RING_PATH_WIDTH / 2 -- 4
GroundTerrain.PLAZA_RADIUS = WorldLayout.PLAZA_RADIUS -- 66
GroundTerrain.SPOKE_END = 104 -- spokes end here (rounded) just inside the plot gates
GroundTerrain.SPOKE_START = 60 -- under the plaza sand edge
GroundTerrain.FILLET = 3 -- smooth-union width of ring and spokes
GroundTerrain.EDGE_JITTER = 2 -- studs peak to peak of the per-cell path edge jitter (the centreline cells stay dirt)
GroundTerrain.FEATHER_IN = 3.5 -- sand fully on this far inside the plaza edge
GroundTerrain.FEATHER_OUT = 4 -- and gone this far outside it (7.5 studs of blend)

-- Terrain material tints (Terrain:SetMaterialColor), the lightest colour of each palette; the soft ColorMaps
-- of GroundMaterials multiply them down to the darker one. Without the variants these are the flat colours.
GroundTerrain.COLORS = table.freeze({
	Grass = { 162, 206, 118 },
	Ground = { 204, 152, 100 },
	Sand = { 246, 220, 170 },
} :: { [string]: { number } })

-- Darker colour of each palette (the concept's A colours), the low end of the ColorMap variation.
GroundTerrain.DARK = table.freeze({
	Grass = { 92, 182, 70 },
	Ground = { 178, 124, 80 },
	Sand = { 236, 204, 146 },
} :: { [string]: { number } })

-- How much of DARK each ColorMap may reach (tools/ground/ground_textures.py STRENGTH; the render export mirrors it).
GroundTerrain.MAP_DEPTH = table.freeze({ Grass = 0.65, Ground = 1, Sand = 1 } :: { [string]: number })

local SEED_LO, SEED_MID, SEED_HI, SEED_DITHER, SEED_CLUMP, SEED_EDGE = 1, 2, 3, 4, 5, 6

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function smin(a: number, b: number, k: number): number
	local h = math.clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return b * (1 - h) + a * h - k * h * (1 - h)
end

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

-- Smooth value noise in [0, 1) at `scale` lattice cells per stud.
local function vnoise(x: number, z: number, scale: number, seed: number): number
	local fx, fz = x * scale, z * scale
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = fx - ix, fz - iz
	tx = tx * tx * (3 - 2 * tx)
	tz = tz * tz * (3 - 2 * tz)
	local a, b = lattice(ix, iz, seed), lattice(ix + 1, iz, seed)
	local c, d = lattice(ix, iz + 1, seed), lattice(ix + 1, iz + 1, seed)
	local top = a + (b - a) * tx
	return top + ((c + (d - c) * tx) - top) * tz
end

-- Direction (unit, x z) of plot / spoke k (0-based): +Z first, then every 45 degrees.
local SPOKES: { { number } } = {}
for k = 0, 7 do
	local a = math.rad(360 / 8 * k)
	SPOKES[k + 1] = { math.sin(a), math.cos(a) }
end

-- Signed distance (studs, < 0 inside) of the dirt path: ring + eight spokes, smooth-unioned.
local function pathDistance(x: number, z: number): number
	local r = math.sqrt(x * x + z * z)
	local d = math.abs(r - GroundTerrain.RING_RADIUS) - GroundTerrain.PATH_HALF_WIDTH
	for _, dir in SPOKES do
		local ux, uz = dir[1], dir[2]
		local t = math.clamp(x * ux + z * uz, GroundTerrain.SPOKE_START, GroundTerrain.SPOKE_END)
		local ds = math.sqrt((x - ux * t) ^ 2 + (z - uz * t) ^ 2) - GroundTerrain.PATH_HALF_WIDTH
		d = smin(d, ds, GroundTerrain.FILLET)
	end
	return d
end

-- Plot k's Base floor (an 80 x 80 square turned by its yaw, centred at r PLOT_RING_RADIUS).
local function underPlot(x: number, z: number): boolean
	local half = WorldLayout.PLOT_SIZE / 2 - 1
	local ring = WorldLayout.PLOT_RING_RADIUS
	for _, dir in SPOKES do
		local cx, cz = dir[1] * ring, dir[2] * ring
		-- along = away from the centre, across = sideways
		local along = (x - cx) * dir[1] + (z - cz) * dir[2]
		local across = (x - cx) * dir[2] - (z - cz) * dir[1]
		if math.abs(along) <= half and math.abs(across) <= half then
			return true
		end
	end
	return false
end

-- Material of the 4-stud cell centred on (x, z).
function GroundTerrain.material(x: number, z: number): string
	local r = math.sqrt(x * x + z * z)
	local nMid = vnoise(x, z, 1 / 2.9, SEED_MID) - 0.5
	local nHi = vnoise(x, z, 1 / 0.65, SEED_HI) - 0.5
	-- per-cell jitter of the path edge: a straight 4-stud voxel staircase breaks into a scatter of dirt / grass cells
	local ix, iz = math.floor(x / GroundTerrain.CELL), math.floor(z / GroundTerrain.CELL)
	local edge = (lattice(ix, iz, SEED_EDGE) - 0.5) * GroundTerrain.EDGE_JITTER
	local d = pathDistance(x, z) + nMid * 0.7 + nHi * 0.25 + edge
	if d < 0 then
		return "Ground"
	end
	if underPlot(x, z) then
		return "Ground"
	end
	local nLo = vnoise(x, z, 1 / 10, SEED_LO) - 0.5
	local ds = r - GroundTerrain.PLAZA_RADIUS + nLo * 5 + nMid * 2
	local coverage = smooth(GroundTerrain.FEATHER_OUT, -GroundTerrain.FEATHER_IN, ds + nHi * 2.5)
	if coverage <= 0 then
		return "Grass"
	end
	if coverage >= 1 then
		return "Sand"
	end
	-- the feather band: dither Sand vs Grass by a seeded threshold (cell hash mixed with a soft clump noise)
	local threshold = 0.6 * lattice(ix, iz, SEED_DITHER) + 0.4 * vnoise(x, z, 1 / 7, SEED_CLUMP)
	-- widen the mixed threshold back to a uniform-ish spread so coverage maps to the sand fraction
	threshold = math.clamp((threshold - 0.5) * 1.35 + 0.5, 0, 1)
	return if coverage > threshold then "Sand" else "Grass"
end

-- Materials at the centres of the cells covering the Ground square.
function GroundTerrain.grid(): Grid
	local cell, half = GroundTerrain.CELL, GroundTerrain.HALF
	local n = 2 * half // cell
	local materials = table.create(n * n)
	for j = 0, n - 1 do
		local z = -half + (j + 0.5) * cell
		for i = 0, n - 1 do
			materials[j * n + i + 1] = GroundTerrain.material(-half + (i + 0.5) * cell, z)
		end
	end
	return { cell = cell, min = -half + cell / 2, n = n, materials = materials }
end

function GroundTerrain.tiles(): { Tile }
	local out: { Tile } = {}
	local size = GroundTerrain.TILE_CELLS * GroundTerrain.CELL
	local x = -GroundTerrain.HALF
	while x < GroundTerrain.HALF do
		local z = -GroundTerrain.HALF
		while z < GroundTerrain.HALF do
			table.insert(out, { x = x, z = z })
			z += size
		end
		x += size
	end
	return out
end

return table.freeze(GroundTerrain)
