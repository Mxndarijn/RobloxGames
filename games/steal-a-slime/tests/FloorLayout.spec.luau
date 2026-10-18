--!strict
-- B11 floor (src/visuals/shared/FloorLayout): the sand yard, grass border band, plaza deck, boardwalk, lawns and gate ramps on
-- top of the voxel terrain. One height constant, flush layers, no trip lips, snow v2 opt-in, the terrain-grass swap, budgets.
local Config = require("../src/shared/Config")
local FloorLayout = require("../src/visuals/shared/FloorLayout")
local GroundTerrain = require("../src/visuals/shared/GroundTerrain")
local Meadow = require("../src/visuals/shared/Meadow")
local MeshAssets = require("../src/shared/MeshAssets")
local SnowCover = require("../src/visuals/shared/SnowCover")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")
local YardProps = require("../src/visuals/shared/YardProps")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function geometry(): any
	return {
		ringRadius = WorldLayout.RING_PATH_RADIUS,
		ringWidth = WorldLayout.RING_PATH_WIDTH,
		plazaRadius = WorldLayout.PLAZA_RADIUS,
		plotRing = WorldLayout.PLOT_RING_RADIUS,
		plotSize = WorldLayout.PLOT_SIZE,
		plotFloorTop = WorldLayout.PLOT_FLOOR_TOP,
		plots = Config.PLOT_COUNT,
	}
end

local function walk(node: any, fn: (any) -> ())
	fn(node)
	for _, c in node.children or {} do
		walk(c, fn)
	end
end

local function floorParts(): { any }
	local out = {}
	for _, folder in FloorLayout.build(geometry()) do
		walk(folder, function(n)
			if n.class == "Part" then
				table.insert(out, n)
			end
		end)
	end
	return out
end

local function folder(name: string): any
	for _, f in FloorLayout.build(geometry()) do
		if f.name == name then
			return f
		end
	end
	return nil
end

local function mapChild(name: string): any
	for _, c in WorldLayout.build()[1].children do
		if c.name == name then
			return c
		end
	end
	return nil
end

describe("FloorLayout height", function()
	it("keeps the layer tops strictly rising, by at least 0.025, and under the trim top", function()
		local order = { "band", "hem", "sand", "disc", "lawn", "plank", "trim" }
		for i = 2, #order do
			expect(FloorLayout.LAYER[order[i]] - FloorLayout.LAYER[order[i - 1]] >= 0.025 - 1e-9).toBe(true)
		end
		expect(FloorLayout.LAYER.trim <= 0.25).toBe(true)
	end)
	it("puts every flat part's top on FLOOR_Y + its layer, and the mesh slots' bottoms on FLOOR_Y", function()
		local tops = { FieldBand = "band", FieldHem = "hem", FieldSand = "sand", PlazaDisc = "disc" }
		for _, n in floorParts() do
			local top = n.pos[2] + n.size[2] / 2
			if tops[n.name] then
				-- a Cylinder is rolled 90 degrees about Z: its thickness is size[1], along world Y
				expect(n.pos[2] + n.size[1] / 2).toBeCloseTo(
					FloorLayout.FLOOR_Y + FloorLayout.LAYER[tops[n.name]],
					1e-6
				)
			elseif string.match(n.name, "^Lawn") then
				expect(math.abs(top - (FloorLayout.FLOOR_Y + FloorLayout.LAYER.lawn)) <= FloorLayout.LAWN_STEP + 1e-9).toBe(
					true
				)
			elseif n.attributes.MeshAsset then
				expect(n.pos[2] - n.size[2] / 2).toBeCloseTo(FloorLayout.FLOOR_Y, 1e-6)
			end
		end
	end)
	it("moves the whole floor with the ONE constant FLOOR_Y (the gate ramps still end on the plot floor)", function()
		local before = {}
		for _, n in floorParts() do
			before[n.name] = { n.pos[1], n.pos[2], n.pos[3] }
		end
		local old = FloorLayout.FLOOR_Y
		FloorLayout.FLOOR_Y = old + 3
		local moved = floorParts()
		FloorLayout.FLOOR_Y = old
		for _, n in moved do
			local b = before[n.name]
			if string.match(n.name, "^GateRamp") then
				continue
			end
			expect(n.pos[2] - b[2]).toBeCloseTo(3, 1e-9)
			expect(n.pos[1]).toBeCloseTo(b[1], 1e-9)
			expect(n.pos[3]).toBeCloseTo(b[3], 1e-9)
		end
	end)
end)

describe("FloorLayout walkability", function()
	it("collides nowhere except the gate ramps; nothing queries or touches", function()
		for _, n in floorParts() do
			expect(n.canQuery).toBe(false)
			expect(n.canTouch).toBe(false)
			expect(n.canCollide).toBe(string.match(n.name, "^GateRamp") ~= nil)
		end
	end)
	it("keeps every floor surface within the trim top: no lip over the terrain", function()
		for _, n in floorParts() do
			if string.match(n.name, "^GateRamp") then
				continue
			end
			local top = if n.shape == "Cylinder" then n.pos[2] + n.size[1] / 2 else n.pos[2] + n.size[2] / 2
			expect(top <= FloorLayout.FLOOR_Y + FloorLayout.LAYER.trim + 1e-9).toBe(true)
		end
	end)
	it(
		"has Base floors at WorldLayout.PLOT_FLOOR_TOP, and one ramp per gate climbing flush from the planks to it",
		function()
			local plots = WorldLayout.build()[2]
			local checked = 0
			for _, plot in plots.children do
				for _, c in plot.children or {} do
					if c.name == "Base" then
						expect(c.pos[2] + c.size[2] / 2).toBeCloseTo(WorldLayout.PLOT_FLOOR_TOP, 1e-9)
						checked += 1
					end
				end
			end
			expect(checked).toBe(Config.PLOT_COUNT)
			local ramps = 0
			for _, n in folder("Paths").children do
				if string.match(n.name, "^GateRamp%d+$") then
					ramps += 1
					-- rotation about X tilts +Z up: the top line runs from (RAMP_START, plank top) to (RAMP_END, floor top)
					local tilt = math.rad(-n.rot[1])
					local bearing = math.rad(n.rot[2])
					local length, t = n.size[3], n.size[2]
					local sc = n.pos[1] * math.sin(bearing) + n.pos[3] * math.cos(bearing) -- distance along the spoke
					local topLowS = sc - math.cos(tilt) * length / 2 - math.sin(tilt) * t / 2
					local topLowY = n.pos[2] - math.sin(tilt) * length / 2 + math.cos(tilt) * t / 2
					local topHighS = sc + math.cos(tilt) * length / 2 - math.sin(tilt) * t / 2
					local topHighY = n.pos[2] + math.sin(tilt) * length / 2 + math.cos(tilt) * t / 2
					expect(topLowS).toBeCloseTo(FloorLayout.RAMP_START, 1e-6)
					expect(topLowY).toBeCloseTo(FloorLayout.FLOOR_Y + FloorLayout.LAYER.plank, 1e-6)
					expect(topHighS).toBeCloseTo(FloorLayout.RAMP_END, 1e-6)
					expect(topHighY).toBeCloseTo(WorldLayout.PLOT_FLOOR_TOP, 1e-6)
					expect(math.deg(tilt) < 15).toBe(true)
				end
			end
			expect(ramps).toBe(Config.PLOT_COUNT)
			-- the ramp ends where the plot's Base floor begins (plot centre minus half the plot)
			expect(FloorLayout.RAMP_END).toBe(WorldLayout.PLOT_RING_RADIUS - WorldLayout.PLOT_SIZE / 2)
		end
	)
	it(
		"keeps the lawns off the spokes (corners 6.5+ studs from every centre line), inside the wedge band, clear of the ramps",
		function()
			local g = geometry()
			local step = 360 / g.plots
			for _, n in folder("Lawns").children do
				local x, z = n.pos[1], n.pos[3]
				local r = math.sqrt(x * x + z * z)
				expect(r >= FloorLayout.LAWN_R0 and r <= FloorLayout.LAWN_R1).toBe(true)
				-- the block's four corners
				local yaw = math.rad(n.rot[2])
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local lx, lz = sx * n.size[1] / 2, sz * n.size[3] / 2
						local cx = x + lx * math.cos(yaw) + lz * math.sin(yaw)
						local cz = z - lx * math.sin(yaw) + lz * math.cos(yaw)
						for k = 0, g.plots - 1 do
							local b = math.rad(step * k)
							local along = cx * math.sin(b) + cz * math.cos(b)
							local across = math.abs(cx * math.cos(b) - cz * math.sin(b))
							if along > 0 then
								expect(across >= 6.5).toBe(true)
							end
						end
					end
				end
			end
		end
	)
end)

describe("FloorLayout meshes", function()
	it("sizes the two slots to the native size of the kit meshes, and the entries agree", function()
		local sizes = { ranch_floor_deck = FloorLayout.DECK_SIZE, ranch_floor_paths = FloorLayout.PATH_SIZE }
		for name, size in sizes do
			local entry = MeshAssets.get(name)
			expect(entry ~= nil).toBe(true)
			for i = 1, 3 do
				expect((entry :: any).size[i]).toBeCloseTo(size[i], 0.01)
			end
		end
	end)
	it("centres both slots on the hub, invisible, never solid, tinted by the slot colour, one per mesh", function()
		local seen = {}
		for _, n in folder("Paths").children do
			if n.attributes.MeshAsset then
				seen[n.attributes.MeshAsset] = n
				expect(n.pos[1]).toBe(0)
				expect(n.pos[3]).toBe(0)
				expect(n.transparency).toBe(1)
				expect(n.canCollide).toBe(false)
				expect(n.attributes.MeshTint).toBe(true)
			end
		end
		expect(seen.ranch_floor_deck ~= nil and seen.ranch_floor_paths ~= nil).toBe(true)
	end)
	it("is decor in MeshAssets.COLLISION (the terrain is the walk surface)", function()
		expect(MeshAssets.COLLISION.ranch_floor_deck).toBe(nil)
		expect(MeshAssets.COLLISION.ranch_floor_paths).toBe(nil)
	end)
end)

describe("FloorLayout snow v2", function()
	it(
		"declares a SnowKind on every part, and SnowCover.classify follows it (grass white, paths frosted, slots skipped)",
		function()
			for _, n in floorParts() do
				local kind = n.attributes[FloorLayout.SNOW_KIND_ATTRIBUTE]
				expect(kind == "grass" or kind == "path").toBe(true)
				local got =
					SnowCover.classify(n.name, n.material, false, n.size[1], n.size[3], n.transparency or 0, kind)
				if n.transparency == 1 then
					expect(got).toBe(nil) -- the hidden slot; its MeshPart child takes the slot's kind (SnowGround)
				else
					expect(got).toBe(kind)
				end
			end
		end
	)
	it(
		"makes the sand yard and the lawns grass-class (fully white, melt last) and the walked surfaces path-class",
		function()
			local kinds = {}
			for _, n in floorParts() do
				kinds[string.gsub(n.name, "%d+_?%d*$", "")] = n.attributes.SnowKind
			end
			expect(kinds.FieldSand).toBe("grass")
			expect(kinds.FieldBand).toBe("grass")
			expect(kinds.Lawn).toBe("grass")
			expect(kinds.Boardwalk).toBe("path")
			expect(kinds.DeckPlaza).toBe("path")
			expect(kinds.PlazaDisc).toBe("path")
			expect(kinds.GateRamp).toBe("path")
			expect(kinds.FieldHem).toBe("path")
		end
	)
	it("lets an explicit SnowKind override the guess, and 'none' opts out", function()
		expect(SnowCover.classify("Anything", "SmoothPlastic", false, 4, 4, 0, "grass")).toBe("grass")
		expect(SnowCover.classify("Anything", "Grass", false, 100, 100, 0, "none")).toBe(nil)
		expect(SnowCover.classify("Pad_1", "SmoothPlastic", false, 4, 4, 0, nil)).toBe("path")
		expect(SnowCover.classify("Anything", "SmoothPlastic", false, 4, 4, 1, "grass")).toBe(nil)
	end)
	it(
		"frosts a baked mesh by lerping its slot colour toward white, which brightens every vertex-colour ratio",
		function()
			local base = FloorLayout.COLORS.pathBase
			local ratios = { 0.96, 0.82, 0.55 } -- plank, plank B, rail (kit vertex colours are <= 1)
			local w = SnowCover.tints(1, true).path
			local r, g, b = SnowCover.lerpColor(base[1] / 255, base[2] / 255, base[3] / 255, w)
			for _, k in ratios do
				expect(r * k > base[1] / 255 * k).toBe(true)
				expect(g * k > base[2] / 255 * k).toBe(true)
				expect(b * k > base[3] / 255 * k).toBe(true)
			end
			local r0, g0, b0 = SnowCover.lerpColor(base[1] / 255, base[2] / 255, base[3] / 255, 0)
			expect(r0).toBeCloseTo(base[1] / 255, 1e-12) -- level 0 restores the colour bit for bit
			expect(g0).toBeCloseTo(base[2] / 255, 1e-12)
			expect(b0).toBeCloseTo(base[3] / 255, 1e-12)
		end
	)
end)

describe("FloorLayout terrain grass swap", function()
	it("covers the whole yard and border band, and stops where the border wall ring begins", function()
		expect(FloorLayout.FIELD_RADIUS > 184.4 + 20).toBe(true) -- past the plots' outer corners and fences
		expect(FloorLayout.HEM_RADIUS > FloorLayout.FIELD_RADIUS).toBe(true)
		expect(FloorLayout.BAND_RADIUS > FloorLayout.TERRAIN_SAND_RADIUS).toBe(true)
		expect(FloorLayout.TERRAIN_SAND_RADIUS > 292).toBe(true) -- WorldBorder.RADIUS
		expect(FloorLayout.TERRAIN_SAND_RADIUS + 3 < GroundTerrain.HALF).toBe(true)
	end)
	it("swaps exactly the Grass cells inside the radius, and terrainRows names exactly those cells", function()
		local grid = GroundTerrain.grid()
		local inRows = {}
		for _, row in FloorLayout.terrainRows() do
			expect(row.x0 % 4).toBe(0)
			expect(row.x1 % 4).toBe(0)
			expect(row.z0 % 4).toBe(0)
			expect(row.x0).toBe(-row.x1)
			local zc = row.z0 + 2
			local x = row.x0 + 2
			while x < row.x1 do
				inRows[`{x},{zc}`] = true
				x += 4
			end
		end
		local swapped = 0
		for j = 0, grid.n - 1 do
			for i = 0, grid.n - 1 do
				local x, z = grid.min + i * grid.cell, grid.min + j * grid.cell
				local m = grid.materials[j * grid.n + i + 1]
				local out = FloorLayout.groundMaterial(x, z, m)
				if m ~= "Grass" then
					expect(out).toBe(m)
				elseif x * x + z * z <= FloorLayout.TERRAIN_SAND_RADIUS ^ 2 then
					expect(out).toBe("Sand")
					swapped += 1
				else
					expect(out).toBe("Grass")
				end
				expect(inRows[`{x},{z}`] == true).toBe(x * x + z * z <= FloorLayout.TERRAIN_SAND_RADIUS ^ 2)
			end
		end
		expect(swapped > 1000).toBe(true)
	end)
	it("leaves no Grass voxel under any floor part except the band's own outer fringe", function()
		local grid = GroundTerrain.grid()
		for j = 0, grid.n - 1 do
			for i = 0, grid.n - 1 do
				local x, z = grid.min + i * grid.cell, grid.min + j * grid.cell
				local r = math.sqrt(x * x + z * z)
				local out = FloorLayout.groundMaterial(x, z, grid.materials[j * grid.n + i + 1])
				if r + 2.9 <= FloorLayout.BAND_RADIUS - 2 then -- whole cell under the band, clear of its outer fringe
					expect(out ~= "Grass").toBe(true)
				end
			end
		end
	end)
	it("moves the meadow out to the grass band", function()
		expect(Meadow.INNER > FloorLayout.HEM_RADIUS).toBe(true)
		expect(Meadow.OUTER <= FloorLayout.BAND_RADIUS).toBe(true)
	end)
end)

describe("FloorLayout budget", function()
	it("adds a handful of parts: field 3, paths 11, lawns 32, yard patches (YardProps.PATCHES)", function()
		expect(#folder("Field").children).toBe(3)
		expect(#folder("YardPatches").children).toBe(#YardProps.PATCHES)
		expect(#folder("Paths").children).toBe(3 + Config.PLOT_COUNT)
		expect(#folder("Lawns").children).toBe(FloorLayout.LAWN_BLOCKS * Config.PLOT_COUNT)
		expect(#floorParts()).toBe(
			3 + 3 + Config.PLOT_COUNT + FloorLayout.LAWN_BLOCKS * Config.PLOT_COUNT + #YardProps.PATCHES
		)
	end)
	it("is built into Map as Field / Paths / Lawns / YardPatches with unique names", function()
		for _, name in { "Field", "Paths", "Lawns", "YardPatches" } do
			expect(mapChild(name) ~= nil).toBe(true)
		end
		local seen = {}
		for _, n in floorParts() do
			expect(seen[n.name]).toBe(nil)
			seen[n.name] = true
		end
	end)
end)
