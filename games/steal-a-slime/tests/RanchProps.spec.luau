--!strict
-- Kit prop placement (RanchProps table -> WorldLayout slots): every kit mesh
-- is placed, placed awaiting upload (a pending tag) or listed as
-- intentionally unplaced, no prop footprint enters a keep-clear zone
-- (PropClearance), the world border or a habitat pad, every mesh slot is
-- scaled uniformly, each plot fence has exactly one opening (the gate) with
-- 20-stud panels (or their two-segment fallback) on the grid, and the
-- placement is deterministic. Budgets: tests/WorldBudget.spec.
local fs = require("@lune/fs")

local Config = require("../src/shared/Config")
local Habitats = require("../src/shared/Habitats")
local MeshAssets = require("../src/shared/MeshAssets")
local PropClearance = require("../src/visuals/shared/PropClearance")
local RanchProps = require("../src/visuals/shared/RanchProps")
local TestRunner = require("./TestRunner")
local WorldBorder = require("../src/visuals/shared/WorldBorder")
local WorldLayout = require("../src/visuals/shared/WorldLayout")
local YardGen = require("../tools/yard/YardGen")

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

-- Habitat looks with their own mesh (Habitats.MESH_SLOTS, main #57/#58) are
-- placed by HabitatFx on the pads at runtime, not by WorldLayout.
local habitatMeshes: { [string]: boolean } = {}
for _, id in Habitats.MESH_SLOTS do
	local kit = (Habitats.get(id) :: any).kit
	if kit then
		habitatMeshes[kit] = true
	end
end

local function placed(mesh: string): boolean
	if slots[mesh] or pending[mesh] or habitatMeshes[mesh] then
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
		for _, k in WorldBorder.CHUNKS do
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
			{
				"fountain",
				"slide",
				"landing band",
				"parade lane",
				"ring path",
				"ItemShopStand",
				"UpgradeShopStand",
				"LeaderboardBoard",
			}
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
				-- yard scenes: a bench or table may stand under a tree's canopy (its footprint), and a fence run's corners join
				local scene = a.cluster == "yard"
					and b.cluster == "yard"
					and (
						YardGen.isCanopy(a.mesh)
						or YardGen.isCanopy(b.mesh)
						or (string.find(a.mesh, "fence") ~= nil and string.find(b.mesh, "fence") ~= nil)
					)
				if
					not scene
					and PropClearance.rectsOverlap(PropClearance.footprint(a), PropClearance.footprint(b), 0.5)
				then
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
		expect(#pieces > 30).toBe(true)
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
				if
					n.class == "Part"
					and n.canCollide ~= false
					and ((n.attributes :: any) and (n.attributes :: any).FenceCollider or name:match("^GatePost"))
				then
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
	it("has no invisible Wall* blocks: the fence meshes (MeshAssets.COLLISION Box) are the walls (bug #11)", function()
		for _, plot in plots do
			for _, name in { "WallBack", "WallLeft", "WallRight", "WallFrontL", "WallFrontR" } do
				expect(plotChild(plot, name)).toBe(nil)
			end
		end
	end)
	-- Fence pieces of one build, checked for either mode: a ranch_fence_20 slot
	-- (uploaded) or a FenceMesh Model of two phoenix_fence_segment halves
	-- (fallback) per 20-stud panel, and 10-stud segments beside the gate.
	local function checkFence(built: { any }, uploadedMode: boolean)
		local g, h = WorldLayout.FENCE_GRID, WorldLayout.FENCE_SEGMENT_GRID
		expect(g).toBe(20)
		expect(h).toBe(10)
		local function native(mesh: string): Vec
			return (MeshAssets.get(mesh) :: any).size :: Vec
		end
		local function onGrid(v: number, step: number): boolean
			local f = (v / step) % 1
			return f < 1e-6 or f > 1 - 1e-6
		end
		for i, plot in built[2].children do
			local fence = plotChild(plot, "Fence")
			expect(fence ~= nil).toBe(true)
			local spans: { [string]: { { number } } } = { Back = {}, Left = {}, Right = {}, Front = {} }
			local panels, segments = 0, 0
			local function slot(n: any, mesh: string, length: number)
				expect(n.class).toBe("Part")
				expect(n.attributes.MeshAsset).toBe(mesh)
				expect(n.canCollide ~= false).toBe(true) -- the Box collider until the mesh lands (bug #11)
				expect(n.size[1]).toBeCloseTo(length)
				expect(n.size[2] / native(mesh)[2]).toBeCloseTo(WorldLayout.FENCE_SCALE)
				expect(n.size[2]).toBeCloseTo(native(WorldLayout.FENCE_SEGMENT)[2] * WorldLayout.FENCE_SCALE)
			end
			for _, seg in fence.children do
				if seg.name == "GatePost" then
					continue -- checked in "shows one post at every joint"
				end
				local side = string.match(seg.name, "^Segment(%a+)_%d+$") :: string
				expect(spans[side] ~= nil).toBe(true)
				local cx, cz, length
				if seg.class == "Model" then
					-- fallback panel: two halves on the 10 grid, 10 apart
					expect(uploadedMode).toBe(false)
					expect(seg.attributes.FenceMesh).toBe(WorldLayout.FENCE_MESH)
					expect(#seg.children).toBe(2)
					local a, b = seg.children[1], seg.children[2]
					slot(a, WorldLayout.FENCE_SEGMENT, h)
					slot(b, WorldLayout.FENCE_SEGMENT, h)
					local ax, az = toLocal(i, a.pos[1], a.pos[3])
					local bx, bz = toLocal(i, b.pos[1], b.pos[3])
					expect(math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)).toBeCloseTo(h)
					cx, cz, length = (ax + bx) / 2, (az + bz) / 2, g
					panels += 1
				elseif seg.attributes.MeshAsset == WorldLayout.FENCE_MESH then
					expect(uploadedMode).toBe(true)
					slot(seg, WorldLayout.FENCE_MESH, g)
					cx, cz = toLocal(i, seg.pos[1], seg.pos[3])
					length = g
					panels += 1
				else
					slot(seg, WorldLayout.FENCE_SEGMENT, h)
					cx, cz = toLocal(i, seg.pos[1], seg.pos[3])
					length = h
					segments += 1
				end
				local along = if side == "Back" or side == "Front" then cx else cz
				local across = if side == "Back" or side == "Front" then cz else cx
				expect(math.abs(across)).toBeCloseTo(line)
				-- ends on the grid: panels on the 20 grid from the corner, segments on the 10 grid
				local lo, hi = along - length / 2, along + length / 2
				expect(onGrid(lo, h) and onGrid(hi, h)).toBe(true)
				if length == g then
					expect(onGrid(lo + s / 2, g) or onGrid(s / 2 - hi, g)).toBe(true)
				end
				table.insert(spans[side], { lo, hi })
			end
			expect(panels).toBe(14)
			expect(segments).toBe(2)
			-- every side covered end to end without overlap; the front leaves the gate slot
			for side, list in spans do
				table.sort(list, function(a, b)
					return a[1] < b[1]
				end)
				local covered = 0
				for k, span in list do
					covered += span[2] - span[1]
					if k > 1 then
						expect(span[1] >= list[k - 1][2] - 1e-6).toBe(true)
					end
					if side == "Front" then
						expect(
							span[2] <= -WorldLayout.GATE_SLOT / 2 + 1e-6 or span[1] >= WorldLayout.GATE_SLOT / 2 - 1e-6
						).toBe(true)
					end
				end
				expect(covered).toBeCloseTo(if side == "Front" then s - WorldLayout.GATE_SLOT else s)
				expect(#list).toBe(4)
			end
		end
	end
	it("lines the walls with 20-stud fence panels, two 10-stud segments beside the open gate slot", function()
		checkFence(nodes, WorldLayout.fenceUploaded())
	end)
	it("builds the uploaded layout too: one ranch_fence_20 slot per panel", function()
		local entry = MeshAssets.entries[WorldLayout.FENCE_MESH] :: any
		local was = entry.meshId
		entry.meshId = "rbxassetid://0"
		local ok, built = pcall(WorldLayout.build)
		entry.meshId = was
		expect(ok).toBe(true)
		checkFence(built, true)
	end)
	it("builds the fallback layout too: two phoenix_fence_segment per panel", function()
		local entry = MeshAssets.entries[WorldLayout.FENCE_MESH] :: any
		local was = entry.meshId
		entry.meshId = nil
		local ok, built = pcall(WorldLayout.build)
		entry.meshId = was
		expect(ok).toBe(true)
		checkFence(built, false)
	end)
	-- Kit pieces carry one post, at their -X end (+ the panel's mid post).
	-- Round the loop each joint and corner gets the next piece's post and the
	-- gate's right stub gets the GatePost: exactly one post at every piece end,
	-- never two side by side, in both fence modes.
	local function checkPosts(built: { any })
		local inset = WorldLayout.FENCE_POST_INSET
		-- An upload comes in turned 180 from the kit axes (kit x -> import -x)
		-- and MeshSwap turns each Part slot's mesh MeshAssets.IMPORT_YAW back,
		-- so a kit -X post must land on the slot's -X end.
		local turn = math.cos(math.rad(MeshAssets.IMPORT_YAW))
		local function slotX(kitX: number): number
			return turn * -kitX
		end
		for i, plot in built[2].children do
			local _, plotYaw = WorldLayout.plotCentre(i)
			local posts: { { number } } = {}
			local ends: { { number } } = {}
			local gatePosts = 0
			local function piece(n: any, mid: boolean)
				local x, z = toLocal(i, n.pos[1], n.pos[3])
				local a = math.rad(n.rot[2] - plotYaw)
				local dx, dz = math.cos(a), -math.sin(a)
				local half = n.size[1] / 2
				local post = slotX(inset - half)
				table.insert(posts, { x + dx * post, z + dz * post })
				if mid then
					local m = slotX(inset)
					table.insert(posts, { x + dx * m, z + dz * m })
				end
				table.insert(ends, { x - dx * half, z - dz * half })
				table.insert(ends, { x + dx * half, z + dz * half })
			end
			for _, n in plotChild(plot, "Fence").children do
				if n.name == "GatePost" then
					expect(n.attributes.MeshAsset).toBe(WorldLayout.GATE_POST_MESH)
					expect(n.canCollide ~= false).toBe(true)
					local x, z = toLocal(i, n.pos[1], n.pos[3])
					table.insert(posts, { x, z })
					gatePosts += 1
					-- mirrors the left gate segment's post across the gate
					expect(x).toBeCloseTo(WorldLayout.GATE_SLOT / 2 + inset)
					expect(z).toBeCloseTo(-line)
				elseif n.class == "Model" then
					piece(n.children[1], false)
					piece(n.children[2], false)
				else
					piece(n, n.attributes.MeshAsset == WorldLayout.FENCE_MESH)
				end
			end
			expect(gatePosts).toBe(1)
			-- every piece end (joints, corners, both gate stubs): one post within 1.5
			for _, e in ends do
				local near = 0
				for _, p in posts do
					if (p[1] - e[1]) ^ 2 + (p[2] - e[2]) ^ 2 < 1.5 ^ 2 then
						near += 1
					end
				end
				expect(near).toBe(1)
			end
			-- no doubled posts anywhere: posts at least a post width apart
			for a = 1, #posts do
				for b = a + 1, #posts do
					local d = math.sqrt((posts[a][1] - posts[b][1]) ^ 2 + (posts[a][2] - posts[b][2]) ^ 2)
					expect(d > 2).toBe(true)
				end
			end
			-- and one at each gate stub, mirrored
			for _, sx in { -1, 1 } do
				local near = 0
				for _, p in posts do
					if
						math.abs(p[1] - sx * (WorldLayout.GATE_SLOT / 2 + inset)) < 1e-6
						and math.abs(p[2] + line) < 1e-6
					then
						near += 1
					end
				end
				expect(near).toBe(1)
			end
		end
	end
	it("shows one post at every joint, corner and gate stub (uploaded and fallback)", function()
		local entry = MeshAssets.entries[WorldLayout.FENCE_MESH] :: any
		local was = entry.meshId
		for _, up in { true, false } do
			entry.meshId = if up then "rbxassetid://0" else nil
			local ok, built = pcall(WorldLayout.build)
			entry.meshId = was
			expect(ok).toBe(true)
			checkPosts(built)
		end
	end)
	-- The corners close on the next side's -X end post (checked above), so
	-- there is no plot corner post slot.
	it("keeps the gate as a kit model and no corner post slots", function()
		for _, plot in plots do
			for k = 1, 4 do
				expect(plotChild(plot, `CornerPost_{k}`)).toBe(nil)
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
