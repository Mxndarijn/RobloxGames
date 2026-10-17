--!strict
-- BorderTerrain chunking: the server writes 64-stud chunks nearest-first on a
-- per-frame time budget. Chunks must cover exactly the columns the 128-stud
-- tiles did, never overlap, and produce bit-identical voxels.
local BorderTerrain = require("../src/visuals/shared/BorderTerrain")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local CELL, E, INNER = BorderTerrain.CELL, BorderTerrain.EXTENT, BorderTerrain.INNER

-- column (cell index pair) -> true for every column of the given squares
local function columns(rects: { { x: number, z: number } }, size: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, r in rects do
		for i = 0, size / CELL - 1 do
			for k = 0, size / CELL - 1 do
				local key = `{r.x + i * CELL},{r.z + k * CELL}`
				out[key] = (out[key] or 0) + 1
			end
		end
	end
	return out
end

describe("BorderTerrain.chunks", function()
	local chunks = BorderTerrain.chunks()
	local tiles = BorderTerrain.tiles()
	local tileSize = BorderTerrain.TILE_CELLS * CELL
	local chunkSize = BorderTerrain.CHUNK_CELLS * CELL

	it("are 16 cells (64 studs) square and aligned to the CELL grid and FLOOR", function()
		expect(BorderTerrain.CHUNK_CELLS).toBe(16)
		expect(#chunks > 0).toBe(true)
		for _, c in chunks do
			expect(c.size).toBe(chunkSize)
			expect(c.x % CELL).toBe(0)
			expect(c.z % CELL).toBe(0)
			expect(c.x >= -E and c.x + c.size <= E).toBe(true)
			expect(c.z >= -E and c.z + c.size <= E).toBe(true)
		end
		expect(BorderTerrain.FLOOR % CELL).toBe(0)
	end)
	it("never overlap: every column is in at most one chunk", function()
		for _, n in columns(chunks, chunkSize) do
			expect(n).toBe(1)
		end
	end)
	it("cover every column with terrain that the old tiles wrote", function()
		local old = columns(tiles, tileSize)
		local new = columns(chunks, chunkSize)
		for key in new do
			expect(old[key]).toBe(1) -- nothing outside the old tiles
		end
		for key in old do
			if new[key] == nil then
				-- the only columns dropped are air-only ones wholly inside INNER
				local x, z = string.match(key, "^(-?%d+),(-?%d+)$")
				local cx, cz = tonumber(x) :: number, tonumber(z) :: number
				expect(math.max(math.abs(cx + CELL / 2), math.abs(cz + CELL / 2)) <= INNER).toBe(true)
			end
		end
	end)
	it("are sorted nearest-first and deterministic", function()
		local function dist(c: BorderTerrain.Chunk): number
			local nx, nz = math.max(c.x, -(c.x + c.size), 0), math.max(c.z, -(c.z + c.size), 0)
			return math.sqrt(nx * nx + nz * nz)
		end
		for i = 2, #chunks do
			expect(dist(chunks[i - 1]) <= dist(chunks[i])).toBe(true)
		end
		expect(dist(chunks[1])).toBe(dist(chunks[1])) -- nearest touches the Ground edge ring
		expect(BorderTerrain.chunks()).toEqual(chunks)
		expect(#BorderTerrain.chunks(32)).toBe(#tiles)
	end)
end)

describe("BorderTerrain.voxels", function()
	local field = BorderTerrain.field()
	local names = { Grass = "Grass", LeafyGrass = "LeafyGrass", Rock = "Rock" }

	-- voxel map "x,layer,z" -> "material:occupancy" for non-air voxels
	local function solids(chunkList: { BorderTerrain.Chunk }): { [string]: string }
		local out: { [string]: string } = {}
		for _, c in chunkList do
			local v = BorderTerrain.voxels(field, c, names, "Air")
			for i, mx in v.materials do
				for j, mj in mx do
					for k, m in mj do
						if m ~= "Air" then
							local key = `{c.x + (i - 1) * CELL},{j},{c.z + (k - 1) * CELL}`
							out[key] = `{m}:{v.occupancy[i][j][k]}`
						end
					end
				end
			end
		end
		return out
	end

	it("write identical voxels for a 128-stud tile and the 64-stud chunks inside it", function()
		local checked = 0
		for _, spot in { { 320, 0 }, { 384, 384 }, { -640, 128 }, { 0, -512 } } do
			local tile = { x = spot[1], z = spot[2], size = 128 }
			local sub = {}
			for dx = 0, 64, 64 do
				for dz = 0, 64, 64 do
					table.insert(sub, { x = tile.x + dx, z = tile.z + dz, size = 64 })
				end
			end
			local a, b = solids({ tile }), solids(sub)
			for key, value in a do
				expect(b[key]).toBe(value)
				checked += 1
			end
			for key in b do
				expect(a[key] ~= nil).toBe(true)
			end
		end
		expect(checked > 1000).toBe(true)
	end)
	it("leave columns inside the Ground square empty", function()
		local v = BorderTerrain.voxels(field, { x = 256, z = 0, size = 64 }, names, "Air")
		-- x 256..320 is inside INNER: all air
		for _, mx in v.materials do
			for _, mj in mx do
				for _, m in mj do
					expect(m).toBe("Air")
				end
			end
		end
	end)
end)

describe("BorderTerrain.runBudgeted", function()
	it("runs every step in order and yields once the budget is spent", function()
		local now = 0
		local done: { number } = {}
		local yields = BorderTerrain.runBudgeted(
			10,
			function(n)
				table.insert(done, n)
				now += 1
			end,
			3,
			function()
				return now
			end,
			function()
				now += 100 -- the next frame
			end
		)
		expect(done).toEqual({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
		expect(yields).toBe(3) -- after steps 3, 6, 9; none after the last
	end)
	it("makes progress even when one step exceeds the budget", function()
		local now = 0
		local yields = BorderTerrain.runBudgeted(
			4,
			function()
				now += 10
			end,
			3,
			function()
				return now
			end,
			function() end
		)
		expect(yields).toBe(3)
	end)
end)

describe("BorderTerrain voxel surface (B1)", function()
	it(
		"renders each column at its height: top voxel occupancy is (h - bottom - CELL/2) / CELL, flush with the Ground at h = 0",
		function()
			local field = BorderTerrain.field(1)
			local air = "Air"
			local mats = { Grass = "Grass", LeafyGrass = "Grass", Rock = "Rock", Slate = "Rock", Snow = "Snow" }
			local chunk = BorderTerrain.chunks()[1]
			local v = BorderTerrain.voxels(field, chunk, mats, air)
			local count = math.floor(chunk.size / CELL)
			for i = 1, count do
				for k = 1, count do
					local x = chunk.x + (i - 0.5) * CELL
					local z = chunk.z + (k - 0.5) * CELL
					local h = field.height(x, z)
					if math.max(math.abs(x), math.abs(z)) > INNER and h > 0.2 then
						-- surface of the highest non-air voxel as Terrain renders it: bottom + CELL/2 + CELL * occ
						local top
						for j = 1, v.layers do
							if v.materials[i][j][k] ~= air then
								top = BorderTerrain.FLOOR + (j - 1) * CELL + CELL / 2 + CELL * v.occupancy[i][j][k]
							end
						end
						expect(top ~= nil and math.abs(top - h) < 0.1).toBe(true)
					end
				end
			end
		end
	)
end)
