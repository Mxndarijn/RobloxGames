--!strict
-- Map.Decor.Meadow (src/visuals/shared/Meadow): the flower / tall grass /
-- small rock clusters in the grass band between the plots and the border.
-- Clear of plots, entrances (spoke paths), the ring path, the parade lane,
-- props, prop spots and the other decor; inside the part budget; resting on
-- the Ground (nothing floats); seeded, and varied (no repeated cluster).
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local Meadow = require("../src/visuals/shared/Meadow")
local PropClearance = require("../src/visuals/shared/PropClearance")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Vec = { number }

local built = WorldLayout.build()

local function child(node: any, name: string): any
	for _, c in node.children or {} do
		if c.name == name then
			return c
		end
	end
	return nil
end

local decor = child(built[1], "Decor")
local meadow = child(decor, "Meadow")

local clusters: { any } = {}
for _, m in (meadow and meadow.children or {}) :: { any } do
	table.insert(clusters, m)
end

local function corners(p: any): { Vec }
	local out = {}
	if p.shape == "Ball" then
		local r = p.size[1] / 2
		for _, s in { { 1, 1, 1 }, { -1, -1, -1 }, { 1, -1, 1 }, { -1, 1, -1 } } do
			table.insert(out, { p.pos[1] + s[1] * r, p.pos[2] + s[2] * r, p.pos[3] + s[3] * r })
		end
		return out
	end
	local m = LayoutMath.orientation(p.rot)
	local h = { p.size[1] / 2, p.size[2] / 2, p.size[3] / 2 }
	if p.shape == "Cylinder" then
		-- round cross-section (Y = Z = the smaller of the two)
		local d = math.min(p.size[2], p.size[3]) / 2
		h = { p.size[1] / 2, d, d }
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local c = LayoutMath.apply(m, { sx * h[1], sy * h[2], sz * h[3] })
				table.insert(out, { p.pos[1] + c[1], p.pos[2] + c[2], p.pos[3] + c[3] })
			end
		end
	end
	return out
end

local function bounds(p: any): (number, number, number, number, number, number)
	local lx, ly, lz, hx, hy, hz = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for _, c in corners(p) do
		lx, ly, lz = math.min(lx, c[1]), math.min(ly, c[2]), math.min(lz, c[3])
		hx, hy, hz = math.max(hx, c[1]), math.max(hy, c[2]), math.max(hz, c[3])
	end
	return lx, ly, lz, hx, hy, hz
end

local function allParts(): { any }
	local out = {}
	for _, c in clusters do
		for _, p in c.children do
			table.insert(out, p)
		end
	end
	return out
end

-- The clusters WorldLayout built (centre, radius, kind, parts).
local list = WorldLayout.meadowClusters()

describe("meadow: budget and determinism", function()
	it("builds Map.Decor.Meadow with clusters of primitives only", function()
		expect(meadow ~= nil).toBe(true)
		expect(#clusters >= 30).toBe(true)
		for _, p in allParts() do
			expect(p.class).toBe("Part")
			expect((p.attributes or {}).MeshAsset).toBe(nil)
		end
	end)
	it("stays inside Meadow.PART_BUDGET and the world's PART_BUDGET of 1400", function()
		local n = #allParts()
		expect(n <= Meadow.PART_BUDGET).toBe(true)
		-- fills the budget: the band is the point of it
		expect(n >= Meadow.PART_BUDGET - 40).toBe(true)
		expect(WorldLayout.PART_BUDGET).toBe(1400)
		expect(Meadow.PART_BUDGET < WorldLayout.PART_BUDGET).toBe(true)
	end)
	it("is seeded: the same world every build", function()
		expect(WorldLayout.build()[1]).toEqual(built[1])
		expect(WorldLayout.meadowClusters()).toEqual(list)
	end)
	it("is decor only: nothing collides, is queried or touched", function()
		for _, p in allParts() do
			expect(p.canCollide).toBe(false)
			expect(p.canQuery).toBe(false)
			expect(p.canTouch).toBe(false)
		end
	end)
end)

describe("meadow: clearances", function()
	it("stays in the band behind the plots: INNER..OUTER, inside the border", function()
		-- the plots' outer corners sit at r ~184.4
		local half = WorldLayout.PLOT_SIZE / 2
		local corner = math.sqrt((WorldLayout.PLOT_RING_RADIUS + half) ^ 2 + half ^ 2)
		expect(Meadow.INNER > corner + 6).toBe(true)
		expect(Meadow.OUTER < PropClearance.EDGE_RADIUS).toBe(true)
		for _, p in allParts() do
			local lx, _, lz, hx, _, hz = bounds(p)
			for _, c in { { lx, lz }, { lx, hz }, { hx, lz }, { hx, hz } } do
				local r = math.sqrt(c[1] ^ 2 + c[2] ^ 2)
				expect(r > Meadow.INNER - 0.5 and r < Meadow.OUTER + 0.5).toBe(true)
			end
		end
	end)
	it("keeps far off the parade lane (r 68), the ring path and the landing ring", function()
		for _, p in allParts() do
			local r = math.sqrt(p.pos[1] ^ 2 + p.pos[3] ^ 2)
			expect(r > PropClearance.LANE_POSTS_OUTER + 100).toBe(true)
			expect(r > WorldLayout.RING_PATH_RADIUS + WorldLayout.RING_PATH_WIDTH / 2 + 100).toBe(true)
		end
	end)
	it("enters no keep-clear zone: plots, entrances, spoke paths, spots, buy stands, edge", function()
		for _, p in allParts() do
			local lx, _, lz, hx, _, hz = bounds(p)
			local hit = PropClearance.conflicts({
				pos = { (lx + hx) / 2, 0, (lz + hz) / 2 },
				size = { hx - lx, 0, hz - lz },
				yaw = 0,
			})
			if #hit > 0 then
				print("meadow part in a keep-clear zone", p.name, table.concat(hit, ", "))
			end
			expect(#hit).toBe(0)
		end
	end)
	it("keeps the plot entrances and spoke paths clear (plot-local check)", function()
		for _, p in allParts() do
			for i = 1, Config.PLOT_COUNT do
				local centre, yaw = WorldLayout.plotCentre(i)
				local a = math.rad(yaw)
				local dx, dz = p.pos[1] - centre[1], p.pos[3] - centre[3]
				local x = dx * math.cos(a) - dz * math.sin(a)
				local z = dx * math.sin(a) + dz * math.cos(a)
				-- the gate side faces the fountain (local -Z): nothing on the walk
				-- from the gate in to the fountain
				local inFront = z < -WorldLayout.PLOT_SIZE / 2
					and z > -WorldLayout.PLOT_RING_RADIUS
					and math.abs(x) < WorldLayout.GATE_SLOT
				expect(inFront).toBe(false)
			end
		end
	end)
	it("keeps clear of the kit props and the scattered rocks and mushrooms", function()
		local others = {}
		for _, prop in WorldLayout.RANCH_PROPS do
			table.insert(others, { prop.pos[1], prop.pos[3], prop.radius })
		end
		for _, n in decor.children do
			if string.match(n.name, "^Rock%d+$") then
				table.insert(others, { n.pos[1], n.pos[3], math.max(n.size[1], n.size[3]) / 2 })
			elseif string.match(n.name, "^Mushroom%d+$") then
				local stem = n.children[1]
				table.insert(others, { stem.pos[1], stem.pos[3], 2 })
			end
		end
		for _, p in allParts() do
			local lx, _, lz, hx, _, hz = bounds(p)
			local cx, cz, r = (lx + hx) / 2, (lz + hz) / 2, math.sqrt((hx - lx) ^ 2 + (hz - lz) ^ 2) / 2
			for _, o in others do
				expect((o[1] - cx) ^ 2 + (o[2] - cz) ^ 2 >= (o[3] + r) ^ 2).toBe(true)
			end
		end
	end)
	it("keeps every piece inside its own cluster circle, clusters apart", function()
		for _, c in list do
			for _, p in c.parts do
				local lx, _, lz, hx, _, hz = bounds(p)
				for _, q in { { lx, lz }, { lx, hz }, { hx, lz }, { hx, hz } } do
					expect(math.sqrt((q[1] - c.x) ^ 2 + (q[2] - c.z) ^ 2) <= c.radius + 0.5).toBe(true)
				end
			end
		end
		for a = 1, #list do
			for b = a + 1, #list do
				local d = math.sqrt((list[a].x - list[b].x) ^ 2 + (list[a].z - list[b].z) ^ 2)
				expect(d >= list[a].radius + list[b].radius).toBe(true)
			end
		end
	end)
end)

describe("meadow: grounded", function()
	it("rests every piece on the Ground: nothing floats, nothing fully buried", function()
		for _, p in allParts() do
			local _, ly, _, _, hy, _ = bounds(p)
			if ly > 0.02 then
				-- flower heads sit on their stem or leafy bunch, not on the Ground
				expect(string.match(p.name, "Head%d*$") ~= nil).toBe(true)
			end
			expect(hy > 0.1).toBe(true)
		end
	end)
	it("seats each flower head on its stem or leaves", function()
		for _, c in clusters do
			local byName: { [string]: any } = {}
			for _, p in c.children do
				byName[p.name] = p
			end
			for _, p in c.children do
				local base = string.match(p.name, "^(.-)Head%d*$")
				if base then
					local holder = byName[base .. "Stem"] or byName[base .. "Leaves"]
					expect(holder ~= nil).toBe(true)
					local _, _, _, _, top, _ = bounds(holder)
					-- the head's bottom is at or below its holder's top
					expect(p.pos[2] - p.size[2] / 2 <= top + 0.05).toBe(true)
				end
			end
		end
	end)
end)

describe("meadow: natural, not repetitive", function()
	it("mixes kinds, sizes and piece counts", function()
		local kinds: { [string]: number } = {}
		local counts: { [number]: boolean } = {}
		local nCounts = 0
		local rMin, rMax = math.huge, 0
		for _, c in list do
			kinds[c.kind] = (kinds[c.kind] or 0) + 1
			if not counts[#c.parts] then
				counts[#c.parts] = true
				nCounts += 1
			end
			rMin, rMax = math.min(rMin, c.radius), math.max(rMax, c.radius)
		end
		local nKinds = 0
		for _, n in kinds do
			if n >= 3 then
				nKinds += 1
			end
		end
		expect(nKinds >= 3).toBe(true)
		expect(nCounts >= 6).toBe(true)
		expect(rMax - rMin >= 3).toBe(true)
	end)
	it("spaces clusters unevenly (nearest-neighbour spread) but covers every octant", function()
		local dists = {}
		for a, c in list do
			local best = math.huge
			for b, o in list do
				if a ~= b then
					best = math.min(best, math.sqrt((c.x - o.x) ^ 2 + (c.z - o.z) ^ 2))
				end
			end
			table.insert(dists, best)
		end
		local mean = 0
		for _, d in dists do
			mean += d / #dists
		end
		local var = 0
		for _, d in dists do
			var += (d - mean) ^ 2 / #dists
		end
		-- coefficient of variation: a grid or a ring of equal steps is ~0
		expect(math.sqrt(var) / mean > 0.2).toBe(true)
		local octants = {}
		for _, c in clusters do
			local first = c.children[1]
			local k = math.floor((math.deg(math.atan2(first.pos[1], first.pos[3])) % 360) / 45) + 1
			octants[k] = (octants[k] or 0) + 1
		end
		for k = 1, 8 do
			expect((octants[k] or 0) >= 2).toBe(true)
		end
	end)
	it("never repeats a cluster layout", function()
		local seen: { [string]: boolean } = {}
		for _, c in list do
			local bits = {}
			for _, p in c.parts do
				table.insert(
					bits,
					string.format("%s:%.1f,%.1f:%.2f", p.shape, p.pos[1] - c.x, p.pos[3] - c.z, p.size[2])
				)
			end
			table.sort(bits)
			local key = table.concat(bits, "|")
			expect(seen[key]).toBe(nil)
			seen[key] = true
		end
	end)
end)
