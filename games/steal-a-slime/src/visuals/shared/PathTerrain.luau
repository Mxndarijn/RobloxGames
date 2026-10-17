--!strict
--[[
	PathTerrain (pure, no Roblox APIs)

	PathTerrain.curves(): { Curve }          -- the sampled centrelines: ring, spokes, slide exit
	PathTerrain.sampleSpline(controls, closed, spacing): { Point }
	PathTerrain.field(): Field               -- smooth signed distance + material at (x, z)
	PathTerrain.fills(): { Fill }            -- the 4-stud terrain columns the server writes

	v2 of the walking paths: no Parts, no MeshParts. The plaza sand, the ring
	path, one spoke per plot and the slide-exit path are Workspace.Terrain
	voxels (server/PathTerrainView), laid out here:

	  ring    a closed Catmull-Rom loop through RING_CONTROLS points on r 78
	  spokes  one per plot, from inside the plaza to the plot gate (d 100),
	          along (sin yaw, cos yaw) like the plot itself
	  exit    from the landing-ring curb's outer edge out to spoke 1 (the
	          slide ends on its axis)

	Every curve is sampled at SPACING studs by arc length (deterministic: no
	randomness). A column's distance to each curve is a capsule distance minus
	the curve's half width; the curves and the plaza disc are merged with a
	polynomial smooth minimum (FILLET), so spokes meet the ring, the plaza and
	the exit in rounded fillets with no seam.

	Smooth terrain draws a voxel's occupancy as how much of the 4-stud cell is
	solid, so an edge cell's occupancy is the signed distance mapped to cell
	coverage: occupancy = clamp(0.5 - d / CELL, 0, 1). The mesher then puts
	the edge where occupancy crosses one half, a sub-voxel accurate curve, not
	a 4-stud staircase. A column is solid from FLOOR up to TOP in every layer, so
	a path's top is flush at TOP wherever it is occupied. Materials: Ground on
	the path, Sand on the plaza, a Mud rim on the cells that straddle either edge.
	The Ground part sits a hair under TOP, so no edge or surface z-fights it.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

export type Point = { x: number, z: number }

export type Curve = {
	name: string,
	kind: string, -- "ring" | "spoke" | "exit"
	closed: boolean,
	halfWidth: number,
	points: { Point },
	plot: number?, -- spoke: the plot it serves
}

export type Fill = {
	x: number, -- column centre
	z: number,
	material: string, -- "Ground" | "Sand" | "Mud"
	occupancy: number, -- 0..1 of the cell's lateral coverage (every layer of the column)
	top: number, -- studs: the column's surface, always TOP
}

export type Field = {
	sdf: (x: number, z: number) -> number, -- paths only, smooth; < 0 inside
	plaza: (x: number, z: number) -> number, -- signed distance to the plaza disc
	material: (x: number, z: number) -> (string?, number), -- material and occupancy, nil = untouched
}

local PathTerrain = {}

PathTerrain.CELL = 4 -- voxel size
PathTerrain.FLOOR = -8 -- columns are filled from here up (a multiple of CELL)
PathTerrain.TOP = 0 -- full column top, studs
PathTerrain.PLAZA_RADIUS = 66
PathTerrain.RING_RADIUS = 78
PathTerrain.RING_HALF_WIDTH = 5
PathTerrain.SPOKE_HALF_WIDTH = 5
PathTerrain.EXIT_HALF_WIDTH = 5
PathTerrain.RING_CONTROLS = 24
PathTerrain.SPOKE_START = 62 -- inside the plaza disc, so the spoke grows out of the sand
PathTerrain.GATE_DISTANCE = 100 -- PLOT_RING_RADIUS - PLOT_SIZE / 2: the plot's front edge
PathTerrain.EXIT_FROM = 43.8 -- the landing-ring curb's outer edge (WorldLayout.LANDING_OUTER_RADIUS)
PathTerrain.EXIT_X = 0 -- the slide ends on +Z at x 0
PathTerrain.EXIT_TO = 64 -- runs 4 studs into spoke 1
PathTerrain.SPACING = 1.5
PathTerrain.FILLET = 7 -- smooth-union radius, studs
PathTerrain.PLAZA_FILLET = 3 -- the plaza disc blends into a spoke less than the path curves do (the ring stays clear of it)
PathTerrain.TRIM = 0.5 -- cells whose centre is within this of an edge (inside) or past it are Mud
PathTerrain.EXTENT = 112 -- half size of the box the server writes (a multiple of CELL)
PathTerrain.MATERIALS = table.freeze({ "Ground", "Sand", "Mud" })
-- Studio terrain material colours (RGB). Terrain colours are per material and global: the
-- border hills use Grass / LeafyGrass / Rock, so these three are ours alone.
PathTerrain.COLORS = table.freeze({
	Ground = table.freeze({ 186, 138, 88 }), -- packed ranch dirt
	Sand = table.freeze({ 224, 200, 152 }), -- the plaza
	Mud = table.freeze({ 118, 82, 52 }), -- warm wood-brown rim
})

-- Uniform Catmull-Rom through `controls` (open: end points repeated), resampled by arc length
-- every `spacing` studs. Open curves include both end points; closed ones do not repeat the first.
function PathTerrain.sampleSpline(controls: { Point }, closed: boolean, spacing: number): { Point }
	local n = #controls
	assert(n >= 2, "a spline needs two control points")
	local function at(i: number): Point
		if closed then
			return controls[(i - 1) % n + 1]
		end
		return controls[math.clamp(i, 1, n)]
	end
	local dense: { Point } = {}
	local segments = if closed then n else n - 1
	local steps = 24
	for s = 1, segments do
		local p0, p1, p2, p3 = at(s - 1), at(s), at(s + 1), at(s + 2)
		for k = 0, steps - 1 do
			local t = k / steps
			local t2, t3 = t * t, t * t * t
			local function axis(a: number, b: number, c: number, d: number): number
				return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
			end
			table.insert(dense, { x = axis(p0.x, p1.x, p2.x, p3.x), z = axis(p0.z, p1.z, p2.z, p3.z) })
		end
	end
	if closed then
		table.insert(dense, dense[1])
	else
		table.insert(dense, controls[n])
	end
	-- resample at equal arc length
	local out: { Point } = { dense[1] }
	local total = 0
	local lengths = { 0 }
	for i = 2, #dense do
		total += math.sqrt((dense[i].x - dense[i - 1].x) ^ 2 + (dense[i].z - dense[i - 1].z) ^ 2)
		lengths[i] = total
	end
	local count = math.max(1, math.round(total / spacing))
	local j = 1
	for k = 1, count - (if closed then 1 else 0) do
		local target = total * k / count
		while lengths[j + 1] < target do
			j += 1
		end
		local seg = lengths[j + 1] - lengths[j]
		local f = if seg > 0 then (target - lengths[j]) / seg else 0
		table.insert(out, {
			x = dense[j].x + (dense[j + 1].x - dense[j].x) * f,
			z = dense[j].z + (dense[j + 1].z - dense[j].z) * f,
		})
	end
	if closed then
		return out -- the loop closes from the last point back to the first
	end
	out[#out] = controls[n]
	return out
end

local function yawOf(plot: number): number
	return math.rad((plot - 1) * 360 / Config.PLOT_COUNT)
end

local cached: { Curve }? = nil

function PathTerrain.curves(): { Curve }
	if cached then
		return cached
	end
	local out: { Curve } = {}
	local ring: { Point } = {}
	for k = 0, PathTerrain.RING_CONTROLS - 1 do
		local a = 2 * math.pi * k / PathTerrain.RING_CONTROLS
		table.insert(ring, { x = math.sin(a) * PathTerrain.RING_RADIUS, z = math.cos(a) * PathTerrain.RING_RADIUS })
	end
	table.insert(out, {
		name = "Ring",
		kind = "ring",
		closed = true,
		halfWidth = PathTerrain.RING_HALF_WIDTH,
		points = PathTerrain.sampleSpline(ring, true, PathTerrain.SPACING),
	})
	for i = 1, Config.PLOT_COUNT do
		local yaw = yawOf(i)
		local sx, sz = math.sin(yaw), math.cos(yaw)
		local controls: { Point } = {}
		for _, d in
			{
				PathTerrain.SPOKE_START,
				(PathTerrain.SPOKE_START + PathTerrain.GATE_DISTANCE) / 2,
				PathTerrain.GATE_DISTANCE,
			}
		do
			table.insert(controls, { x = sx * d, z = sz * d })
		end
		table.insert(out, {
			name = `Spoke{i}`,
			kind = "spoke",
			closed = false,
			halfWidth = PathTerrain.SPOKE_HALF_WIDTH,
			points = PathTerrain.sampleSpline(controls, false, PathTerrain.SPACING),
			plot = i,
		})
	end
	local x = PathTerrain.EXIT_X
	table.insert(out, {
		name = "SlideExit",
		kind = "exit",
		closed = false,
		halfWidth = PathTerrain.EXIT_HALF_WIDTH,
		points = PathTerrain.sampleSpline({
			{ x = x, z = PathTerrain.EXIT_FROM },
			{ x = x, z = (PathTerrain.EXIT_FROM + PathTerrain.EXIT_TO) / 2 },
			{ x = x, z = PathTerrain.EXIT_TO },
		}, false, PathTerrain.SPACING),
	})
	cached = out
	return out
end

-- Distance from (x, z) to a polyline's nearest segment.
local function distance(points: { Point }, closed: boolean, x: number, z: number): number
	local best = math.huge
	local count = #points
	local last = if closed then count else count - 1
	for i = 1, last do
		local a, b = points[i], points[i % count + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len2 = dx * dx + dz * dz
		local t = if len2 > 0 then math.clamp(((x - a.x) * dx + (z - a.z) * dz) / len2, 0, 1) else 0
		local px, pz = a.x + dx * t - x, a.z + dz * t - z
		local d2 = px * px + pz * pz
		if d2 < best then
			best = d2
		end
	end
	return math.sqrt(best)
end

PathTerrain.distance = distance

-- Polynomial smooth minimum: the rounded fillet where two curves meet.
local function smin(a: number, b: number, k: number): number
	local h = math.max(k - math.abs(a - b), 0) / k
	return math.min(a, b) - h * h * k * 0.25
end

function PathTerrain.field(): Field
	local curves = PathTerrain.curves()
	local fillet = PathTerrain.FILLET
	local gate = PathTerrain.GATE_DISTANCE
	local function sdf(x: number, z: number): number
		local d = math.huge
		for _, c in curves do
			-- a spoke stops at its plot's front edge: no stub past the gate
			if c.plot then
				local yaw = yawOf(c.plot)
				if x * math.sin(yaw) + z * math.cos(yaw) > gate then
					continue
				end
			end
			local own = distance(c.points, c.closed, x, z) - c.halfWidth
			d = if d == math.huge then own else smin(d, own, fillet)
		end
		return d
	end
	local function plaza(x: number, z: number): number
		return math.sqrt(x * x + z * z) - PathTerrain.PLAZA_RADIUS
	end
	local plazaFillet = PathTerrain.PLAZA_FILLET
	local trim, cell = PathTerrain.TRIM, PathTerrain.CELL
	local function material(x: number, z: number): (string?, number)
		local dp, dz = sdf(x, z), plaza(x, z)
		local d = smin(dp, dz, plazaFillet)
		local occupancy = math.clamp(0.5 - d / cell, 0, 1)
		if occupancy <= 0.02 then
			return nil, 0
		end
		if dp <= -trim then
			return "Ground", occupancy
		end
		if dz <= -trim then
			return "Sand", occupancy
		end
		return "Mud", occupancy
	end
	return { sdf = sdf, plaza = plaza, material = material }
end

local fillCache: { Fill }? = nil

-- Every column the server writes, in z-outer order. Cell centres sit on the 4-stud grid.
function PathTerrain.fills(): { Fill }
	if fillCache then
		return fillCache
	end
	local field = PathTerrain.field()
	local cell, extent = PathTerrain.CELL, PathTerrain.EXTENT
	local out: { Fill } = {}
	for j = 0, 2 * extent / cell - 1 do
		local z = -extent + (j + 0.5) * cell
		for i = 0, 2 * extent / cell - 1 do
			local x = -extent + (i + 0.5) * cell
			local material, occupancy = field.material(x, z)
			if material and occupancy > 0.02 then
				table.insert(out, {
					x = x,
					z = z,
					material = material,
					occupancy = occupancy,
					top = PathTerrain.TOP,
				})
			end
		end
	end
	fillCache = out
	return out
end

return PathTerrain
