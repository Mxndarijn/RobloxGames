--!strict
-- Paths v2 geometry probe: the plaza sand, ring, spokes and slide-exit path are
-- terrain (shared/PathTerrain), not Parts. No path Part is left in the world; no
-- path column rises more than 0.05 above the Ground part's top (and none hides
-- under it: a full column is the walking surface); the Catmull-Rom sampling is
-- exact at its ends, continuous, evenly spaced, closed for the ring and
-- deterministic; every spoke reaches the ring and its plot's gate, and the
-- slide exit reaches spoke 1.
local Config = require("../src/shared/Config")
local PathTerrain = require("../src/visuals/shared/PathTerrain")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function walk(node: any, visit: (any) -> ())
	visit(node)
	for _, c in node.children or {} do
		walk(c, visit)
	end
end

local function groundTop(): number
	local top
	walk(WorldLayout.build()[1], function(n)
		if n.name == "Ground" then
			top = n.pos[2] + n.size[2] / 2
		end
	end)
	return top
end

local function curve(name: string): PathTerrain.Curve
	for _, c in PathTerrain.curves() do
		if c.name == name then
			return c
		end
	end
	error(`no curve {name}`)
end

local function dist(a: PathTerrain.Point, b: PathTerrain.Point): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

describe("path terrain spline", function()
	it("passes through both end points of an open spline", function()
		local controls = { { x = 0, z = 0 }, { x = 10, z = 4 }, { x = 20, z = 0 } }
		local pts = PathTerrain.sampleSpline(controls, false, 1)
		expect(dist(pts[1], controls[1]) < 1e-9).toBe(true)
		expect(dist(pts[#pts], controls[3]) < 1e-9).toBe(true)
	end)
	it("is continuous and evenly spaced", function()
		for _, c in PathTerrain.curves() do
			local n = #c.points
			local last = if c.closed then n else n - 1
			for i = 1, last do
				local d = dist(c.points[i], c.points[i % n + 1])
				expect(d <= PathTerrain.SPACING * 1.15).toBe(true)
				expect(d >= PathTerrain.SPACING * 0.5).toBe(true)
			end
		end
	end)
	it("closes the ring on r 78 with no repeated point", function()
		local ring = curve("Ring")
		expect(ring.closed).toBe(true)
		expect(dist(ring.points[1], ring.points[#ring.points]) > 0.5).toBe(true)
		for _, p in ring.points do
			expect(math.abs(math.sqrt(p.x ^ 2 + p.z ^ 2) - WorldLayout.RING_PATH_RADIUS) < 0.3).toBe(true)
		end
	end)
	it("samples identically every time", function()
		local controls = { { x = 1, z = 2 }, { x = 8, z = 9 }, { x = 15, z = 3 }, { x = 22, z = 11 } }
		local a = PathTerrain.sampleSpline(controls, false, 1.5)
		local b = PathTerrain.sampleSpline(controls, false, 1.5)
		expect(#a).toBe(#b)
		for i = 1, #a do
			expect(a[i].x).toBe(b[i].x)
			expect(a[i].z).toBe(b[i].z)
		end
	end)
	it("keeps the layout constants in step with WorldLayout", function()
		expect(PathTerrain.RING_RADIUS).toBe(WorldLayout.RING_PATH_RADIUS)
		expect(PathTerrain.PLAZA_RADIUS).toBe(WorldLayout.PLAZA_RADIUS)
		expect(PathTerrain.GATE_DISTANCE).toBe(WorldLayout.PLOT_RING_RADIUS - WorldLayout.PLOT_SIZE / 2)
		expect(math.abs(PathTerrain.EXIT_FROM - WorldLayout.LANDING_OUTER_RADIUS) < 0.1).toBe(true)
		expect(PathTerrain.EXIT_X).toBe(math.round(WorldLayout.SLIDE_PATH[#WorldLayout.SLIDE_PATH][1]))
		expect(PathTerrain.TOP).toBe(WorldLayout.PATH_TOPS.plaza)
	end)
end)

describe("path geometry probe (paths v2)", function()
	it("leaves no path Part or mesh in the world", function()
		walk(WorldLayout.build()[1], function(n)
			expect(n.name ~= "Paths").toBe(true)
			expect(string.match(n.name, "^Ring%d+$")).toBe(nil)
			expect(string.match(n.name, "^Path%d+$")).toBe(nil)
			expect(n.name ~= "SlideExit").toBe(true)
			expect(n.name ~= "Plaza" or n.class == "Folder").toBe(true)
		end)
	end)
	it("never lifts a path column more than 0.05 above the Ground, nor sinks one under it", function()
		local ground = groundTop()
		local fills = PathTerrain.fills()
		expect(#fills > 500).toBe(true)
		local full = 0
		for _, f in fills do
			expect(f.top - ground <= 0.05).toBe(true)
			if f.occupancy >= 1 then
				full += 1
				-- a full column is the surface: above the Ground part, by a hair
				expect(f.top - ground >= 0.02).toBe(true)
			end
		end
		expect(full > 500).toBe(true)
		-- the voxel box covers every fill
		for _, f in fills do
			expect(math.abs(f.x) < PathTerrain.EXTENT and math.abs(f.z) < PathTerrain.EXTENT).toBe(true)
		end
	end)
	it("paints each spoke's centreline from the ring to its plot's gate", function()
		local field = PathTerrain.field()
		local spokes = 0
		for _, c in PathTerrain.curves() do
			if c.kind ~= "spoke" then
				continue
			end
			spokes += 1
			local yaw = math.rad(((c.plot :: number) - 1) * 360 / Config.PLOT_COUNT)
			local sx, sz = math.sin(yaw), math.cos(yaw)
			local d = PathTerrain.SPOKE_START
			while d <= PathTerrain.GATE_DISTANCE - 0.01 do
				for _, off in { -3.5, 0, 3.5 } do
					expect(field.sdf(sx * d + sz * off, sz * d - sx * off) <= 0).toBe(true)
				end
				d += 0.5
			end
			-- the end of the line is the gate, and it crosses the ring path
			local tip = c.points[#c.points]
			expect(math.abs(tip.x * sx + tip.z * sz - PathTerrain.GATE_DISTANCE) < 1e-6).toBe(true)
			local ringHit = field.sdf(sx * WorldLayout.RING_PATH_RADIUS, sz * WorldLayout.RING_PATH_RADIUS)
			expect(ringHit <= -PathTerrain.RING_HALF_WIDTH + 0.5).toBe(true)
		end
		expect(spokes).toBe(Config.PLOT_COUNT)
	end)
	it("has no gap along the whole ring, edge to edge", function()
		local field = PathTerrain.field()
		for k = 0, 1439 do
			local a = 2 * math.pi * k / 1440
			for _, r in { 73.5, 78, 82.5 } do
				expect(field.sdf(math.sin(a) * r, math.cos(a) * r) <= 0).toBe(true)
			end
		end
	end)
	it("runs the slide exit from the curb to spoke 1 without a gap", function()
		local field = PathTerrain.field()
		local exit = curve("SlideExit")
		expect(math.abs(exit.points[1].z - WorldLayout.LANDING_OUTER_RADIUS) < 0.1).toBe(true)
		local z = WorldLayout.LANDING_OUTER_RADIUS
		while z <= PathTerrain.SPOKE_START + 10 do
			for _, off in { -3.5, 0, 3.5 } do
				expect(field.sdf(PathTerrain.EXIT_X + off, z) <= 0).toBe(true)
			end
			z += 0.25
		end
		-- the exit's far end sits on spoke 1's centreline
		local tip = exit.points[#exit.points]
		expect(math.abs(tip.x) < 1e-6).toBe(true)
		expect(tip.z > PathTerrain.SPOKE_START).toBe(true)
	end)
	it("rounds a fillet where a spoke meets the ring", function()
		local field = PathTerrain.field()
		-- the inside corner of the junction: a plain union would leave d > 0 here, the fillet fills it
		local corner = math.sqrt((PathTerrain.RING_HALF_WIDTH + 1) ^ 2 * 2)
		local x, z =
			PathTerrain.SPOKE_HALF_WIDTH + 0.5, WorldLayout.RING_PATH_RADIUS - PathTerrain.RING_HALF_WIDTH - 0.5
		local plain = math.max(
			math.abs(x) - PathTerrain.SPOKE_HALF_WIDTH,
			(WorldLayout.RING_PATH_RADIUS - PathTerrain.RING_HALF_WIDTH) - z
		)
		expect(corner > 0).toBe(true)
		expect(plain > 0).toBe(true)
		expect(field.sdf(x, z) < plain).toBe(true)
	end)
	it("is deterministic", function()
		local a = PathTerrain.field()
		local b = PathTerrain.field()
		for _, p in { { 12.3, 70.1 }, { -40.2, 77.7 }, { 3, 95 } } do
			expect(a.sdf(p[1], p[2])).toBe(b.sdf(p[1], p[2]))
		end
	end)
end)
