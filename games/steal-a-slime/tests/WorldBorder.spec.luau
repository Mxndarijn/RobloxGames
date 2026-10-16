--!strict
-- World border (WorldBorder): seeded edge decor is deterministic and varied,
-- and the invisible collider ring closes the whole perimeter.
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

describe("WorldBorder decor", function()
	it("rings the whole edge with no see-through gaps in the front row", function()
		local sorted = table.clone(frontRow)
		table.sort(sorted, function(a, b)
			return a.angle < b.angle
		end)
		local worst = 0
		for i, p in sorted do
			local q = sorted[i % #sorted + 1]
			local d = (q.angle - p.angle) % 360
			-- arc between the two footprints along the wall line
			local gap = math.rad(d) * WorldBorder.RADIUS - (p.size[1] + q.size[1]) / 2
			worst = math.max(worst, gap)
		end
		expect(worst < 3).toBe(true)
		expect(#frontRow > 60).toBe(true)
	end)
	it("mixes every kind, with no long runs of one kind", function()
		local seen: { [string]: number } = {}
		for _, p in frontRow do
			seen[p.kind] = (seen[p.kind] or 0) + 1
		end
		for _, k in WorldBorder.KINDS do
			expect((seen[k.kind] or 0) >= 4).toBe(true)
		end
		for i = 1, #frontRow do
			local window: { [string]: boolean } = {}
			local n = 0
			for j = 0, 7 do
				local kind = frontRow[(i + j - 1) % #frontRow + 1].kind
				if not window[kind] then
					window[kind] = true
					n += 1
				end
			end
			expect(n >= 3).toBe(true)
		end
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
		expect(spread(steps) > 0.2).toBe(true)
		expect(spread(scales) > 0.08).toBe(true)
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
		-- the kind sequence never repeats with a short period
		for period = 1, 12 do
			local same = 0
			for i = 1, #frontRow - period do
				if frontRow[i].kind == frontRow[i + period].kind then
					same += 1
				end
			end
			expect(same / (#frontRow - period) < 0.6).toBe(true)
		end
	end)
	it("fills the Ground corners with a back row", function()
		local corners = 0
		for _, p in pieces do
			if p.row == "back" and p.radius > WorldBorder.GROUND_HALF + 20 then
				corners += 1
			end
		end
		expect(corners >= 8).toBe(true)
	end)
	it("stands on the Ground (footprints at most 3 studs over the edge)", function()
		for _, p in pieces do
			local reach = math.max(p.size[1], p.size[3]) / 2
			expect(math.abs(p.pos[1]) - reach <= WorldBorder.GROUND_HALF).toBe(true)
			expect(math.abs(p.pos[3]) - reach <= WorldBorder.GROUND_HALF).toBe(true)
			expect(math.max(math.abs(p.pos[1]), math.abs(p.pos[3])) + reach <= WorldBorder.GROUND_HALF + 3).toBe(true)
			expect(p.pos[2]).toBeCloseTo(p.size[2] / 2)
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
			local a = n.attributes or {}
			local mesh = a.MeshAsset
			if mesh then
				local native = (MeshAssets.get(mesh) :: any).size
				local s = n.size[1] / native[1]
				expect(n.size[2] / native[2]).toBeCloseTo(s)
				expect(n.size[3] / native[3]).toBeCloseTo(s)
				expect(MeshAssets.meshId(mesh) ~= nil).toBe(true)
				meshed += 1
			end
			expect(a.BorderMesh == nil).toBe(true)
		end)
		expect(meshed).toBe(#WorldBorder.pieces())
	end)
	it("wires border KINDS into MeshAssets with uploaded meshIds", function()
		for _, k in WorldBorder.KINDS do
			local entry = MeshAssets.get(k.mesh)
			expect(entry ~= nil and entry.size ~= nil).toBe(true)
			expect(MeshAssets.meshId(k.mesh) ~= nil).toBe(true)
			expect(table.find(MeshAssets.NAMES, k.mesh) ~= nil).toBe(true)
		end
	end)
end)
