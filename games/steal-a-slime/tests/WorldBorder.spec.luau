--!strict
-- World border (WorldBorder): seeded chunk decor is deterministic and varied,
-- the invisible collider ring closes the whole perimeter, and the border
-- stays inside its MeshPart slot share (<= 120 of the THEME.md 400).
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")
local WorldBorder = require("../src/visuals/shared/WorldBorder")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Vec = LayoutMath.Vec

local function walk(node: any, visit: (any) -> ())
	visit(node)
	for _, c in node.children or {} do
		walk(c, visit)
	end
end

local function child(node: any, name: string): any
	for _, c in node.children or {} do
		if c.name == name then
			return c
		end
	end
	error(`{node.name} has no {name}`)
end

-- Is (x, z) inside the upright block `size` at `pos` turned `yaw` degrees?
local function inside(x: number, z: number, pos: Vec, size: Vec, yaw: number): boolean
	local local_ = LayoutMath.apply(LayoutMath.orientation({ 0, -yaw, 0 }), { x - pos[1], 0, z - pos[3] })
	return math.abs(local_[1]) <= size[1] / 2 and math.abs(local_[3]) <= size[3] / 2
end

local function front(pieces: { WorldBorder.Piece }): { WorldBorder.Piece }
	local out = {}
	for _, p in pieces do
		if p.row == "front" then
			table.insert(out, p)
		end
	end
	return out
end

local pieces = WorldBorder.pieces()
local frontRow = front(pieces)

describe("WorldBorder determinism", function()
	it("builds the same border every time for one seed", function()
		expect(WorldBorder.build()).toEqual(WorldBorder.build())
		expect(WorldBorder.pieces(WorldBorder.SEED)).toEqual(pieces)
	end)
	it("a different seed gives a different border", function()
		local other = WorldBorder.pieces(7)
		local same = #other == #pieces
		if same then
			for i, p in other do
				same = same and p.kind == pieces[i].kind and math.abs(p.angle - pieces[i].angle) < 1e-6
			end
		end
		expect(same).toBe(false)
	end)
end)

describe("WorldBorder collider ring", function()
	local walls = WorldBorder.colliders()
	local R, T = WorldBorder.RADIUS, WorldBorder.WALL_THICKNESS
	it("closes the whole perimeter (every ray out of the map hits a wall)", function()
		-- Rays from the centre, stepped out through the wall band; the polygon
		-- corners sit at (R + T) / cos(pi / n), so the band ends there.
		local far = (R + T) / math.cos(math.pi / WorldBorder.WALL_SEGMENTS) + 1
		local escapes = 0
		for k = 0, 3599 do
			local a = math.rad(k / 10)
			local hit = false
			local r = R - 1
			while r <= far and not hit do
				local x, z = math.sin(a) * r, math.cos(a) * r
				for _, w in walls do
					if inside(x, z, w.pos, w.size, w.yaw) then
						hit = true
						break
					end
				end
				r += 0.25
			end
			if not hit then
				escapes += 1
			end
		end
		expect(escapes).toBe(0)
	end)
	it("has no gap between neighbouring walls (both cover their shared outer corner)", function()
		local n = WorldBorder.WALL_SEGMENTS
		local corner = (R + T) / math.cos(math.pi / n) - 0.05
		for i, w in walls do
			local v = walls[i % #walls + 1]
			local a = math.rad(w.yaw + 180 / n)
			local x, z = math.sin(a) * corner, math.cos(a) * corner
			expect(inside(x, z, w.pos, w.size, w.yaw)).toBe(true)
			expect(inside(x, z, v.pos, v.size, v.yaw)).toBe(true)
		end
	end)
	it("is too tall to jump and stands on the ground", function()
		for _, w in walls do
			expect(w.size[2] >= 40).toBe(true)
			expect(w.pos[2] - w.size[2] / 2).toBeCloseTo(0)
		end
	end)
	it("ships as invisible, collidable walls that raycasts and prompts ignore", function()
		local border = child(child(WorldLayout.build()[1], "Border"), "Walls")
		expect(#border.children).toBe(WorldBorder.WALL_SEGMENTS)
		for _, wall in border.children do
			expect(wall.class).toBe("Part")
			expect(wall.canCollide).toBe(true)
			expect(wall.transparency).toBe(1)
			expect(wall.canQuery).toBe(false)
			expect(wall.canTouch).toBe(false)
		end
	end)
	it("keeps the plots, prop spots, sheds and scattered decor inside the ring", function()
		local h = WorldLayout.PLOT_SIZE / 2
		for i = 1, Config.PLOT_COUNT do
			local c = WorldLayout.plotCentre(i)
			for _, s in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
				expect(math.sqrt((c[1] + s[1] * h) ^ 2 + (c[3] + s[2] * h) ^ 2) < R - 20).toBe(true)
			end
		end
		for _, spot in WorldLayout.PROP_SPOTS do
			expect(math.sqrt(spot.pos[1] ^ 2 + spot.pos[3] ^ 2) < R - 20).toBe(true)
		end
		local decor = child(WorldLayout.build()[1], "Decor")
		walk(decor, function(n)
			if n.class == "Part" and n.pos then
				local reach = math.max(n.size[1], n.size[3]) / 2
				expect(math.sqrt(n.pos[1] ^ 2 + n.pos[3] ^ 2) + reach < R).toBe(true)
			end
		end)
	end)
	it("sits on the Ground", function()
		for _, w in walls do
			expect(math.abs(w.pos[1]) + w.size[1] / 2 <= WorldBorder.GROUND_HALF).toBe(true)
			expect(math.abs(w.pos[3]) + w.size[1] / 2 <= WorldBorder.GROUND_HALF).toBe(true)
		end
	end)
end)

local function chunks(list: { WorldBorder.Piece }): { WorldBorder.Piece }
	local out = {}
	for _, p in list do
		if p.kind ~= "Accent" then
			table.insert(out, p)
		end
	end
	return out
end

local function design(p: WorldBorder.Piece): string
	return (string.gsub(p.mesh, "_m$", ""))
end

local frontChunks = chunks(frontRow)

local function overhang(p: WorldBorder.Piece): number
	local worst = -math.huge
	for _, c in WorldBorder.corners(p) do
		worst = math.max(worst, math.abs(c[1]), math.abs(c[3]))
	end
	return worst - WorldBorder.GROUND_HALF
end

describe("WorldBorder decor", function()
	it("rings the whole edge with no see-through gaps in the front row", function()
		local sorted = table.clone(frontRow)
		table.sort(sorted, function(a, b)
			return a.angle < b.angle
		end)
		local worst = -math.huge
		for i, p in sorted do
			local q = sorted[i % #sorted + 1]
			local d = (q.angle - p.angle) % 360
			-- arc between the two footprints along the wall line
			local gap = math.rad(d) * WorldBorder.RADIUS - (p.size[1] + q.size[1]) / 2
			worst = math.max(worst, gap)
		end
		expect(worst < 3).toBe(true)
	end)
	it("builds the edge from 30-40 chunk placements of the chunk meshes", function()
		local all = chunks(pieces)
		expect(#all >= 30 and #all <= 40).toBe(true)
		local meshes: { [string]: boolean } = {}
		for _, p in all do
			meshes[p.mesh] = true
		end
		local n = 0
		for _ in meshes do
			n += 1
		end
		-- reuse: far fewer meshes than placements
		expect(n <= #WorldBorder.CHUNKS * 2).toBe(true)
		expect(n * 2 <= #all).toBe(true)
	end)
	it("uses at most 120 MeshPart slots for the whole border", function()
		local slots = 0
		walk(WorldBorder.build(), function(n)
			if n.attributes and n.attributes.MeshAsset then
				slots += 1
			end
		end)
		expect(slots).toBe(#pieces)
		expect(slots <= 120).toBe(true)
		expect(slots).toBe(#chunks(pieces) + WorldBorder.ACCENT_COUNT)
	end)
	it("mixes every front design, never one design twice within three neighbours", function()
		local seen: { [string]: number } = {}
		for _, p in frontChunks do
			seen[p.kind] = (seen[p.kind] or 0) + 1
		end
		for _, c in WorldBorder.CHUNKS do
			if c.front > 0 then
				expect((seen[c.kind] or 0) >= 2).toBe(true)
			end
		end
		for i = 1, #frontChunks - 2 do
			local a, b, c = frontChunks[i], frontChunks[i + 1], frontChunks[i + 2]
			expect(a.kind ~= b.kind and b.kind ~= c.kind and a.kind ~= c.kind).toBe(true)
		end
	end)
	it("mirrors about half the chunks, never three of one hand in a row", function()
		local mirrored = 0
		for i, p in frontChunks do
			if p.mirrored then
				mirrored += 1
				expect(string.sub(p.mesh, -2)).toBe("_m")
			else
				expect(string.sub(p.mesh, -2) ~= "_m").toBe(true)
			end
			if i >= 3 then
				local a, b = frontChunks[i - 1].mirrored, frontChunks[i - 2].mirrored
				expect(a == b and b == p.mirrored).toBe(false)
			end
		end
		expect(mirrored >= #frontChunks * 0.3 and mirrored <= #frontChunks * 0.7).toBe(true)
	end)
	it("varies scale, yaw, spacing and inset (no repeating period)", function()
		local function spread(values: { number }): number
			local mean = 0
			for _, v in values do
				mean += v / #values
			end
			local var = 0
			for _, v in values do
				var += (v - mean) ^ 2 / #values
			end
			return math.sqrt(var) / math.max(math.abs(mean), 1e-6)
		end
		local steps, scales, insets, turns = {}, {}, {}, {}
		for i, p in frontRow do
			local q = frontRow[i % #frontRow + 1]
			table.insert(steps, (q.angle - p.angle) % 360)
			table.insert(scales, p.scale)
			table.insert(insets, p.radius)
			table.insert(turns, ((p.yaw - p.angle - 180 + 540) % 360) - 180)
		end
		expect(spread(steps) > 0.05).toBe(true)
		expect(spread(scales) > 0.03).toBe(true)
		expect(spread(insets) > 0.003).toBe(true)
		local distinct: { [string]: boolean } = {}
		local n = 0
		for _, t in turns do
			local key = string.format("%.1f", t)
			if not distinct[key] then
				distinct[key] = true
				n += 1
			end
		end
		expect(n > #turns * 0.8).toBe(true)
		-- the (design, hand) sequence never repeats with a short period
		for period = 1, 8 do
			local same = 0
			for i = 1, #frontChunks - period do
				if frontChunks[i].mesh == frontChunks[i + period].mesh then
					same += 1
				end
			end
			expect(same / (#frontChunks - period) < 0.4).toBe(true)
		end
	end)
	it("fills each Ground corner with corner groves behind the front row", function()
		local perCorner = { 0, 0, 0, 0 }
		for _, p in pieces do
			if p.row == "corner" then
				local q = math.floor(p.angle / 90) + 1
				perCorner[q] += 1
				-- within 15 degrees of the diagonal, past the wall line
				expect(math.abs(p.angle - ((q - 1) * 90 + 45)) <= 15).toBe(true)
				expect(p.radius - p.size[3] / 2 >= WorldBorder.RADIUS + 10).toBe(true)
			end
		end
		for _, n in perCorner do
			expect(n).toBe(WorldBorder.CORNER_CHUNKS)
		end
	end)
	it("stands on the Ground (footprint corners at most 3 studs over the edge)", function()
		for _, p in pieces do
			expect(overhang(p) <= 3).toBe(true)
			expect(p.pos[2]).toBeCloseTo(p.size[2] / 2)
		end
	end)
	it("keeps every decor axis within MAX_AXIS (v17 decor)", function()
		for _, p in pieces do
			expect(math.max(p.size[1], p.size[2], p.size[3]) <= WorldBorder.MAX_AXIS + 1e-6).toBe(true)
		end
	end)
	it("never collides and keeps each slot at the mesh's native proportions", function()
		local border = child(child(WorldLayout.build()[1], "Border"), "Decor")
		local meshed = 0
		walk(border, function(n)
			if n.class ~= "Part" then
				return
			end
			expect(n.canCollide).toBe(false)
			local mesh = (n.attributes or {}).MeshAsset
			expect(mesh ~= nil).toBe(true)
			local native = (MeshAssets.get(mesh) :: any).size
			local s = n.size[1] / native[1]
			expect(n.size[2] / native[2]).toBeCloseTo(s)
			expect(n.size[3] / native[3]).toBeCloseTo(s)
			expect(MeshAssets.meshId(mesh) ~= nil).toBe(true)
			meshed += 1
		end)
		expect(meshed).toBe(#WorldBorder.pieces())
	end)
	it("wires every chunk mesh and its mirrored twin into MeshAssets with uploaded meshIds", function()
		for _, c in WorldBorder.CHUNKS do
			for _, mesh in { c.mesh, c.mesh .. "_m" } do
				local entry = MeshAssets.get(mesh)
				expect(entry ~= nil and entry.size ~= nil).toBe(true)
				expect(MeshAssets.meshId(mesh) ~= nil).toBe(true)
				expect(table.find(MeshAssets.NAMES, mesh) ~= nil).toBe(true)
			end
		end
		for _, p in pieces do
			expect(p.uploaded).toBe(true)
			if p.kind ~= "Accent" then
				expect(string.find(design(p), "^ranch_border_chunk_") ~= nil).toBe(true)
			end
		end
	end)
end)
