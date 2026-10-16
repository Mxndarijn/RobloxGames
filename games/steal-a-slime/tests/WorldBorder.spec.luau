--!strict
-- World border (WorldBorder): seeded layered decor (fences and hedges, tree
-- and rock groves, backdrop hills) is deterministic and never repeats a
-- stretch, the invisible collider ring closes the whole perimeter, and the
-- border stays inside its MeshPart slot share (88 of the THEME.md 400) and
-- part budget (700).
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

local pieces = WorldBorder.pieces()

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

local LAYERS = { "inner", "mid", "outer" }
local W = WorldBorder.WINDOW

local function layer(list: { WorldBorder.Piece }, row: string): { WorldBorder.Piece }
	local out = {}
	for _, p in list do
		if p.row == row then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	return out
end

local function sig(p: WorldBorder.Piece): string
	return `{p.mesh}|{p.rotBucket}|{p.scaleBucket}`
end

-- First repeated window of W consecutive signatures in `seq`, going round
-- the ring (the last pieces are followed by the first), or nil.
local function repeatedWindow(seq: { WorldBorder.Piece }): string?
	local n = #seq
	local seen: { [string]: boolean } = {}
	for start = 1, n do
		local run = {}
		for j = 0, W - 1 do
			table.insert(run, sig(seq[(start + j - 1) % n + 1]))
		end
		local key = table.concat(run, "/")
		if seen[key] then
			return key
		end
		seen[key] = true
	end
	return nil
end

local function overhang(p: WorldBorder.Piece): number
	local worst = -math.huge
	for _, c in WorldBorder.corners(p) do
		worst = math.max(worst, math.abs(c[1]), math.abs(c[3]))
	end
	return worst - WorldBorder.GROUND_HALF
end

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

local function borderNodes(): { any }
	local out = {}
	walk(child(WorldLayout.build()[1], "Border"), function(n)
		table.insert(out, n)
	end)
	return out
end

describe("WorldBorder layers", function()
	it("walks an inner, a mid and an outer layer plus corner groves, each within its cap", function()
		for _, name in LAYERS do
			local n = #layer(pieces, name)
			expect(n >= 8).toBe(true)
			local cap = (WorldBorder.LAYERS :: any)[name].cap
			expect(n <= cap).toBe(true)
		end
		expect(#layer(pieces, "corner")).toBe(4 * WorldBorder.CORNER_CHUNKS)
		expect(#pieces).toBe(
			#layer(pieces, "inner") + #layer(pieces, "mid") + #layer(pieces, "outer") + 4 * WorldBorder.CORNER_CHUNKS
		)
	end)
	it("keeps fences and hedges inside, trees and rocks in the middle, hills outside", function()
		local function mean(row: string): number
			local sum, list = 0, layer(pieces, row)
			for _, p in list do
				sum += p.radius
			end
			return sum / #list
		end
		expect(mean("inner") < mean("mid")).toBe(true)
		expect(mean("mid") < mean("outer")).toBe(true)
		for _, p in layer(pieces, "inner") do
			expect(p.kind == "Accent" or p.mesh:find("fence") ~= nil or p.mesh:find("hedge") ~= nil).toBe(true)
		end
		for _, p in layer(pieces, "outer") do
			expect(p.mesh:find("^ranch_border_hill_") ~= nil).toBe(true)
		end
	end)
	it("uses every piece design somewhere on the ring", function()
		local used: { [string]: number } = {}
		for _, p in pieces do
			used[p.mesh] = (used[p.mesh] or 0) + 1
		end
		for _, d in WorldBorder.DEFS do
			expect((used[d.mesh] or 0) >= 1).toBe(true)
		end
		local n = 0
		for _ in used do
			n += 1
		end
		expect(n >= 20).toBe(true)
	end)
	it("has 3+ trees, 3+ hedges, 3+ rocks, 2+ fences and 2+ hills to scatter", function()
		local count = {
			Pine = 0,
			Oak = 0,
			Saplings = 0,
			Hedge = 0,
			Boulder = 0,
			Slab = 0,
			RockHeap = 0,
			Spire = 0,
			Fence = 0,
			Hill = 0,
		}
		for _, d in WorldBorder.DEFS do
			for key in count do
				if d.kind:find("^" .. key) or (key == "Fence" and d.kind == "BrokenFence") then
					count[key] += 1
				end
			end
		end
		expect(count.Pine + count.Oak + count.Saplings >= 3).toBe(true)
		expect(count.Hedge >= 3).toBe(true)
		expect(count.Boulder + count.Slab + count.RockHeap + count.Spire >= 3).toBe(true)
		expect(count.Fence >= 2).toBe(true)
		expect(count.Hill >= 2).toBe(true)
	end)
end)

describe("WorldBorder no repeating sequence", function()
	it("never repeats a window of 4 consecutive pieces (mesh, rotation bucket, scale bucket) in a layer", function()
		for _, name in LAYERS do
			expect(repeatedWindow(layer(pieces, name))).toBe(nil)
		end
	end)
	it("never repeats one either when the layers are read together bearing by bearing", function()
		local all = {}
		for _, name in LAYERS do
			for _, p in layer(pieces, name) do
				table.insert(all, p)
			end
		end
		table.sort(all, function(a, b)
			return a.angle < b.angle
		end)
		expect(repeatedWindow(all)).toBe(nil)
	end)
	it("holds for other seeds too", function()
		for seed = 1, 12 do
			local other = WorldBorder.pieces(seed * 977)
			for _, name in LAYERS do
				expect(repeatedWindow(layer(other, name))).toBe(nil)
			end
		end
	end)
	it("never puts one design twice within two neighbours", function()
		for _, name in LAYERS do
			local seq = layer(pieces, name)
			for i = 1, #seq - 2 do
				local a, b, c = seq[i], seq[i + 1], seq[i + 2]
				if a.kind ~= "Accent" and b.kind ~= "Accent" and c.kind ~= "Accent" then
					expect(a.mesh ~= b.mesh and b.mesh ~= c.mesh).toBe(true)
				end
			end
		end
	end)
	it("varies scale, rotation, spacing and depth along every layer", function()
		for _, name in LAYERS do
			local seq = layer(pieces, name)
			local scales, buckets, steps, depths = {}, {}, {}, {}
			local nb = 0
			for i, p in seq do
				local q = seq[i % #seq + 1]
				table.insert(scales, p.scale)
				table.insert(steps, (q.angle - p.angle) % 360)
				table.insert(depths, p.radius)
				if not buckets[p.rotBucket] then
					buckets[p.rotBucket] = true
					nb += 1
				end
			end
			expect(spread(scales) > 0.06).toBe(true)
			expect(spread(steps) > 0.1).toBe(true)
			expect(spread(depths) > 0.002).toBe(true)
			expect(nb >= (if name == "mid" then 6 else 2)).toBe(true)
		end
	end)
	it("clusters the trees and rocks into groves with open ground between", function()
		local seq = layer(pieces, "mid")
		local gaps = {}
		for i, p in seq do
			local q = seq[i % #seq + 1]
			local d = math.rad((q.angle - p.angle) % 360) * p.radius - (p.size[1] + q.size[1]) / 2
			table.insert(gaps, d)
		end
		local tight, open = 0, 0
		for _, g in gaps do
			if g < 6 then
				tight += 1
			elseif g > 40 then
				open += 1
			end
		end
		expect(tight >= 8).toBe(true)
		expect(open >= 4).toBe(true)
	end)
end)

describe("WorldBorder decor", function()
	it("stays inside the MeshPart slot share (<= 88) and the border part budget (<= 700)", function()
		local slots, parts = 0, 0
		for _, n in borderNodes() do
			if n.class == "Part" then
				parts += 1
			end
			if n.attributes and n.attributes.MeshAsset then
				slots += 1
			end
		end
		expect(slots).toBe(#pieces)
		expect(slots).toBe(WorldLayout.BORDER_SLOT_COUNT)
		expect(slots <= WorldLayout.BORDER_SLOT_BUDGET).toBe(true)
		expect(WorldLayout.BORDER_SLOT_BUDGET).toBe(88)
		expect(parts <= WorldLayout.BORDER_PART_BUDGET).toBe(true)
		expect(parts).toBe(WorldBorder.WALL_SEGMENTS + #pieces)
	end)
	it("builds at most 88 slots whatever the seed", function()
		for seed = 1, 12 do
			expect(#WorldBorder.pieces(seed * 977) <= WorldLayout.BORDER_SLOT_BUDGET).toBe(true)
		end
	end)
	it("stands on the Ground: flat on y = 0 and at most 3 studs over the edge", function()
		for _, p in pieces do
			expect(p.pos[2] - p.size[2] / 2).toBeCloseTo(0, 1)
			expect(math.abs(p.pos[2] - p.size[2] / 2) <= 0.1).toBe(true)
			expect(overhang(p) <= 3).toBe(true)
		end
	end)
	it("keeps the footprints outside the wall line, so nothing sits on the walkable ground", function()
		for _, p in pieces do
			local reach = p.radius - (if p.row == "corner" then p.size[3] / 2 else 0)
			local worst = math.huge
			for _, c in WorldBorder.corners(p) do
				worst = math.min(worst, math.sqrt(c[1] ^ 2 + c[3] ^ 2))
			end
			expect(reach >= WorldBorder.RADIUS).toBe(true)
			-- outer hills have a low tapered rim that may reach back over the wall line
			expect(worst >= WorldBorder.RADIUS - (if p.row == "outer" then 8 else 1)).toBe(true)
		end
	end)
	it("keeps every decor axis within MAX_AXIS (v17 decor)", function()
		for _, p in pieces do
			expect(math.max(p.size[1], p.size[2], p.size[3]) <= WorldBorder.MAX_AXIS + 1e-6).toBe(true)
		end
	end)
	it("keeps scales within each design's range", function()
		for _, p in pieces do
			if p.row ~= "corner" and p.kind ~= "Accent" then
				for _, d in WorldBorder.DEFS do
					if d.mesh == p.mesh then
						expect(p.scale <= d.scale[2] + 1e-6).toBe(true)
						expect(p.scale >= math.min(d.scale[1], WorldBorder.MAX_AXIS / 57) - 1e-6).toBe(true)
					end
				end
			end
		end
	end)
	it("fills each Ground corner with corner groves past the wall", function()
		local perCorner = { 0, 0, 0, 0 }
		for _, p in pieces do
			if p.row == "corner" then
				local q = math.floor(p.angle / 90) + 1
				perCorner[q] += 1
				-- within 15 degrees of the diagonal, past the wall line
				expect(math.abs(p.angle - ((q - 1) * 90 + 45)) <= 15).toBe(true)
				expect(p.radius - p.size[3] / 2 >= WorldBorder.RADIUS + WorldBorder.CORNER_TUCK - 1e-6).toBe(true)
			end
		end
		for _, n in perCorner do
			expect(n).toBe(WorldBorder.CORNER_CHUNKS)
		end
	end)
	it("leaves no stretch of the edge open: every bearing has something behind the wall", function()
		local covered: { boolean } = {}
		local count = 0
		for deg = 0, 359 do
			for _, p in pieces do
				local half = math.deg(math.max(p.size[1], p.size[3]) / 2 / p.radius)
				if math.abs((deg - p.angle + 180) % 360 - 180) <= half then
					covered[deg + 1] = true
					count += 1
					break
				end
			end
		end
		expect(count >= 310).toBe(true)
		local longest, run = 0, 0
		for k = 0, 719 do
			if covered[k % 360 + 1] then
				run = 0
			else
				run += 1
				longest = math.max(longest, run)
			end
		end
		expect(longest <= 10).toBe(true)
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
	it("wires every border mesh into MeshAssets with an uploaded meshId and size", function()
		local meshes: { string } = {}
		for _, d in WorldBorder.DEFS do
			table.insert(meshes, d.mesh)
		end
		for _, c in WorldBorder.CHUNKS do
			table.insert(meshes, c.mesh)
			table.insert(meshes, c.mesh .. "_m")
		end
		for _, a in WorldBorder.ACCENTS do
			table.insert(meshes, a)
		end
		for _, mesh in meshes do
			local entry = MeshAssets.get(mesh)
			expect(entry ~= nil and entry.size ~= nil).toBe(true)
			expect(MeshAssets.meshId(mesh) ~= nil).toBe(true)
			expect(table.find(MeshAssets.NAMES, mesh) ~= nil).toBe(true)
		end
		for _, p in pieces do
			expect(p.uploaded).toBe(true)
			expect(table.find(meshes, p.mesh) ~= nil).toBe(true)
		end
	end)
end)
