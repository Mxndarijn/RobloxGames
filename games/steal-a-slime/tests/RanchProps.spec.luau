--!strict
-- Kit prop placement (RanchProps table -> WorldLayout slots): every kit mesh
-- is placed, placed awaiting upload (a pending tag) or listed as
-- intentionally unplaced, no prop footprint enters a keep-clear zone
-- (PropClearance), the world border or a habitat pad, every mesh slot is
-- scaled uniformly, each plot's jar has exactly one way in (the door, with
-- the bridge lined up to it), and the placement is deterministic. Budgets: tests/WorldBudget.spec.

local Config = require("../src/shared/Config")
local Habitats = require("../src/shared/Habitats")
local MeshAssets = require("../src/shared/MeshAssets")
local PropClearance = require("../src/visuals/shared/PropClearance")
local PvpModels = require("../src/shared/PvpModels")
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
-- tag instead of MeshAsset (WorldBorder's BorderMesh pieces).
local PENDING_TAGS = { "BorderMesh" }
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

-- Habitat layers are placed by HabitatFx on the pads at runtime, not by
-- WorldLayout.
local habitatMeshes: { [string]: boolean } = {}
for _, mesh in Habitats.MESHES do
	habitatMeshes[mesh] = true
end

local function placed(mesh: string): boolean
	if slots[mesh] or pending[mesh] or habitatMeshes[mesh] then
		return true
	end
	for _, stand in WorldLayout.SHOP_STANDS do -- every shop stand skin
		if stand.mesh == mesh then
			return true
		end
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
			local held = table.find(PvpModels.MESHES, name) ~= nil -- a held PvP item (server/PvpHeld), never a world slot
			if not placed(name) and not held and not (type(reason) == "string" and #reason > 0) then
				table.insert(missing, name)
			end
		end
		expect(missing).toEqual({})
	end)
	it("covers the assets main added: fountain emerge, border models", function()
		local names = { "slime_fountain_emerge" }
		for _, k in WorldBorder.CHUNKS do
			table.insert(names, k.mesh)
		end
		for _, mesh in WorldBorder.ACCENTS do
			table.insert(names, mesh)
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
		-- just in front of plot 1's bridge, inside the corridor
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
		-- HabitatFx grows the overlay on the pad (dressing up to ~4 from its
		-- centre on an 8-stud pad): a 10 x 10 footprint per pad holds it.
		local half = 5
		local s = WorldLayout.PLOT_SIZE
		local bad = {}
		for i = 1, Config.PLOT_COUNT do
			local centre, yaw = WorldLayout.plotCentre(i)
			local a = math.rad(yaw)
			for j = 1, Config.PADS_MAX do
				local x, z = WorldLayout.padOffset(j)
				-- inside the plot, so props outside it can't reach a habitat
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

describe("plot jar", function()
	local plots = nodes[2].children
	local s = WorldLayout.PLOT_SIZE
	local floor = WorldLayout.PLOT_FLOOR_TOP

	-- Collidable Parts under `root` whose height span covers plot-local height y.
	local function collidersAt(root: any, y: number): { any }
		local out = {}
		walk(root, function(n)
			if n.class == "Part" and n.canCollide ~= false then
				local h = if n.shape == "Cylinder" then n.size[1] else n.size[2]
				if math.abs(n.pos[2] - y) <= h / 2 then
					table.insert(out, n)
				end
			end
		end)
		return out
	end

	-- Does any of `parts` cover plot-local point (x, z)? Upright cylinders by radius, the rest as rotated boxes.
	local function covered(i: number, parts: { any }, x: number, z: number): boolean
		local probe = { cx = x, cz = z, hx = 0.01, hz = 0.01, yaw = 0 }
		for _, n in parts do
			if n.shape == "Cylinder" then
				local px, pz = toLocal(i, n.pos[1], n.pos[3])
				if (px - x) ^ 2 + (pz - z) ^ 2 <= (n.size[2] / 2) ^ 2 then
					return true
				end
			elseif PropClearance.rectsOverlap(localRect(i, n), probe) then
				return true
			end
		end
		return false
	end

	it("closes jar 1's glass all round except one doorway at -Z, inside the stopper's span", function()
		local door = WorldLayout.doorway()
		local r = WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL / 2
		local step = 0.25
		local n = math.ceil(2 * math.pi * r / step)
		for i, plot in plots do
			local jar = plotChild(plot, "Jar")
			expect(jar ~= nil).toBe(true)
			local lintels = 0
			for _, c in jar.children do
				if c.name == "DoorLintel" then
					lintels += 1
				end
			end
			expect(lintels).toBe(1)
			-- walking height: one open run (the door), centred on the -Z axis, no wider than the stopper
			local walls = collidersAt(jar, floor + 2.5)
			local samples = {}
			for k = 0, n - 1 do
				local x, z = WorldLayout.jarWallPoint(1, k * 360 / n)
				table.insert(samples, { x = x, z = z, closed = covered(i, walls, x, z) })
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
			local width = #open * 2 * math.pi * r / n
			expect(width >= 4).toBe(true) -- a character fits through
			for _, smp in open do
				expect(smp.z < 0).toBe(true)
				expect(math.abs(smp.x) <= door.halfWidth).toBe(true)
			end
			-- above the door the lintel closes the ring
			local above = collidersAt(jar, floor + WorldLayout.DOOR.height + 0.5)
			for _, smp in samples do
				expect(covered(i, above, smp.x, smp.z)).toBe(true)
			end
		end
	end)
	it("lays one bridge from the plot edge over the moat to the door, lined up with it", function()
		local door = WorldLayout.doorway()
		for i, plot in plots do
			local bridges = 0
			for _, c in plot.children do
				if c.name == "Bridge" then
					bridges += 1
				end
			end
			expect(bridges).toBe(1)
			local bridge = plotChild(plot, "Bridge")
			expect(bridge.canCollide ~= false).toBe(true)
			local rect = localRect(i, bridge)
			expect(math.abs(math.sin(math.rad(rect.yaw)))).toBeCloseTo(0)
			-- straddles the door's span
			expect(math.abs(rect.cx) + door.halfWidth <= rect.hx + 1e-6).toBe(true)
			-- from the plot edge, over the moat, up to the glass
			expect(rect.cz - rect.hz >= -s / 2 - 1e-6).toBe(true)
			expect(rect.cz - rect.hz <= -WorldLayout.MOAT.outer).toBe(true)
			expect(rect.cz + rect.hz >= -(WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL)).toBe(true)
			-- a step up from the Base a character walks onto
			local top = bridge.pos[2] + bridge.size[2] / 2 - floor
			expect(top >= 0 and top <= 0.5).toBe(true)
		end
	end)
	it("keeps the walk from the plot edge over the bridge and through the door free of colliders", function()
		local inside = -(WorldLayout.jarRadius(1) - WorldLayout.DOOR_INNER_INSET - 1)
		local blocked = {}
		for i, plot in plots do
			for y = floor + 0.5, floor + 5, 0.5 do
				local parts = collidersAt(plot, y)
				for z = -s / 2, inside, 0.25 do
					for x = -1.5, 1.5, 0.5 do
						if covered(i, parts, x, z) then
							table.insert(blocked, `plot {i} at ({x}, {y}, {z})`)
						end
					end
				end
			end
		end
		expect(blocked).toEqual({})
	end)
end)

describe("ranch props: deterministic", function()
	it("builds the same world twice", function()
		expect(WorldLayout.build()).toEqual(nodes)
	end)
end)
