--!strict
-- Border terrain (BorderTerrain): the seeded hills behind the world border are
-- voxel terrain written at server start. They cost no mesh slot and no part,
-- vary in height / width / spacing without repeating a profile run, leave the
-- whole Ground square (paths, plots, plaza, slide, parade lane, border decor)
-- alone, and stay below the invisible walls.
local BorderTerrain = require("../src/visuals/shared/BorderTerrain")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")
local WorldBorder = require("../src/visuals/shared/WorldBorder")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- tools/pr-gate/budget_counts: mesh slots with the 20 giant trees and 66 decor pieces of the border
-- (the terrain itself adds none).
local BASELINE_MESH_SLOTS = 421 -- the Hall of Fame dressing (8 lanterns, 4 benches, 6 planters), the five Hall of Fame boards, the Upcoming Events board and Professor Goo (PROP_MESHES), the goo jar tower's 9 look slots a plot (foot, glass, trim, mascot, door, ring, two stoppers, button; no SlimeDex board), the border's 86 slots, the Upgrade Shop stand (CONTRACT.md §27.2), the Guide skin and its 6-prop corner, the floor's deck and boardwalk and the sand yard's dressing (YardProps: 66 props) included
-- Part nodes outside Map.Border: 1332 (main, after the SlideExit strip went) minus the 41 path / plaza parts that became GroundTerrain voxels, minus the 40 invisible plot Wall* blocks (bug #11).
local BASELINE_PARTS = 1386 -- the gate ramps' planks and rails (4 a gate) + the Hall of Fame floor (rim, floor, stage disc, the star walk: cream walk, two borders, 7 stars of 10 wedges) and its 18 dressing slots + the goo jar tower plots (the door bridge's planks and rails, 12 collision segments + door jambs, the open door collider, the look slots, a lamp per jar, the round PlotFloor, the sign's cradle and two stubs; the SlimeDex board and the rebirth decor gone) + the Guide's 6-prop corner + 1251 + the B11 floor (FloorLayout: 3 field discs, plaza disc, 2 mesh slots, 8 gate ramps, 32 lawn blocks) and the meadow it moved + the sand yard's 66 props (YardProps) minus the scattered rocks / mushrooms that made room (one for the Upcoming Events board, one for the Exclusive Shop jar spot and the moved well) + a flat-top collider per mushroom + the yard trees' trunk posts (WorldLayout.TREE_TRUNKS)

local field = BorderTerrain.field()
local INNER = BorderTerrain.INNER

local function walk(node: any, visit: (any, boolean) -> (), inBorder: boolean?)
	visit(node, inBorder == true)
	for _, c in node.children or {} do
		walk(c, visit, inBorder or (node.name == WorldLayout.MAP_NAME and c.name == "Border"))
	end
end

local function stdev(values: { number }): number
	local mean = 0
	for _, v in values do
		mean += v
	end
	mean /= #values
	local sum = 0
	for _, v in values do
		sum += (v - mean) ^ 2
	end
	return math.sqrt(sum / #values)
end

local function range(values: { number }): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, v in values do
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	return lo, hi
end

describe("BorderTerrain budget", function()
	it(
		"adds no mesh slot of its own: the world's mesh slot count stays at its baseline, under MESH_SLOT_BUDGET",
		function()
			local slots = 0
			walk({ name = "root", children = WorldLayout.build() }, function(n)
				local a = n.attributes or {}
				if type(a.MeshAsset or a.BorderMesh) == "string" then
					slots += 1
				end
			end)
			for _ in WorldLayout.PROP_MESHES do
				slots += 1
			end
			slots += WorldLayout.RUNTIME_SLOT_ALLOWANCE
			expect(slots).toBe(BASELINE_MESH_SLOTS)
			expect(slots < WorldLayout.MESH_SLOT_BUDGET).toBe(true)
		end
	)
	it("adds no part: the world keeps its build parts, under PART_BUDGET", function()
		local parts = 0
		walk({ name = "root", children = WorldLayout.build() }, function(n, inBorder)
			if n.class == "Part" and not inBorder then
				parts += 1
			end
		end)
		expect(parts).toBe(BASELINE_PARTS)
		expect(parts < WorldLayout.PART_BUDGET).toBe(true)
	end)
end)

describe("BorderTerrain determinism", function()
	it("gives the same hills for one seed and other hills for another", function()
		expect(BorderTerrain.field().hills).toEqual(field.hills)
		local other = BorderTerrain.field(7)
		local same = #other.hills == #field.hills
		if same then
			for i, h in other.hills do
				same = same and math.abs(h.x - field.hills[i].x) < 1e-6
			end
		end
		expect(same).toBe(false)
		expect(field.height(400, 410)).toBe(BorderTerrain.field().height(400, 410))
	end)
end)

describe("BorderTerrain hills", function()
	local function layer(name: string)
		local out = {}
		for _, h in field.hills do
			if h.layer == name then
				table.insert(out, h)
			end
		end
		return out
	end

	it("has a ring of near and mid hills and of tall peaks behind them", function()
		expect(#layer("near") >= 12).toBe(true)
		expect(#layer("mid") >= 8).toBe(true)
		expect(#layer("peak") >= 10).toBe(true)
	end)
	it("varies height, width and spacing", function()
		for _, name in { "near", "mid", "peak" } do
			local hills = layer(name)
			local heights, widths, gaps = {}, {}, {}
			for i, h in hills do
				table.insert(heights, h.height)
				table.insert(widths, h.along)
				local nxt = hills[i % #hills + 1]
				table.insert(gaps, math.sqrt((h.x - nxt.x) ^ 2 + (h.z - nxt.z) ^ 2))
			end
			local lo, hi = range(heights)
			expect(hi - lo >= 15).toBe(true)
			expect(stdev(heights) >= 6).toBe(true)
			expect(stdev(widths) >= 15).toBe(true)
			expect(stdev(gaps) >= 12).toBe(true)
		end
	end)
	it("never repeats a window of WINDOW neighbours' (height, width) profile", function()
		local W = BorderTerrain.WINDOW
		for _, name in { "near", "mid", "peak" } do
			local hills = layer(name)
			local n = #hills
			local seen: { [string]: number } = {}
			for start = 1, n do
				local run = {}
				for j = 0, W - 1 do
					local h = hills[(start + j - 1) % n + 1]
					table.insert(run, `{h.hBucket}|{h.wBucket}`)
				end
				local key = table.concat(run, "/")
				seen[key] = (seen[key] or 0) + 1
			end
			for key, times in seen do
				expect(`{name} {key} x{times}`).toBe(`{name} {key} x1`)
			end
		end
	end)
	it("keeps the land near the walls no taller than MAX_HEIGHT, well under the 80-stud walls", function()
		local grid = BorderTerrain.sample(field, 16)
		local near = {}
		for j = 0, grid.n - 1 do
			for i = 0, grid.n - 1 do
				local x, z = grid.min + i * grid.step, grid.min + j * grid.step
				if math.max(math.abs(x), math.abs(z)) <= INNER + BorderTerrain.PEAK_CLEAR then
					table.insert(near, grid.heights[j * grid.n + i + 1])
				end
			end
		end
		local _, hi = range(near)
		expect(hi <= BorderTerrain.MAX_HEIGHT).toBe(true)
		expect(hi >= 40).toBe(true)
		expect(BorderTerrain.MAX_HEIGHT <= WorldBorder.WALL_HEIGHT - 10).toBe(true)
	end)
	it("raises the mountains well above the walls, never past FAR_MAX_HEIGHT", function()
		local grid = BorderTerrain.sample(field, 16)
		local _, hi = range(grid.heights)
		expect(hi <= BorderTerrain.FAR_MAX_HEIGHT).toBe(true)
		expect(hi >= 2 * WorldBorder.WALL_HEIGHT).toBe(true)
		-- the v4 peak layer alone still stays under its own ceiling
		local _, peakHi = range((function()
			local tops: { number } = {}
			for _, h in field.hills do
				if h.layer == "peak" then
					table.insert(tops, h.height)
				end
			end
			return tops
		end)())
		expect(peakHi <= BorderTerrain.PEAK_MAX_HEIGHT).toBe(true)
	end)
	it("v6 outer ring: far mountains stand well behind the peaks, taller on average, each its own size", function()
		local far, peaks = {}, {}
		local sizes: { [string]: boolean } = {}
		for _, h in field.hills do
			if h.layer == "far" then
				table.insert(far, h)
				sizes[`{h.hBucket}|{h.wBucket}`] = true
				-- feet well out past the peaks' inner edge, whatever the footprint
				expect(math.max(math.abs(h.x), math.abs(h.z)) >= INNER + BorderTerrain.PEAK_CLEAR + 300).toBe(true)
			elseif h.layer == "peak" then
				table.insert(peaks, h)
			end
		end
		expect(#far >= 10).toBe(true)
		local n = 0
		for _ in sizes do
			n += 1
		end
		expect(n >= 5).toBe(true)
		local function mean(list: { any }): number
			local sum = 0
			for _, h in list do
				sum += h.height
			end
			return sum / #list
		end
		expect(mean(far) > mean(peaks)).toBe(true)
		local lo, hi = math.huge, 0
		for _, h in far do
			local top = field.height(h.x, h.z)
			lo, hi = math.min(lo, top), math.max(hi, top)
		end
		expect(lo >= 100).toBe(true)
		expect(hi - lo >= 60).toBe(true)
	end)
	it("v6 outer ridge ring and the far mountains die down before the edge of the written box", function()
		local E = BorderTerrain.EXTENT
		local worst = 0
		for t = -E + 2, E - 2, 16 do
			for _, p in { { t, E - 2 }, { t, 2 - E }, { E - 2, t }, { 2 - E, t } } do
				worst = math.max(worst, field.height(p[1], p[2]))
			end
		end
		expect(worst <= 24).toBe(true)
	end)
	it("keeps every mountain's foot past PEAK_CLEAR so the low land is all a player could ever near", function()
		for _, h in field.hills do
			if h.layer == "peak" then
				for a = 0, 355, 5 do
					local rad = math.rad(a)
					-- the rim of the footprint ellipse (long axis tangent, yaw degrees)
					local yaw = math.rad(h.yaw)
					local lx, lz = math.cos(rad) * h.across, math.sin(rad) * h.along
					local x = h.x + lx * math.cos(yaw) + lz * math.sin(yaw)
					local z = h.z - lx * math.sin(yaw) + lz * math.cos(yaw)
					expect(math.max(math.abs(x), math.abs(z)) >= INNER + BorderTerrain.PEAK_CLEAR).toBe(true)
				end
			end
		end
	end)
	it("layers the peaks behind the hills: taller than the ridge ring at their crest, many different peaks", function()
		local tops: { number } = {}
		for _, h in field.hills do
			if h.layer == "peak" then
				table.insert(tops, field.height(h.x, h.z))
			end
		end
		local lo, hi = range(tops)
		expect(lo >= 60).toBe(true)
		expect(hi >= 150).toBe(true)
		expect(hi - lo >= 60).toBe(true)
		-- no two peak crests at the same height (the far mountains may overlap and lift a few)
		table.sort(tops)
		for i = 2, #tops do
			expect(math.abs(tops[i] - tops[i - 1]) > 0.1).toBe(true)
		end
	end)
	it("wears rock on the upper slopes and grass on the lower ones of a mountain", function()
		-- a tall peak (>= 120) standing furthest from every far mountain, whose flanks would add rock to a foot
		local tallest, best = nil, -1
		for _, h in field.hills do
			if h.layer == "peak" and h.height >= 120 then
				local nearest = math.huge
				for _, f in field.hills do
					if f.layer == "far" then
						nearest = math.min(nearest, math.sqrt((f.x - h.x) ^ 2 + (f.z - h.z) ^ 2))
					end
				end
				if nearest > best then
					tallest, best = h, nearest
				end
			end
		end
		local rockLow, lows, grassHigh = 0, 0, 0
		for dx = -200, 200, 8 do
			for dz = -200, 200, 8 do
				local x, z = tallest.x + dx, tallest.z + dz
				local h = field.height(x, z)
				if h > 110 and (field.material(x, z) == "Grass" or field.material(x, z) == "LeafyGrass") then
					grassHigh += 1
				elseif h > 3 and h < 25 then
					lows += 1
					if field.material(x, z) == "Rock" then
						rockLow += 1
					end
				end
			end
		end
		expect(grassHigh).toBe(0)
		expect(lows >= 100 and rockLow <= lows * 0.2).toBe(true)
	end)
	it("closes the horizon: every bearing has a crest, none the same height", function()
		local crests = {}
		for a = 0, 359, 3 do
			local best = 0
			for r = 330, 900, 10 do
				local x, z = math.sin(math.rad(a)) * r, math.cos(math.rad(a)) * r
				best = math.max(best, field.height(x, z))
			end
			table.insert(crests, best)
		end
		local lo, hi = range(crests)
		expect(lo >= 20).toBe(true)
		expect(hi - lo >= 15).toBe(true)
		expect(stdev(crests) >= 5).toBe(true)
	end)
	it("blends Grass, LeafyGrass and Rock tinted to the ranch palette", function()
		local grid = BorderTerrain.sample(field, 16)
		local used: { [string]: number } = {}
		for i, m in grid.materials do
			if grid.heights[i] > 0 then
				used[m] = (used[m] or 0) + 1
			end
		end
		for name in used do
			expect(BorderTerrain.COLORS[name] ~= nil).toBe(true)
		end
		expect((used.Grass or 0) > 0 and (used.LeafyGrass or 0) > 0 and (used.Rock or 0) > 0).toBe(true)
		expect(BorderTerrain.COLORS.Grass).toEqual({ 162, 206, 118 })
	end)
	it("is covered by the tiles the server writes", function()
		local tiles = BorderTerrain.tiles()
		local size = BorderTerrain.TILE_CELLS * BorderTerrain.CELL
		expect(#tiles > 0).toBe(true)
		local grid = BorderTerrain.sample(field, 16)
		for j = 0, grid.n - 1 do
			for i = 0, grid.n - 1 do
				if grid.heights[j * grid.n + i + 1] > 0 then
					local x, z = grid.min + i * grid.step, grid.min + j * grid.step
					local hit = false
					for _, t in tiles do
						if x >= t.x and x < t.x + size and z >= t.z and z < t.z + size then
							hit = true
							break
						end
					end
					expect(hit).toBe(true)
				end
			end
		end
	end)
end)

describe("BorderTerrain clearance", function()
	it("leaves the whole Ground square bare", function()
		for x = -INNER, INNER, 8 do
			for z = -INNER, INNER, 8 do
				expect(field.height(x, z)).toBe(0)
			end
		end
	end)
	it("rises from flush at the Ground edge", function()
		for t = -INNER, INNER, 10 do
			expect(field.height(INNER + 1, t) < 0.5).toBe(true)
			expect(field.height(t, -INNER - 1) < 0.5).toBe(true)
		end
	end)
	it("stays off every world part (plots, plaza, paths, slide) and clear of the walls", function()
		local worst = 0
		walk({ name = "root", children = WorldLayout.build() }, function(n, inBorder)
			if n.class ~= "Part" or inBorder or n.name == "Ground" then
				return
			end
			local pos, size = n.pos or { 0, 0, 0 }, n.size or { 1, 1, 1 }
			local m = LayoutMath.orientation(n.rot or { 0, 0, 0 })
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local v = LayoutMath.apply(m, { sx * size[1] / 2, 0, sz * size[3] / 2 })
					local x, z = pos[1] + v[1], pos[3] + v[3]
					worst = math.max(worst, math.abs(x), math.abs(z))
					expect(field.height(x, z)).toBe(0)
				end
			end
		end)
		for _, c in WorldBorder.colliders() do
			expect(field.height(c.pos[1], c.pos[3])).toBe(0)
		end
		-- the nearest terrain is a long way past the wall
		expect(INNER - (WorldBorder.RADIUS + WorldBorder.WALL_THICKNESS) >= 20).toBe(true)
		expect(worst < INNER).toBe(true)
	end)
	it("stays off the parade lane and the slide path", function()
		for _, w in ParadeLane.WAYPOINTS do
			for _, o in { -ParadeLane.HALF_WIDTH, 0, ParadeLane.HALF_WIDTH } do
				expect(field.height(w[1] + o, w[2] + o)).toBe(0)
			end
		end
		for _, p in WorldLayout.SLIDE_PATH do
			expect(field.height(p[1], p[3])).toBe(0)
		end
	end)
	it("stays off the border decor (low at most under a footprint corner)", function()
		for _, p in WorldBorder.pieces() do
			expect(field.height(p.pos[1], p.pos[3])).toBe(0)
			for _, c in WorldBorder.corners(p) do
				expect(field.height(c[1], c[3]) <= 2).toBe(true)
			end
		end
	end)
end)
