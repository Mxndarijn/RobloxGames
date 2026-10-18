--!strict
-- v31 bugs #13-15: the inner ground is voxel terrain (GroundTerrain, written by server/GroundTerrainView). One seamless
-- dirt shape (ring + eight spokes) with no Part tiles, a plaza of sand feathered ~7 studs into the
-- grass, grass everywhere else, flat on y = 0, deterministic, nothing grassy under a plot floor.
local Config = require("../src/shared/Config")
local GroundTerrain = require("../src/visuals/shared/GroundTerrain")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local grid = GroundTerrain.grid()

-- the material of the cell that holds the point (x, z)
local function cellAt(x: number, z: number): string
	local half, cell = GroundTerrain.HALF, GroundTerrain.CELL
	local i, j = math.floor((x + half) / cell), math.floor((z + half) / cell)
	return grid.materials[j * grid.n + i + 1]
end

local function count(name: string): number
	local c = 0
	for _, m in grid.materials do
		if m == name then
			c += 1
		end
	end
	return c
end

local function walk(node: any, visit: (any) -> ())
	visit(node)
	for _, c in node.children or {} do
		walk(c, visit)
	end
end

describe("GroundTerrain layout", function()
	it("covers the 640-stud Ground square with 160 x 160 cells of Grass / Ground / Sand", function()
		expect(grid.n).toBe(160)
		expect(#grid.materials).toBe(160 * 160)
		for _, m in grid.materials do
			expect(m == "Grass" or m == "Ground" or m == "Sand").toBe(true)
		end
		expect(count("Grass") > 8000).toBe(true)
		expect(count("Ground") > 1500).toBe(true)
		expect(count("Sand") > 700).toBe(true)
	end)
	it("is deterministic", function()
		local again = GroundTerrain.grid()
		for i, m in grid.materials do
			expect(again.materials[i]).toBe(m)
		end
	end)
	it("makes the whole ring one dirt band: every point of the centreline is Ground", function()
		for k = 0, 1439 do
			local a = 2 * math.pi * k / 1440
			local r = WorldLayout.RING_PATH_RADIUS
			expect(cellAt(math.sin(a) * r, math.cos(a) * r)).toBe("Ground")
		end
	end)
	it("keeps the ring's edge cells dirt too (3 studs off the centreline)", function()
		for _, r in { WorldLayout.RING_PATH_RADIUS - 3, WorldLayout.RING_PATH_RADIUS + 3 } do
			local ground = 0
			for k = 0, 719 do
				local a = 2 * math.pi * k / 720
				if cellAt(math.sin(a) * r, math.cos(a) * r) == "Ground" then
					ground += 1
				end
			end
			expect(ground > 450).toBe(true)
		end
	end)
	it("runs a dirt spoke from the plaza edge to each plot gate", function()
		local from, to = WorldLayout.PLAZA_RADIUS, WorldLayout.PLOT_RING_RADIUS - WorldLayout.PLOT_SIZE / 2
		for i = 1, Config.PLOT_COUNT do
			local yaw = math.rad((i - 1) * 360 / Config.PLOT_COUNT)
			local d = from
			while d <= to do
				expect(cellAt(math.sin(yaw) * d, math.cos(yaw) * d)).toBe("Ground")
				d += 0.5
			end
		end
	end)
	it("paints no dirt for the slide exit: the plaza sand runs straight to the landing ring (bug #6)", function()
		local exit = WorldLayout.SLIDE_PATH[#WorldLayout.SLIDE_PATH]
		local d = WorldLayout.LANDING_OUTER_RADIUS + 1
		while d <= GroundTerrain.SPOKE_START - 10 do
			expect(cellAt(exit[1], d) ~= "Ground").toBe(true)
			d += 0.5
		end
	end)
	it("is sand on the plaza between the fountain and the ring path, off the paths", function()
		expect(cellAt(0, -30)).toBe("Sand")
		expect(cellAt(-30, 0)).toBe("Sand")
		expect(cellAt(30, -20)).toBe("Sand")
		expect(cellAt(-20, 30)).toBe("Sand")
	end)
	it("is grass between spokes outside the plaza and far from the paths", function()
		expect(cellAt(200, 100)).toBe("Grass")
		expect(cellAt(-250, 280)).toBe("Grass")
		expect(cellAt(300, 300)).toBe("Grass")
		-- between the ring and the plots, off a spoke
		local a = math.rad(22.5)
		expect(cellAt(math.sin(a) * 95, math.cos(a) * 95)).toBe("Grass")
	end)
	it("never leaves grass under a plot floor (no tuft pokes through a plot Base or a pad)", function()
		local half = WorldLayout.PLOT_SIZE / 2 - 4
		local ring = WorldLayout.PLOT_RING_RADIUS
		for i = 1, Config.PLOT_COUNT do
			local a = math.rad((i - 1) * 360 / Config.PLOT_COUNT)
			local ux, uz = math.sin(a), math.cos(a)
			for along = -half, half, 2 do
				for across = -half, half, 2 do
					local x = ux * (ring + along) + uz * across
					local z = uz * (ring + along) - ux * across
					expect(cellAt(x, z) ~= "Grass").toBe(true)
				end
			end
		end
	end)
	it("feathers the plaza sand ~7 studs into the grass (10% to 90% sand within 5..10 studs)", function()
		-- sand share by radius over the arcs away from every spoke and the ring
		local per = {} -- radius bucket -> { sand, total }
		for deg = 0, 359, 1 do
			local off = (deg + 22.5) % 45 -- distance in degrees from the nearest spoke axis (spokes every 45)
			if math.abs(off - 22.5) < 14 then
				continue
			end
			local a = math.rad(deg)
			for r10 = 520, 760, 5 do
				local r = r10 / 10
				local m = cellAt(math.sin(a) * r, math.cos(a) * r)
				local b = per[r10] or { 0, 0 }
				per[r10] = b
				if m == "Sand" then
					b[1] += 1
				end
				if m ~= "Ground" then
					b[2] += 1
				end
			end
		end
		local inner, outer
		for r10 = 520, 760, 5 do
			local b = per[r10]
			local share = b[1] / math.max(b[2], 1)
			if share < 0.9 and not inner then
				inner = r10 / 10
			end
			if share < 0.1 and not outer then
				outer = r10 / 10
			end
		end
		expect(inner ~= nil and outer ~= nil).toBe(true)
		local width = (outer :: number) - (inner :: number)
		expect(width >= 5 and width <= 10).toBe(true)
	end)
	it("mixes Sand and Grass inside the feather band (a patchy dither, not a ring)", function()
		local sand, grass = 0, 0
		for deg = 0, 359 do
			local a = math.rad(deg + 0.5)
			local m = cellAt(math.sin(a) * 66, math.cos(a) * 66)
			if m == "Sand" then
				sand += 1
			elseif m == "Grass" then
				grass += 1
			end
		end
		expect(sand > 60 and grass > 60).toBe(true)
	end)
end)

describe("GroundTerrain voxels", function()
	it("tiles the Ground square exactly: 5 x 5 tiles of 32 x 32 cells", function()
		local tiles = GroundTerrain.tiles()
		expect(#tiles).toBe(25)
		local seen = {}
		for _, t in tiles do
			expect((t.x + 320) % 128).toBe(0)
			expect((t.z + 320) % 128).toBe(0)
			expect(t.x >= -320 and t.x < 320 and t.z >= -320 and t.z < 320).toBe(true)
			seen[`{t.x},{t.z}`] = true
		end
		expect(next(seen) ~= nil).toBe(true)
		local n = 0
		for _ in seen do
			n += 1
		end
		expect(n).toBe(25)
	end)
	it(
		"is flat at y = 0: columns fill from FLOOR to SURFACE in whole voxels, and meet the border terrain at the edge",
		function()
			expect(GroundTerrain.SURFACE).toBe(0)
			expect((GroundTerrain.SURFACE - GroundTerrain.FLOOR) % GroundTerrain.CELL).toBe(0)
			expect(GroundTerrain.HALF).toBe(320) -- BorderTerrain.INNER
		end
	)
	it("keeps the fill top at or below y = 0 on the voxel grid, with the rendered surface at the prop bases", function()
		local cell = GroundTerrain.CELL
		expect(GroundTerrain.SURFACE <= 0).toBe(true)
		expect(GroundTerrain.FLOOR % cell).toBe(0)
		expect(GroundTerrain.SURFACE % cell).toBe(0)
		for _, t in GroundTerrain.tiles() do
			-- GroundTerrainView's Region3 corners: (x, FLOOR, z) .. (x + 32 cells, SURFACE, z + 32 cells)
			for _, v in { t.x, t.z, t.x + GroundTerrain.TILE_CELLS * cell } do
				expect(v % cell).toBe(0)
			end
		end
		expect(GroundTerrain.TOP_OCCUPANCY > 0 and GroundTerrain.TOP_OCCUPANCY < 1).toBe(true)
		expect(GroundTerrain.RENDER_SURFACE <= GroundTerrain.SURFACE).toBe(true)
		expect(GroundTerrain.RENDER_SURFACE).toBe(0) -- the ground reads as y = 0 where characters and props stand
		-- no prop that stands on the ground (not the deliberately sunk rocks, fountain, vat or leaf bunches) has a base more than 0.25 under the surface (Phoenix's post-publish tolerance); the plot Base floor top (1) is above it
		local lowest = math.huge
		walk({ children = WorldLayout.build() }, function(n)
			if n.pos and n.size and n.name and n.name ~= "Ground" then
				local base = n.pos[2] - n.size[2] / 2
				if base > -0.5 and base < lowest then
					lowest = base
				end
			end
		end)
		expect(GroundTerrain.RENDER_SURFACE <= lowest + 0.25).toBe(true)
	end)
	it(
		"is a pure module: no dirt path parts (Ring / Path / SlideExit), and the Ground part is invisible void-safety",
		function()
			local found = {}
			walk({ children = WorldLayout.build() }, function(n)
				if n.name then
					found[n.name] = n
				end
			end)
			expect(found.Ring1).toBe(nil)
			expect(found.Path1).toBe(nil)
			expect(found.SlideExit).toBe(nil)
			expect(found.Ground ~= nil).toBe(true)
			expect(found.Ground.transparency).toBe(1)
			expect(found.Ground.pos[2] + found.Ground.size[2] / 2).toBe(0)
		end
	)
	it("tints the three materials with the pastel palette", function()
		for _, name in { "Grass", "Ground", "Sand" } do
			local light, dark = GroundTerrain.COLORS[name], GroundTerrain.DARK[name]
			for c = 1, 3 do
				expect(dark[c] <= light[c]).toBe(true)
			end
		end
	end)
end)
