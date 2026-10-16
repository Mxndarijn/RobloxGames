--!strict
-- Kit prop placement (RanchProps table -> WorldLayout slots): every kit mesh
-- is placed, placed awaiting upload (a pending tag) or listed as
-- intentionally unplaced, no prop footprint enters a keep-clear zone
-- (PropClearance), the world border or a habitat pad, every mesh slot is
-- scaled uniformly, each plot fence has exactly one opening (the gate), and
-- the placement is deterministic.
local fs = require("@lune/fs")

local Config = require("../src/shared/Config")
local Habitats = require("../src/shared/Habitats")
local MeshAssets = require("../src/shared/MeshAssets")
local PropClearance = require("../src/visuals/shared/PropClearance")
local RanchProps = require("../src/visuals/shared/RanchProps")
local TestRunner = require("./TestRunner")
local WorldBorder = require("../src/visuals/shared/WorldBorder")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Vec = { number }

local function walk(node: any, visit: (any) -> ())
	visit(node)
	for _, c in node.children or {} do
		walk(c, visit)
	end
end

local nodes = WorldLayout.build()

-- Every MeshAsset slot in the built world, by mesh name.
local function slotsByMesh(): { [string]: { any } }
	local out: { [string]: { any } } = {}
	for _, root in nodes do
		walk(root, function(n)
			local mesh = n.attributes and n.attributes.MeshAsset
			if mesh then
				out[mesh] = out[mesh] or {}
				table.insert(out[mesh], n)
			end
		end)
	end
	return out
end
local slots = slotsByMesh()

-- Slots placed but waiting for an upload: their mesh name rides on a pending
-- tag instead of MeshAsset (WorldBorder's BorderMesh pieces, the plot fence's
-- FenceMesh slots while ranch_fence_20 has no asset id).
local PENDING_TAGS = { "BorderMesh", "FenceMesh" }
local pending: { [string]: number } = {}
for _, root in nodes do
	walk(root, function(n)
		for _, tag in PENDING_TAGS do
			local mesh = n.attributes and n.attributes[tag]
			if mesh then
				pending[mesh] = (pending[mesh] or 0) + 1
			end
		end
	end)
end

local function placed(mesh: string): boolean
	if slots[mesh] or pending[mesh] then
		return true
	end
	for _, m in WorldLayout.PROP_MESHES do
		if m == mesh then
			return true
		end
	end
	return false
end

describe("ranch props: every kit mesh is placed", function()
	it("places every kit asset at least once (or awaiting upload) or lists it with a reason", function()
		local missing = {}
		for _, name in MeshAssets.NAMES do
			local reason = RanchProps.INTENTIONALLY_UNPLACED[name]
			if not placed(name) and not (type(reason) == "string" and #reason > 0) then
				table.insert(missing, name)
			end
		end
		expect(missing).toEqual({})
	end)
	it("covers the assets main added: fountain emerge, habitat looks, border models", function()
		local names = { "slime_fountain_emerge" }
		for _, k in WorldBorder.KINDS do
			table.insert(names, k.mesh)
		end
		for _, mesh in WorldBorder.ACCENTS do
			table.insert(names, mesh)
		end
		for _, h in Habitats.LIST do
			if h.kit and not h.newMesh then
				table.insert(names, h.kit)
			end
		end
		local missing = {}
		for _, name in names do
			expect(MeshAssets.get(name) ~= nil).toBe(true)
			if not placed(name) and RanchProps.INTENTIONALLY_UNPLACED[name] == nil then
				table.insert(missing, name)
			end
		end
		expect(missing).toEqual({})
		-- The emerge slimes are uploaded now: a real slot on the fountain.
		expect(MeshAssets.meshId("slime_fountain_emerge") ~= nil).toBe(true)
		expect(#(slots.slime_fountain_emerge or {})).toBe(1)
		-- New habitat looks without a kit mesh yet are no MeshAssets names.
		for _, id in Habitats.MESH_SLOTS do
			expect(MeshAssets.get(id)).toBe(nil)
		end
	end)
	it("tags a pending mesh only while it has no asset id", function()
		for mesh in pending do
			expect(MeshAssets.get(mesh) ~= nil).toBe(true)
			expect(MeshAssets.meshId(mesh)).toBe(nil)
		end
	end)
	it("keeps INTENTIONALLY_UNPLACED honest (real names, a reason, not placed anyway)", function()
		for name, reason in RanchProps.INTENTIONALLY_UNPLACED do
			expect(MeshAssets.get(name) ~= nil).toBe(true)
			expect(type(reason) == "string" and #reason >= 10).toBe(true)
			expect(placed(name)).toBe(false)
		end
	end)
	it("places only known kit meshes, with unique names, in a known cluster", function()
		local names = {}
		local clusters = {}
		for _, c in RanchProps.CLUSTERS do
			clusters[c] = true
		end
		for _, p in WorldLayout.RANCH_PROPS do
			expect(MeshAssets.get(p.mesh) ~= nil).toBe(true)
			expect(names[p.name]).toBe(nil)
			names[p.name] = true
			expect(clusters[p.cluster]).toBe(true)
		end
		expect(#WorldLayout.RANCH_PROPS).toBe(#RanchProps.PLACEMENTS)
	end)
	it("puts each RanchProps row in Map.Decor as a MeshAsset slot", function()
		local decor: any = nil
		for _, c in nodes[1].children do
			if c.name == "Decor" then
				decor = c
			end
		end
		local byName = {}
		for _, c in decor.children do
			byName[c.name] = c
		end
		for _, p in WorldLayout.RANCH_PROPS do
			local n = byName[p.name]
			expect(n ~= nil).toBe(true)
			expect(n.attributes.MeshAsset).toBe(p.mesh)
			expect(n.pos[2] - n.size[2] / 2).toBeCloseTo(0)
		end
	end)
end)

describe("ranch props: keep-clear zones", function()
	it("keeps every footprint off the lane, landing band, ring path, plots, entrances, fountain and spots", function()
		local bad = {}
		for _, p in WorldLayout.RANCH_PROPS do
			local hits = PropClearance.conflicts(p)
			if #hits > 0 then
				table.insert(bad, `{p.name}: {table.concat(hits, ", ")}`)
			end
		end
		expect(bad).toEqual({})
	end)
	it("has every zone the brief names", function()
		local names = {}
		for _, z in PropClearance.ZONES do
			names[z.name] = true
		end
		for _, name in
			{ "fountain", "slide", "landing band", "parade lane", "ring path", "ShopStand", "LeaderboardBoard" }
		do
			expect(names[name]).toBe(true)
		end
		for i = 1, Config.PLOT_COUNT do
			expect(names[`plot {i}`] and names[`plot {i} entrance`]).toBe(true)
		end
	end)
	it("catches a prop dropped on each zone (the checker is not a no-op)", function()
		local size = { 4, 4, 4 }
		local probes = {
			{ { 0, 2, 20 }, "slide" },
			{ { 0, 2, -48 }, "landing band" },
			{ { 68, 2, 0 }, "parade lane" },
			{ { 0, 2, -78 }, "ring path" },
		}
		local c1 = WorldLayout.plotCentre(1)
		table.insert(probes, { { c1[1], 2, c1[3] }, "plot 1" })
		-- just in front of plot 1's gate, inside the corridor
		table.insert(probes, { { 0, 2, c1[3] - 48 }, "plot 1 entrance" })
		for _, probe in probes do
			local hits = PropClearance.conflicts({ pos = probe[1], size = size, yaw = 0 })
			expect(table.find(hits, probe[2]) ~= nil).toBe(true)
		end
	end)
	it("never stacks two props in the same spot", function()
		local props = WorldLayout.RANCH_PROPS
		local bad = {}
		for i, a in props do
			for j = i + 1, #props do
				local b = props[j]
				if PropClearance.rectsOverlap(PropClearance.footprint(a), PropClearance.footprint(b), 0.5) then
					table.insert(bad, `{a.name} / {b.name}`)
				end
			end
		end
		expect(bad).toEqual({})
	end)
	it("keeps every prop off the world border: inside the wall ring, clear of every edge piece", function()
		local pieces = WorldBorder.pieces()
		local bad = {}
		for _, p in WorldLayout.RANCH_PROPS do
			local rect = PropClearance.footprint(p)
			local reach = math.sqrt(p.pos[1] ^ 2 + p.pos[3] ^ 2) + p.radius
			if reach >= WorldBorder.RADIUS - PropClearance.MARGIN then
				table.insert(bad, `{p.name}: wall`)
			end
			for _, q in pieces do
				if PropClearance.rectsOverlap(rect, PropClearance.footprint(q), PropClearance.MARGIN) then
					table.insert(bad, `{p.name}: {q.kind} at {math.round(q.angle)}`)
				end
			end
		end
		expect(bad).toEqual({})
		expect(#pieces > 100).toBe(true)
	end)
	it("keeps every prop off the habitat pads (the largest habitat look round each pad)", function()
		-- HabitatFx grows the look round the pad (dressing up to ~4.6 from its
		-- centre on an 8-stud pad): a 10 x 10 footprint per pad holds it.
		local half = 5
		local s = WorldLayout.PLOT_SIZE
		local bad = {}
		for i = 1, Config.PLOT_COUNT do
			local centre, yaw = WorldLayout.plotCentre(i)
			local a = math.rad(yaw)
			for j = 1, Config.PADS_MAX do
				local x, z = WorldLayout.padOffset(j)
				-- inside the fence, so props outside it can't reach a habitat
				expect(math.abs(x) + half < s / 2 - 1 and math.abs(z) + half < s / 2 - 1).toBe(true)
				local pad = {
					cx = centre[1] + x * math.cos(a) + z * math.sin(a),
					cz = centre[3] - x * math.sin(a) + z * math.cos(a),
					hx = half,
					hz = half,
					yaw = yaw,
				}
				for _, p in WorldLayout.RANCH_PROPS do
					if PropClearance.rectsOverlap(pad, PropClearance.footprint(p), PropClearance.MARGIN) then
						table.insert(bad, `plot {i} pad {j}: {p.name}`)
					end
				end
			end
		end
		expect(bad).toEqual({})
	end)
end)

describe("ranch props: uniform scale", function()
	it("scales every mesh slot in the world uniformly (native size x one number)", function()
		local bad = {}
		for mesh, list in slots do
			local native = (MeshAssets.get(mesh) :: any).size :: Vec
			for _, n in list do
				local s = n.size :: Vec
				local a, b, c = s[1] / native[1], s[2] / native[2], s[3] / native[3]
				if math.abs(a - b) > 1e-6 * a or math.abs(a - c) > 1e-6 * a then
					table.insert(bad, `{n.name} ({mesh}) {a} {b} {c}`)
				end
			end
		end
		expect(bad).toEqual({})
	end)
	it("keeps the table's scales positive and sane", function()
		for _, p in RanchProps.PLACEMENTS do
			expect(p.scale >= 0.5 and p.scale <= 2).toBe(true)
		end
	end)
	it("stays inside the mesh slot budget", function()
		local n = #WorldLayout.PROP_MESHES
		for _, list in slots do
			n += #list
		end
		expect(n <= WorldLayout.MESH_SLOT_BUDGET).toBe(true)
	end)
end)

-- World -> plot-local (x, z).
local function toLocal(i: number, x: number, z: number): (number, number)
	local centre, yaw = WorldLayout.plotCentre(i)
	local a = math.rad(yaw)
	local dx, dz = x - centre[1], z - centre[3]
	return dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
end

-- Plot-local rect of a part (yaw relative to the plot).
local function localRect(i: number, n: any): PropClearance.Rect
	local _, yaw = WorldLayout.plotCentre(i)
	local x, z = toLocal(i, n.pos[1], n.pos[3])
	return { cx = x, cz = z, hx = n.size[1] / 2, hz = n.size[3] / 2, yaw = n.rot[2] - yaw }
end

local function plotChild(plot: any, name: string): any
	for _, c in plot.children do
		if c.name == name then
			return c
		end
	end
	return nil
end

describe("plot fence", function()
	local plots = nodes[2].children
	local s = WorldLayout.PLOT_SIZE
	local line = s / 2 - 0.5

	it("has exactly one opening per enclosure: the gate slot on the front", function()
		for i, plot in plots do
			local blockers: { PropClearance.Rect } = {}
			walk(plot, function(n)
				local name = n.name :: string
				if n.class == "Part" and n.canCollide ~= false and (name:match("^Wall") or name:match("^GatePost")) then
					table.insert(blockers, localRect(i, n))
				end
			end)
			-- walk the fence line once round (back, right, front, left), 0.25 steps
			local samples = {}
			local step = 0.25
			local function sample(x: number, z: number)
				local p = { cx = x, cz = z, hx = 0.01, hz = 0.01, yaw = 0 }
				local closed = false
				for _, b in blockers do
					if PropClearance.rectsOverlap(b, p) then
						closed = true
						break
					end
				end
				table.insert(samples, { x = x, z = z, closed = closed })
			end
			for t = -line, line - step, step do
				sample(t, line)
			end
			for t = line, -line + step, -step do
				sample(line, t)
			end
			for t = line, -line + step, -step do
				sample(t, -line)
			end
			for t = -line, line - step, step do
				sample(-line, t)
			end
			local runs, open = 0, {}
			for k, smp in samples do
				local prev = samples[(k - 2) % #samples + 1]
				if not smp.closed then
					table.insert(open, smp)
					if prev.closed then
						runs += 1
					end
				end
			end
			expect(runs).toBe(1)
			local width = #open * step
			expect(width >= WorldLayout.GATE_CLEAR - 0.5 and width <= WorldLayout.GATE_SLOT).toBe(true)
			for _, smp in open do
				expect(smp.z).toBeCloseTo(-line)
				expect(math.abs(smp.x) < WorldLayout.GATE_SLOT / 2).toBe(true)
			end
		end
	end)
	it("keeps the walls as invisible colliders", function()
		for _, plot in plots do
			for _, name in { "WallBack", "WallLeft", "WallRight", "WallFrontL", "WallFrontR" } do
				local w = plotChild(plot, name)
				expect(w.transparency).toBe(1)
				expect(w.canCollide ~= false).toBe(true)
			end
		end
	end)
	it("lines the walls with kit fence segments on the 10-stud grid, gate slot open", function()
		local g = WorldLayout.FENCE_GRID
		expect(g).toBe(10)
		local native = (MeshAssets.get(WorldLayout.FENCE_SEGMENT) :: any).size :: Vec
		for i, plot in plots do
			local fence = plotChild(plot, "Fence")
			expect(fence ~= nil).toBe(true)
			local perSide = { Back = 0, Left = 0, Right = 0, Front = 0 }
			for _, seg in fence.children do
				expect(seg.attributes.MeshAsset).toBe(WorldLayout.FENCE_SEGMENT)
				expect(seg.canCollide).toBe(false)
				expect(seg.size[1]).toBeCloseTo(g)
				expect(seg.size[2] / native[2]).toBeCloseTo(WorldLayout.FENCE_SCALE)
				local side = string.match(seg.name, "^Segment(%a+)_%d+$") :: string
				perSide[side] += 1
				local x, z = toLocal(i, seg.pos[1], seg.pos[3])
				local along = if side == "Back" or side == "Front" then x else z
				local across = if side == "Back" or side == "Front" then z else x
				expect(math.abs(across)).toBeCloseTo(line)
				-- centres at odd multiples of 5: ends on the 10-stud grid
				expect(((along - g / 2) / g) % 1 < 1e-6 or ((along - g / 2) / g) % 1 > 1 - 1e-6).toBe(true)
				if side == "Front" then
					expect(math.abs(along) - g / 2 >= WorldLayout.GATE_SLOT / 2 - 1e-6).toBe(true)
				end
			end
			expect(perSide).toEqual({ Back = 8, Left = 8, Right = 8, Front = 6 })
			-- 6 x 10 + the 20-stud slot = 80 on the gate side
			expect(perSide.Front * g + WorldLayout.GATE_SLOT).toBe(s)
		end
	end)
	it("keeps the corner posts and the gate as kit models", function()
		for _, plot in plots do
			for k = 1, 4 do
				expect(plotChild(plot, `CornerPost_{k}`).attributes.MeshAsset).toBe("phoenix_corner_post")
			end
			expect(plotChild(plot, "Gate") ~= nil).toBe(true)
		end
	end)
end)

describe("ranch props: deterministic", function()
	it("builds the same world twice", function()
		expect(WorldLayout.build()).toEqual(nodes)
	end)
	it("uses no unseeded randomness in the placement code", function()
		for _, path in
			{
				"src/visuals/shared/RanchProps.luau",
				"src/visuals/shared/PropClearance.luau",
				"src/visuals/shared/WorldLayout.luau",
			}
		do
			local src = fs.readFile(path)
			expect(string.find(src, "math.random", 1, true)).toBe(nil)
			expect(string.find(src, "Random.new", 1, true)).toBe(nil)
			expect(string.find(src, "os.time", 1, true)).toBe(nil)
		end
	end)
end)
