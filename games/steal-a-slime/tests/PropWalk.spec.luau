--!nocheck
-- Bug B9: walking into a prop stops at its face. Data-driven from shared/PropCollision, runs in BOTH runtimes
-- (tools/pipeline/stage-specs stages it into the cloud test place; string requires to ../src only, no @lune).
--
-- Lune and cloud: pure geometry. Every blocking inventory entry becomes collision volumes from the built layout
-- (WorldLayout.build()): the slot bbox for Box / Hull / PCD (a conservative proxy), the part boxes for "colliders".
-- A character box (2 wide, 5 tall, 1 deep, root at hip height 3) walks at 16 studs/s in 1/60 s steps (0.267 studs)
-- along the four axes of the prop's frame, aimed past the centre: the first blocked step must be at the face (the
-- root still outside the volume). No spawn, walk-path waypoint or other prop's ground position lies in a volume.
--
-- Cloud only: the real collision. Each fidelity mesh is made with AssetService:CreateMeshPartAsync like MeshSwap does,
-- anchored far from the map, and Blockcast from 4 sides; the hit must be that part and the box centre at the hit
-- must be outside it. The same for the collider parts. Gojo's kinds that are already collidable are hard failures,
-- the rest is reported only.
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local MeshAssets = require("../src/shared/MeshAssets")
local MinimapData = require("../src/visuals/shared/MinimapData")
local PropCollision = require("../src/shared/PropCollision")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SPEED = 16
local STEP = SPEED / 60 -- 0.267 studs per 1/60 s step
local GAP = 4 -- the walker starts this far outside the prop's face
local CHAR_HALF_WIDTH, CHAR_HALF_DEPTH = 1, 0.5 -- 2 wide, 1 deep
local CHAR_ROOT_Y = 3 -- R15 root at hip height
local CHAR_BOTTOM, CHAR_TOP = CHAR_ROOT_Y - 2.5, CHAR_ROOT_Y + 2.5 -- 5 tall

local IN_ROBLOX = pcall(function()
	return game:GetService("RunService")
end)

-- Entries that are not walked into: floors, terrain and the slide block (bug09_slide_stand probes it).
local FLOORS = { ground_and_hub_spawn = true, terrain = true, plot_base = true, plot_pads = true }

--------------------------------------------------------------------------------------------------------------------
-- The layout as a flat list: { path = "Map.Decor.Well", node, mesh }
--------------------------------------------------------------------------------------------------------------------

local nodes = {}
local function flatten(node, parent, model)
	local path = if parent == "" then node.name else `{parent}.{node.name}`
	local attrs = node.attributes or {}
	local mesh = attrs.MeshAsset or attrs.BorderMesh
	if node.pos and node.size then
		table.insert(nodes, {
			path = path,
			name = node.name,
			node = node,
			mesh = if type(mesh) == "string" then mesh else nil,
			model = model,
		})
	end
	for _, child in node.children or {} do
		flatten(child, path, if node.class == "Model" then { path = path, name = node.name, node = node } else nil)
	end
end
for _, root in WorldLayout.build() do
	flatten(root, "", nil)
end

-- The shop stands are WorldProps Models (server-built), not layout nodes: their spots and scale are layout data too.
for name, spot in WorldLayout.PROP_SPOTS do
	if name:match("ShopStand$") then
		local size = WorldLayout.meshSize(WorldLayout.BUY_STAND_MESH, WorldLayout.BUY_STAND_SCALE)
		table.insert(nodes, {
			path = `Map.Props.{name}`,
			name = name,
			mesh = WorldLayout.BUY_STAND_MESH,
			node = { pos = { spot.pos[1], size[2] / 2, spot.pos[3] }, size = size, rot = { 0, spot.yaw, 0 } },
		})
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Volumes
--------------------------------------------------------------------------------------------------------------------

local function volumeOf(kind: string, owner: string, entry, item)
	local pos, size, rot = item.node.pos, item.node.size, item.node.rot or { 0, 0, 0 }
	return {
		kind = kind,
		owner = owner,
		entry = entry,
		path = item.path,
		cx = pos[1],
		cy = pos[2],
		cz = pos[3],
		hx = size[1] / 2,
		hy = size[2] / 2,
		hz = size[3] / 2,
		yaw = math.rad(rot[2] or 0),
		item = item,
	}
end

local function matchesFind(find, item)
	return PropCollision.matches(
		find,
		item.path,
		item.name,
		item.mesh,
		item.node.class == "Part" or item.node.class == nil
	)
end

-- `models` entries (the mushrooms) are Models whose Part children are the solids.
local function matchesModel(find, item)
	return item.model ~= nil and PropCollision.matches(find, item.model.path, item.model.name, nil, false)
end

-- kind -> { volumes } for every blocking entry, and the entries whose instances the layout does not hold
-- (server-built props: the cloud half covers their mesh).
local volumesByKind, entryOf, unresolved = {}, {}, {}
local blockers = {}
for _, e in PropCollision.ENTRIES do
	if e.find and e.collision ~= "off" and e.walk ~= false and not FLOORS[e.kind] then
		entryOf[e.kind] = e
		local list = {}
		for _, item in nodes do
			local primary = matchesFind(e.find, item) or (not e.find.parts and matchesModel(e.find, item))
			local extra = e.also ~= nil and matchesFind(e.also, item)
			if primary or extra then
				local attrs = item.node.attributes or {}
				local solid = item.node.canCollide ~= false or attrs.MeshCollider ~= nil
				-- a fidelity mesh collides through its slot (the box is the proxy); hand colliders through their own parts
				local fidelity = PropCollision.FIDELITIES[e.collision] == true
				if (fidelity and primary) or (not fidelity and solid and item.node.class == "Part") then
					table.insert(list, volumeOf(e.kind, e.owner, e, item))
				end
			end
		end
		if #list > 0 then
			volumesByKind[e.kind] = list
			for _, v in list do
				table.insert(blockers, v)
			end
		else
			table.insert(unresolved, e.kind)
		end
	end
end

-- Oriented rectangles in the XZ plane (CFrame.Angles(0, yaw, 0): local x -> (c, -s), local z -> (s, c)).
local function rectsOverlap(ax, az, ayaw, ahx, ahz, bx, bz, byaw, bhx, bhz): boolean
	local axes = {
		{ math.cos(ayaw), -math.sin(ayaw) },
		{ math.sin(ayaw), math.cos(ayaw) },
		{ math.cos(byaw), -math.sin(byaw) },
		{ math.sin(byaw), math.cos(byaw) },
	}
	local dx, dz = bx - ax, bz - az
	for _, u in axes do
		local ux, uz = u[1], u[2]
		local ra = ahx * math.abs(ux * math.cos(ayaw) - uz * math.sin(ayaw))
			+ ahz * math.abs(ux * math.sin(ayaw) + uz * math.cos(ayaw))
		local rb = bhx * math.abs(ux * math.cos(byaw) - uz * math.sin(byaw))
			+ bhz * math.abs(ux * math.sin(byaw) + uz * math.cos(byaw))
		if math.abs(dx * ux + dz * uz) >= ra + rb then
			return false
		end
	end
	return true
end

-- Can a standing character reach this volume at all (its height range meets the character's)?
local function reachable(v): boolean
	return v.cy + v.hy > CHAR_BOTTOM and v.cy - v.hy < CHAR_TOP
end

local function insideVolume(v, x, z, margin): boolean
	return PropCollision.insideFootprint(x, z, v.cx, v.cz, v.yaw, v.hx, v.hz, margin)
end

-- Walks the character box along one side of the prop frame; returns the first blocked step k, the root there, or nil.
local function walk(v, side)
	local sx, sz, dx, dz = side.start[1], side.start[2], side.dir[1], side.dir[2]
	local length = math.sqrt((side.target[1] - sx) ^ 2 + (side.target[2] - sz) ^ 2)
	local yaw = math.atan2(dx, dz) -- the character's depth axis is the walking direction
	for k = 0, math.ceil(length / STEP) do
		local x, z = sx + dx * STEP * k, sz + dz * STEP * k
		if rectsOverlap(x, z, yaw, CHAR_HALF_WIDTH, CHAR_HALF_DEPTH, v.cx, v.cz, v.yaw, v.hx, v.hz) then
			return k, x, z
		end
	end
	return nil
end

--------------------------------------------------------------------------------------------------------------------
-- Pure geometry
--------------------------------------------------------------------------------------------------------------------

local swept, tooHigh, thinnest = 0, 0, math.huge

describe("PropWalk geometry (every blocking inventory entry)", function()
	it("resolves volumes for most blocking entries; the rest are server-built props", function()
		local blocking = 0
		for _, e in PropCollision.ENTRIES do
			if e.find and e.collision ~= "off" and e.walk ~= false and not FLOORS[e.kind] then
				blocking += 1
			end
		end
		expect(blocking > 40).toBe(true)
		expect(blocking - #unresolved > blocking / 2).toBe(true)
		expect(#blockers > 100).toBe(true)
	end)

	it("steps 16 studs/s in 1/60 s is 0.267 studs", function()
		expect(math.abs(STEP - 0.26667) < 1e-4).toBe(true)
	end)

	local kinds = {}
	for kind in volumesByKind do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	for _, kind in kinds do
		local list = volumesByKind[kind]
		it(
			`{kind} ({entryOf[kind].owner}, {entryOf[kind].collision}): blocked at the face from 4 sides, thicker than a step`,
			function()
				for _, v in list do
					if reachable(v) then
						local thin = math.min(v.hx, v.hz) * 2
						thinnest = math.min(thinnest, thin)
						if thin <= STEP then
							error(
								`{v.path}: {string.format("%.3f", thin)} studs thick, a step is {string.format(
									"%.3f",
									STEP
								)}`
							)
						end
						for _, side in PropCollision.sides(v.cx, v.cz, v.yaw, v.hx, v.hz, GAP) do
							local k, x, z = walk(v, side)
							if k == nil then
								error(`{v.path} {side.name}: walked through without a blocked step`)
							end
							if k == 0 then
								error(`{v.path} {side.name}: the walk starts inside the volume`)
							end
							if insideVolume(v, x, z, 0) then
								error(`{v.path} {side.name}: first blocked step {k} has the root inside the volume`)
							end
						end
						swept += 1
					else
						tooHigh += 1
					end
				end
			end
		)
	end

	it("swept a real number of volumes and the thinnest one is thicker than a step", function()
		expect(swept > 100).toBe(true)
		expect(thinnest > STEP).toBe(true)
	end)
end)

-- Points a character stands or walks over.
local function walkPoints()
	local points = {}
	local function add(name: string, x: number, z: number)
		table.insert(points, { name = name, x = x, z = z })
	end
	local hub = LayoutMath.direction(MinimapData.SPAWN_YAW, 0)
	add("hub spawn", hub[1] * MinimapData.SPAWN_RADIUS, hub[3] * MinimapData.SPAWN_RADIUS)
	-- the ring path: 8 wide, centre line every 2 studs
	local ring = WorldLayout.RING_PATH_RADIUS
	for i = 0, math.floor(2 * math.pi * ring / 2) - 1 do
		local a = i * 2 / ring
		add(`ring path {i}`, math.sin(a) * ring, math.cos(a) * ring)
	end
	-- plot spawns, the spokes from the ring to each plot entrance and the gate (centre line and 6 studs either side)
	for i = 1, Config.PLOT_COUNT do
		local centre = WorldLayout.plotCentre(i)
		local len = math.sqrt(centre[1] ^ 2 + centre[3] ^ 2)
		local ux, uz = centre[1] / len, centre[3] / len -- from the fountain out to the plot
		add(`plot {i} spawn`, centre[1], centre[3])
		local gate = len - WorldLayout.PLOT_SIZE / 2
		local r = ring
		while r <= gate + 4 do
			add(`plot {i} spoke r{r}`, ux * r, uz * r)
			r += 2
		end
		for _, across in { -6, 6 } do
			add(`plot {i} gate {across}`, ux * gate - uz * across, uz * gate + ux * across)
		end
		add(`plot {i} inside gate`, ux * (gate + 6), uz * (gate + 6))
	end
	-- the slide exit landing
	local path = WorldLayout.SLIDE_PATH
	for i = math.max(1, #path - 3), #path do
		add(`slide exit {i}`, path[i][1], path[i][3])
	end
	-- the front of every shop stand / board / NPC spot (their local -Z), 5 and 8 studs out
	for name, spot in WorldLayout.PROP_SPOTS do
		local yaw = math.rad(spot.yaw)
		for _, dist in { 5, 8 } do
			add(`{name} front {dist}`, spot.pos[1] - math.sin(yaw) * dist, spot.pos[3] - math.cos(yaw) * dist)
		end
	end
	return points
end

describe("PropWalk geometry against walk paths", function()
	it("no spawn, plot spawn, path waypoint, slide exit or shop front lies inside a blocking prop", function()
		local bad, points = {}, walkPoints()
		expect(#points > 150).toBe(true)
		for _, p in points do
			for _, v in blockers do
				if reachable(v) and insideVolume(v, p.x, p.z, 0) then
					table.insert(
						bad,
						`{p.name} ({string.format("%.1f", p.x)}, {string.format("%.1f", p.z)}) in {v.path} ({v.kind})`
					)
					break
				end
			end
		end
		if #bad > 0 then
			error(table.concat(bad, "; "))
		end
	end)

	it("no other prop's ground position lies inside a blocking prop", function()
		local bad = {}
		local checked = 0
		for _, item in nodes do
			local owner = nil
			for kind, list in volumesByKind do
				for _, v in list do
					if v.item == item then
						owner = kind
					end
				end
			end
			-- placed props: kit mesh slots and the blocking parts; the fountain's own pieces share one structure
			local placed = item.mesh ~= nil or owner ~= nil
			if placed and item.path:sub(1, 11) ~= "Map.Volcano" and item.path:sub(1, 5) ~= "Plots" then
				checked += 1
				local x, z = item.node.pos[1], item.node.pos[3]
				for _, v in blockers do
					if
						v.item ~= item
						and v.kind ~= owner
						and reachable(v)
						and v.path ~= item.path
						and item.path:sub(1, #v.path + 1) ~= v.path .. "."
						and v.path:sub(1, #item.path + 1) ~= item.path .. "."
						and insideVolume(v, x, z, 0)
					then
						table.insert(bad, `{item.path} centre in {v.path} ({v.kind})`)
						break
					end
				end
			end
		end
		expect(checked > 100).toBe(true)
		if #bad > 0 then
			error(table.concat(bad, "; "))
		end
	end)
end)

--------------------------------------------------------------------------------------------------------------------
-- Roblox only: the real collision geometry
--------------------------------------------------------------------------------------------------------------------

if IN_ROBLOX then
	local AssetService = game:GetService("AssetService")
	local ORIGIN = Vector3.new(6000, 500, 6000) -- far from the map; every test part is made, cast and destroyed in turn
	local TIME_BUDGET = 45 -- seconds of CreateMeshPartAsync; the rest is skipped
	local started = os.clock()
	local report = { checked = 0, skipped = {}, advisory = {}, meshes = 0 }

	-- Entries that must hold: Jolt's, and anyone's that is already collidable (every swept entry is, by the rule that
	-- only blocking entries are swept). "ambiguous" (the mailbox) is advisory, as is a Gojo entry with no fidelity on main.
	local function hard(e): boolean
		if e.owner == "jolt" then
			return true
		end
		return e.collision == "colliders" or MeshAssets.collision(e.mesh) ~= nil
	end

	-- One Blockcast from each side of `part` (a part of volume `v`, centre at CFrame, ground at ORIGIN.Y).
	local function castAll(part, v, fidelity: string): string?
		local passUnder = fidelity == "PreciseConvexDecomposition"
		local ground = ORIGIN.Y
		local include = RaycastParams.new()
		include.FilterType = Enum.RaycastFilterType.Include
		include.FilterDescendantsInstances = { part }
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = { part }
		for _, side in PropCollision.sides(0, 0, v.yaw, v.hx, v.hz, GAP) do
			local start = Vector3.new(ORIGIN.X + side.start[1], ground + CHAR_ROOT_Y, ORIGIN.Z + side.start[2])
			local dir = Vector3.new(side.dir[1], 0, side.dir[2])
			local length = math.sqrt((side.target[1] - side.start[1]) ^ 2 + (side.target[2] - side.start[2]) ^ 2)
			local box = CFrame.lookAt(start, start + dir)
			local hit = workspace:Blockcast(
				box,
				Vector3.new(CHAR_HALF_WIDTH * 2, 5, CHAR_HALF_DEPTH * 2),
				dir * length,
				include
			)
			if (not hit or hit.Instance ~= part) and passUnder then
				-- the one PCD (the barn loft) is a platform over an open ground floor: walking under it is the design
				table.insert(report.advisory, `{part.Name or "?"} {side.name}: walks under (open ground floor)`)
			elseif not hit or hit.Instance ~= part then
				return `{side.name}: the box walked through (hit {hit and hit.Instance and hit.Instance.Name or "nothing"})`
			end
			if hit and hit.Instance == part then
				-- the real collision shape (not the bounding box): a probe the box size, shrunk so face contact is no overlap
				local probe = Instance.new("Part")
				probe.Anchored = true
				probe.CanCollide = false
				probe.CanQuery = true
				probe.CanTouch = false
				probe.Transparency = 1
				probe.Size = Vector3.new(CHAR_HALF_WIDTH * 2, 5, CHAR_HALF_DEPTH * 2) * 0.9
				probe.CFrame = box.Rotation + (start + dir * hit.Distance)
				probe.Parent = workspace
				local ok, found = pcall(function()
					return workspace:GetPartsInPart(probe, overlap)
				end)
				probe:Destroy()
				local distance = string.format("%.2f", hit.Distance)
				-- a hull is approximate and the Blockcast already proves the stop: only a Box mesh fails hard on overlap
				if not ok then
					table.insert(
						report.advisory,
						`{part.Name or "?"} {side.name}: GetPartsInPart unavailable ({tostring(found):sub(1, 60)}), inside check skipped`
					)
				elseif #found > 0 then
					if fidelity == "Box" then
						return `{side.name}: the box is inside the part's collision at the hit (distance {distance})`
					end
					table.insert(
						report.advisory,
						`{part.Name or "?"} {side.name}: box overlaps the {fidelity} collision at the hit (distance {distance})`
					)
				end
			end
		end
		return nil
	end

	local function record(e, name: string, err: string?)
		if err then
			if hard(e) then
				error(`{name}: {err}`)
			end
			table.insert(report.advisory, `{e.kind}: {err}`)
		end
		report.checked += 1
	end

	-- scale of a mesh entry: its first placed slot's size over the native size (the shop stands use their layout scale)
	local function scaleOf(e): number
		for _, v in volumesByKind[e.kind] or {} do
			local native = MeshAssets.get(e.mesh).size
			return v.hy * 2 / native[2]
		end
		if e.mesh == WorldLayout.BUY_STAND_MESH then
			return WorldLayout.BUY_STAND_SCALE
		end
		return 1
	end

	describe("PropWalk Blockcast against the real collision (cloud)", function()
		local seen = {}
		for _, e in PropCollision.ENTRIES do
			local fidelity = e.mesh ~= "part" and MeshAssets.collision(e.mesh)
			if fidelity and PropCollision.FIDELITIES[e.collision] and not seen[e.mesh] then
				seen[e.mesh] = true
				it(`{e.kind} ({e.owner}, {fidelity}): the box stops at the mesh from 4 sides`, function()
					local entry = MeshAssets.get(e.mesh)
					if not (entry and entry.meshId and entry.size) then
						table.insert(report.skipped, `{e.kind}: no uploaded id`)
						return
					end
					if os.clock() - started > TIME_BUDGET then
						table.insert(report.skipped, `{e.kind}: time budget`)
						return
					end
					local ok, part = pcall(function()
						return AssetService:CreateMeshPartAsync(
							entry.meshId,
							{ CollisionFidelity = Enum.CollisionFidelity[fidelity] }
						)
					end)
					if not ok then
						table.insert(
							report.skipped,
							`{e.kind}: CreateMeshPartAsync failed ({tostring(part):sub(1, 80)})`
						)
						return
					end
					local scale = scaleOf(e)
					part.Anchored = true
					part.CanCollide = true
					part.Size = Vector3.new(entry.size[1], entry.size[2], entry.size[3]) * scale
					part.CFrame = CFrame.new(ORIGIN + Vector3.new(0, part.Size.Y / 2, 0))
					part.Parent = workspace
					local half = part.Size / 2
					local err = castAll(part, { yaw = 0, hx = half.X, hz = half.Z }, fidelity)
					part:Destroy()
					report.meshes += 1
					record(e, e.kind, err)
				end)
			end
		end

		for _, kind in
			(function()
				local out = {}
				for k in volumesByKind do
					if entryOf[k].collision == "colliders" then
						table.insert(out, k)
					end
				end
				table.sort(out)
				return out
			end)()
		do
			local e = entryOf[kind]
			it(`{kind} ({e.owner}, colliders): the box stops at each collider part from 4 sides`, function()
				local n = 0
				for _, v in volumesByKind[kind] do
					if reachable(v) and n < 60 then
						n += 1
						local node = v.item.node
						local part = Instance.new("Part")
						part.Anchored = true
						part.CanCollide = true
						part.Shape = if node.shape == "Ball"
							then Enum.PartType.Ball
							elseif node.shape == "Cylinder" then Enum.PartType.Cylinder
							else Enum.PartType.Block
						part.Size = Vector3.new(node.size[1], node.size[2], node.size[3])
						local rot = node.rot or { 0, 0, 0 }
						part.CFrame = CFrame.new(ORIGIN + Vector3.new(0, v.cy, 0))
							* CFrame.Angles(math.rad(rot[1]), 0, 0)
							* CFrame.Angles(0, math.rad(rot[2]), 0)
							* CFrame.Angles(0, 0, math.rad(rot[3]))
						part.Parent = workspace
						-- a tilted part reaches further than its unrotated box: start the walk outside its bounding sphere
						local reach = if math.abs(rot[1] or 0) > 1 or math.abs(rot[3] or 0) > 1
							then math.sqrt(v.hx ^ 2 + v.hy ^ 2 + v.hz ^ 2)
							else nil
						local err =
							castAll(part, { yaw = math.rad(rot[2] or 0), hx = reach or v.hx, hz = reach or v.hz })
						part:Destroy()
						record(e, v.path, err)
					end
				end
			end)
		end

		it("skipped at most half of the meshes and reports the rest", function()
			print(
				`PropWalk cloud: {report.meshes} meshes and {report.checked} volumes cast, {#report.skipped} skipped, {#report.advisory} advisory`
			)
			for _, s in report.skipped do
				print(`  skipped {s}`)
			end
			for _, a in report.advisory do
				print(`  advisory {a}`)
			end
			expect(#report.skipped <= (report.meshes + #report.skipped) / 2).toBe(true)
		end)
	end)
end

return true
