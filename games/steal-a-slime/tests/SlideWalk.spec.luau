--!nocheck
-- The fountain slide blocks a walking player everywhere (Merijn, LIVE v215: "players still pass through the slide").
-- Runs in BOTH runtimes (tools/pipeline/stage-specs stages it into the cloud test place; string requires to ../src and
-- ./ only, no @lune). The mesh points are re-derived from the kit source numbers (no FBX read).
--
-- Root cause the first half pins down: the kit's ground posts (and the staves brackets) of the slime_fountain mesh had no
-- collider, so a player walked into a visible post (SlideColliders.supports now covers them), and the mouth end cap is
-- skewed against the last chord, which left its far corner outside the slab (SlideColliders.MOUTH_EXTRA).
--
-- Lune and cloud: pure geometry on SlideColliders.all (what server/FountainColliders places).
--   * a stand-in character box (2 wide, 5 tall, 1 deep) walks at 16 studs/s in 1/60 s steps into the slide from BOTH
--     sides at several points of every segment (low stretch, middle, top), at the slide's own height and, where the
--     block reaches the ground, at the ground; and into every Post / Brace from four sides. The first blocked step is
--     outside the trough, never at the ride line.
--   * every visible post / bracket point (re-derived from the kit source numbers) is inside a collider.
--   * the ride path (WorldLayout.SLIDE_PATH, the rider's centre) is in no Post / Brace; the existing floor / fill / joint
--     blocks do contain it, which is only allowed because riders are anchored and non-colliding (checked in the cloud half
--     on a real ModelFactory slime; tests/SlideColliders.spec "riding slimes are anchored and never collide" in Lune).
--
-- Cloud only: FountainColliders.place() builds the real Parts (Map.Volcano.SlideColliders); Blockcast the stand-in at the
-- walls and supports and GetPartsInPart at the stop (clear of the part), raycast along the ride path against the new
-- parts (no hit), and PhysicsService:CollisionGroupsAreCollidable for every character group against the colliders' group.
local Config = require("../src/shared/Config")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local SlideColliders = require("../src/shared/SlideColliders")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local IN_ROBLOX = pcall(function()
	return game:GetService("RunService")
end)

local STEP = 16 / 60 -- 16 studs/s at 60 Hz
local START = 12 -- the walker starts this far from the ride line
local CHAR_HALF = { 1, 2.5, 0.5 } -- 2 wide, 5 tall, 1 deep (depth along the walk)
local GROUND_ROOT = 3 -- R15 root at hip height
local PATH = WorldLayout.SLIDE_PATH
local KIT = WorldLayout.slidePath(WorldLayout.KIT_SLIDE_SAMPLES)
local SPECS = SlideColliders.all(PATH, KIT, true) -- the roof wedges sit above FILL, over a walker's head: not listed

--------------------------------------------------------------------------------------------------------------------
-- Boxes
--------------------------------------------------------------------------------------------------------------------

local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function unit(v)
	local l = math.sqrt(dot(v, v))
	return { v[1] / l, v[2] / l, v[3] / l }
end

-- The spec's box: lookAt frame (right is horizontal, up = right x forward), size = { width, height, length }.
local function obbOf(spec)
	local f = spec.forward
	local right = unit({ -f[3], 0, f[1] })
	local up = cross(right, f)
	return { c = spec.centre, axes = { right, up, f }, h = { spec.size[1] / 2, spec.size[2] / 2, spec.size[3] / 2 } }
end

local BOXES = {}
for _, spec in SPECS do
	table.insert(BOXES, { spec = spec, box = obbOf(spec) })
end

local function overlaps(a, b): boolean
	local axes = {}
	for _, x in a.axes do
		table.insert(axes, x)
	end
	for _, x in b.axes do
		table.insert(axes, x)
	end
	for _, x in a.axes do
		for _, y in b.axes do
			local c = cross(x, y)
			if dot(c, c) > 1e-9 then
				table.insert(axes, unit(c))
			end
		end
	end
	local d = { b.c[1] - a.c[1], b.c[2] - a.c[2], b.c[3] - a.c[3] }
	for _, axis in axes do
		local ra, rb = 0, 0
		for k = 1, 3 do
			ra += a.h[k] * math.abs(dot(a.axes[k], axis))
			rb += b.h[k] * math.abs(dot(b.axes[k], axis))
		end
		if math.abs(dot(d, axis)) >= ra + rb - 1e-6 then
			return false
		end
	end
	return true
end

local function pointIn(box, p, pad): boolean
	local d = { p[1] - box.c[1], p[2] - box.c[2], p[3] - box.c[3] }
	for k = 1, 3 do
		if math.abs(dot(d, box.axes[k])) > box.h[k] + pad then
			return false
		end
	end
	return true
end

local function anyBox(p, pad, kinds)
	for _, e in BOXES do
		if (kinds == nil or kinds[e.spec.kind]) and pointIn(e.box, p, pad) then
			return e
		end
	end
	return nil
end

local function walker(x, y, z, dir)
	local side = unit(cross({ 0, 1, 0 }, dir))
	return { c = { x, y, z }, axes = { side, { 0, 1, 0 }, dir }, h = CHAR_HALF }
end

local function blockedBy(box)
	for _, e in BOXES do
		if overlaps(box, e.box) then
			return e
		end
	end
	return nil
end

-- Walk from `from` along unit `dir` (horizontal) in 1/60 s steps for `length`. Returns the walked distance before the
-- first blocked step and the block, or nil when nothing blocked it.
local function walk(from, y, dir, length)
	local travelled = 0
	while travelled < length do
		local next = travelled + STEP
		local blocker = blockedBy(walker(from[1] + dir[1] * next, y, from[3] + dir[3] * next, dir))
		if blocker then
			return travelled, blocker
		end
		travelled = next
	end
	return nil, nil
end

--------------------------------------------------------------------------------------------------------------------
-- Sample points: segment fractions, both sides
--------------------------------------------------------------------------------------------------------------------

local FRACTIONS = { 0.25, 0.5, 0.75 }
local samples = {}
for i = 1, #PATH - 1 do
	local a, b = PATH[i], PATH[i + 1]
	local dir = unit({ b[1] - a[1], 0, b[3] - a[3] })
	local right = unit({ -dir[3], 0, dir[1] }) -- horizontal, across the trough
	for _, f in FRACTIONS do
		table.insert(samples, {
			segment = i,
			p = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f },
			right = right,
		})
	end
end

-- The lowest point of the block under a sample (the floor slab's underside, or the ground where a skirt fills in).
local function reachesGround(s): boolean
	return anyBox({ s.p[1], 0.5, s.p[3] }, 0, { Floor = true, Skirt = true, Joint = true }) ~= nil
end

--------------------------------------------------------------------------------------------------------------------
-- Tests (both runtimes)
--------------------------------------------------------------------------------------------------------------------

describe("the slide blocks a walking player (stand-in box at 16 studs/s)", function()
	it("is built from more than the solid block: the supports are in the live specs", function()
		local kinds = {}
		for _, spec in SPECS do
			kinds[spec.kind] = (kinds[spec.kind] or 0) + 1
		end
		expect((kinds.Post or 0) > 0).toBe(true)
		expect((kinds.Brace or 0) > 0).toBe(true)
		expect(kinds.Fill > 0 and kinds.Floor > 0 and kinds.Skirt > 0 and kinds.Joint > 0).toBe(true)
	end)

	for _, mode in { "at the slide's own height", "at the ground" } do
		it(`is stopped outside the trough walking in from both sides, {mode}, along the whole length`, function()
			local walked, skipped = 0, 0
			local top, mid, low = 0, 0, 0
			for _, s in samples do
				local ground = mode == "at the ground"
				if ground and not reachesGround(s) then
					continue -- a high stretch: nobody walks into it from the ground (it is overhead)
				end
				local y = if ground then GROUND_ROOT else s.p[2] + 3
				for _, side in { -1, 1 } do
					local dir = { -s.right[1] * side, 0, -s.right[3] * side }
					local from = { s.p[1] + s.right[1] * side * START, 0, s.p[3] + s.right[3] * side * START }
					if blockedBy(walker(from[1], y, from[3], dir)) then
						skipped += 1 -- starts inside a neighbouring coil's block: that is already solid
						continue
					end
					local distance, blocker = walk(from, y, dir, START)
					expect(blocker ~= nil).toBe(true) -- never walks through to the ride line
					-- the root is still on its own side of the ride line, outside the trough half width
					-- (a walker stopped by another coil's block, stacked under this stretch, is stopped for good too)
					if math.abs(blocker.spec.segment - s.segment) <= 1 then
						expect(START - distance >= SlideColliders.HALF_WIDTH).toBe(true)
					end
					walked += 1
					if s.p[2] > 24 then
						top += 1
					elseif s.p[2] > 8 then
						mid += 1
					else
						low += 1
					end
				end
			end
			expect(walked > 60).toBe(true)
			expect(skipped < walked).toBe(true)
			if mode == "at the slide's own height" then
				expect(top > 0 and mid > 0 and low > 0).toBe(true) -- all three stretches walked
			end
		end)
	end

	it("is stopped at every ground post and every staves bracket from four sides", function()
		local checked = 0
		for _, e in BOXES do
			local kind = e.spec.kind
			if kind ~= "Post" and kind ~= "Brace" then
				continue
			end
			local c = e.box.c
			local y = if kind == "Post" then GROUND_ROOT else c[2]
			for _, axisIndex in { 1, 3 } do
				for _, sign in { -1, 1 } do
					local axis = e.box.axes[axisIndex]
					local dir = unit({ -axis[1] * sign, 0, -axis[3] * sign })
					local from = { c[1] + axis[1] * sign * START, 0, c[3] + axis[3] * sign * START }
					if blockedBy(walker(from[1], y, from[3], dir)) then
						continue -- starts inside the slide block
					end
					local distance, blocker = walk(from, y, dir, START)
					expect(blocker ~= nil).toBe(true)
					-- the walker's root stops outside the post's own footprint
					local px, pz = from[1] + dir[1] * distance - c[1], from[3] + dir[3] * distance - c[3]
					local inside = true
					for _, k in { 1, 3 } do
						inside = inside and math.abs(px * e.box.axes[k][1] + pz * e.box.axes[k][3]) < e.box.h[k]
					end
					expect(inside).toBe(false)
					checked += 1
				end
			end
		end
		expect(checked >= 8).toBe(true)
	end)
end)

-- The kit (models/slime_fountain.py supports()) numbers, re-derived here from the ride line sampled like the mesh.
local function kitSupportPoints()
	local out = {}
	local n = #KIT
	local last = -99
	for k = 1, n do
		local i = k - 1
		if i - last < 6 or i < 5 then
			continue
		end
		last = i
		local p, a, b = KIT[k], KIT[math.max(k - 1, 1)], KIT[math.min(k + 1, n)]
		local t = unit({ b[1] - a[1], b[2] - a[2], b[3] - a[3] })
		local lat = unit({ -t[3], 0, t[1] })
		local up = cross(lat, t)
		local under = { p[1] - 0.7 * up[1], p[2] - 0.7 * up[2], p[3] - 0.7 * up[3] }
		if under[2] <= 9 then
			for _, side in { -1, 1 } do
				local qx, qy, qz =
					under[1] + lat[1] * side * 2.3, under[2] + lat[2] * side * 2.3, under[3] + lat[3] * side * 2.3
				local h = qy + 0.2
				for step = 0, 5 do
					for corner = 0, 5 do -- a 6-sided post, circumradius 0.6
						local ang = corner * math.pi / 3
						table.insert(
							out,
							{ { qx + 0.6 * math.cos(ang), h * step / 5, qz + 0.6 * math.sin(ang) }, `post{i}` }
						)
					end
				end
			end
		else
			local zb = under[2] - 0.45
			local r = math.sqrt(under[1] ^ 2 + under[3] ^ 2)
			local r0 = 11.2 + 0.5 * math.sin(math.pi * math.clamp((zb - 2.4) / 27.6, 0, 1)) - 0.3
			local dx, dz = under[1] / r, under[3] / r
			-- beam: 0.9 square from the staves to 0.8 past the trough centre
			for s = 0, 8 do
				local rr = r0 + (r + 0.8 - r0) * s / 8
				for _, ly in { -0.45, 0.45 } do
					for _, lz in { -0.45, 0.45 } do
						table.insert(out, { { dx * rr - dz * lz, zb + ly, dz * rr + dx * lz }, `beam{i}` })
					end
				end
			end
			-- strut: foot at the staves 4.5 under the beam, up to the trough underside
			for s = 0, 8 do
				local f = s / 8
				local rr = r0 + (r - 0.5 - r0) * f
				table.insert(out, { { dx * rr, zb - 4.5 + 4.3 * f, dz * rr }, `strut{i}` })
			end
		end
	end
	return out
end

describe("every visible post and bracket of the mesh is inside a collider", function()
	it("covers each kit support point (silo wall points are the silo collider's)", function()
		local points = kitSupportPoints()
		expect(#points > 100).toBe(true)
		local posts, braces = 0, 0
		for _, entry in points do
			local p, label = entry[1], entry[2]
			local rr = math.sqrt(p[1] ^ 2 + p[3] ^ 2)
			local wall = 11.2 + 0.5 * math.sin(math.pi * math.clamp((p[2] - 2.4) / 27.6, 0, 1))
			if rr <= wall + 0.2 then
				continue -- inside the staves (the SiloCollider)
			end
			if anyBox(p, 0.05) == nil then
				error(`{label} point ({p[1]}, {p[2]}, {p[3]}) is in no collider`)
			end
			if string.sub(label, 1, 4) == "post" then
				posts += 1
			else
				braces += 1
			end
		end
		expect(posts > 20 and braces > 20).toBe(true)
	end)

	it("keeps the supports' own boxes tight: a brace hangs only 5 studs, a post is 1.3 wide", function()
		for _, spec in SPECS do
			if spec.kind == "Post" then
				expect(spec.size[1]).toBe(SlideColliders.POST_WIDTH)
				expect(spec.centre[2] - spec.size[2] / 2).toBe(0) -- from the ground
			elseif spec.kind == "Brace" then
				expect(spec.size[2] < 5.5).toBe(true)
				expect(spec.size[3] < 6).toBe(true)
			end
		end
	end)
end)

describe("the ride path is clear of the new colliders", function()
	local function ridePoints()
		local out = {}
		for i = 1, #PATH - 1 do
			local a, b = PATH[i], PATH[i + 1]
			local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
			local n = math.ceil(length / 0.25)
			for s = 0, n do
				local f = s / n
				for _, lift in { 0, 0.5, 1.5 } do -- the rider's centre rides a little above the ride line
					table.insert(
						out,
						{ a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f + lift, a[3] + (b[3] - a[3]) * f }
					)
				end
			end
		end
		return out
	end

	it("passes through no Post and no Brace, only through the floor / fill / joint block it rides in", function()
		local inside = {}
		for _, p in ridePoints() do
			local e = anyBox(p, 0)
			if e then
				inside[e.spec.kind] = true
				expect(e.spec.kind == "Post" or e.spec.kind == "Brace").toBe(false)
			end
		end
		-- the ride line is inside the slide block by design: that holds because riders never collide (FountainRide)
		expect(inside.Floor or inside.Fill or inside.Joint).toBe(true)
		for kind in inside do
			expect(kind == "Floor" or kind == "Fill" or kind == "Joint" or kind == "Skirt").toBe(true)
		end
	end)
end)

--------------------------------------------------------------------------------------------------------------------
-- Cloud only: the real Parts
--------------------------------------------------------------------------------------------------------------------

if IN_ROBLOX then
	local PhysicsService = game:GetService("PhysicsService")
	local FountainColliders = require("../src/server/FountainColliders")
	local ModelFactory = require("../src/visuals/shared/ModelFactory")
	local Fixtures = require("./Fixtures")

	local temp: Instance? = nil -- a Map / Volcano made here when the cloud place has none
	local made = false -- the SlideColliders folder was made here (not by a booted server)
	local function colliderFolder(): Folder
		if not workspace:FindFirstChild("Map") then
			local map = Instance.new("Model")
			map.Name = "Map"
			map.Parent = workspace
			temp = map
		end
		local map = workspace.Map
		if not map:FindFirstChild("Volcano") then
			local volcano = Instance.new("Model")
			volcano.Name = "Volcano"
			volcano.Parent = map
			if temp == nil then
				temp = volcano
			end
		end
		made = map.Volcano:FindFirstChild(SlideColliders.FOLDER) == nil
		local folder = FountainColliders.place()
		assert(folder, "FountainColliders.place returned nil")
		return folder
	end

	local function overlapOf(folder)
		local p = OverlapParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		p.FilterDescendantsInstances = { folder }
		return p
	end

	local function rayOf(folder, onlyNew)
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		local list = { folder }
		if onlyNew then
			list = {}
			for _, part in folder:GetChildren() do
				local kind = part:GetAttribute(FountainColliders.ATTRIBUTE)
				if kind == "Post" or kind == "Brace" then
					table.insert(list, part)
				end
			end
		end
		p.FilterDescendantsInstances = list
		return p
	end

	-- Blockcast the stand-in from `from` along `dir` (horizontal unit table) for START studs at root height y.
	local function cast(folder, from, y, dir)
		local start = Vector3.new(from[1], y, from[3])
		local d = Vector3.new(dir[1], 0, dir[3])
		return start,
			d,
			workspace:Blockcast(CFrame.lookAt(start, start + d), Vector3.new(2, 5, 1), d * START, rayOf(folder))
	end

	-- Set of the folder's parts that a probe box at `cf` overlaps.
	local function partsAt(cf, size, overlap)
		local probe = Instance.new("Part")
		probe.Anchored, probe.CanCollide, probe.CanQuery, probe.Transparency = true, false, false, 1
		probe.Size = size
		probe.CFrame = cf
		probe.Parent = workspace
		local set = {}
		for _, part in workspace:GetPartsInPart(probe, overlap) do
			set[part] = true
		end
		probe:Destroy()
		return set
	end

	describe("the slide blocks the stand-in against the real colliders (cloud)", function()
		local folder
		local function get()
			if not folder then
				folder = colliderFolder()
			end
			return folder
		end

		it("holds every spec as a solid anchored Part in the default collision group", function()
			local f = get()
			local fills = 0
			for _, spec in SPECS do
				if spec.kind == "Fill" then
					fills += 1
				end
			end
			-- the live flag decides; with SlideCollision on this is the full set
			if Config.FEATURES.SlideCollision then
				expect(#f:GetChildren()).toBe(#SPECS + 2 * fills)
			end
			for _, part in f:GetChildren() do
				expect(part.Anchored and part.CanCollide).toBe(true)
				expect(part.CollisionGroup).toBe("Default")
				-- only MeshPart / UnionOperation have CollisionFidelity; the slide colliders are plain Parts and WedgeParts
				if part:IsA("MeshPart") or part:IsA("UnionOperation") then
					expect(part.CollisionFidelity ~= Enum.CollisionFidelity.PreciseConvexDecomposition).toBe(true)
				end
			end
		end)

		it("Blockcast: walking in from both sides at every sample stops the box outside the part", function()
			local f = get()
			local overlap = overlapOf(f)
			local checked = 0
			for _, s in samples do
				for _, side in { -1, 1 } do
					local y = s.p[2] + 3
					local dir = { -s.right[1] * side, 0, -s.right[3] * side }
					local from = { s.p[1] + s.right[1] * side * START, 0, s.p[3] + s.right[3] * side * START }
					local start, d, hit = cast(f, from, y, dir)
					-- Blockcast ignores a part the box already overlaps at the start (a neighbouring coil's fill, as the Lune half
					-- skips): such a walker begins inside solid, so the stop may overlap exactly those parts and no others
					local startParts = partsAt(CFrame.lookAt(start, start + d), Vector3.new(2, 5, 1), overlap)
					if not hit then
						-- only allowed when it starts inside a neighbouring coil
						if next(startParts) == nil then
							error(`segment {s.segment} side {side}: the box walked through the slide`)
						end
						continue
					end
					expect(START - hit.Distance >= SlideColliders.HALF_WIDTH).toBe(true)
					-- shrunk probe: face contact is no overlap
					local stop = start + d * hit.Distance
					local extra = 0
					for part in partsAt(CFrame.lookAt(stop, stop + d), Vector3.new(2, 5, 1) * 0.9, overlap) do
						if not startParts[part] then
							extra += 1
						end
					end
					expect(extra).toBe(0)
					checked += 1
				end
			end
			expect(checked > 60).toBe(true)
		end)

		it("Blockcast: every Post and Brace stops the box from four sides", function()
			local f = get()
			local seen = 0
			for _, e in BOXES do
				local kind = e.spec.kind
				if kind ~= "Post" and kind ~= "Brace" then
					continue
				end
				local c = e.box.c
				local y = if kind == "Post" then GROUND_ROOT else c[2]
				for _, axisIndex in { 1, 3 } do
					for _, sign in { -1, 1 } do
						local axis = e.box.axes[axisIndex]
						local dir = unit({ -axis[1] * sign, 0, -axis[3] * sign })
						local from = { c[1] + axis[1] * sign * START, 0, c[3] + axis[3] * sign * START }
						local start, d, hit = cast(f, from, y, dir)
						-- a hit on any collider counts: the slab can sit between the stand-in and the post. Blockcast ignores
						-- parts the box starts inside, so a start inside the slide block (the mouth's fills) is solid already
						-- (the Lune half skips it too)
						if
							hit == nil
							and next(partsAt(CFrame.lookAt(start, start + d), Vector3.new(2, 5, 1), overlapOf(f)))
						then
							continue
						end
						expect(hit ~= nil).toBe(true)
						seen += 1
					end
				end
			end
			expect(seen >= 8).toBe(true)
		end)

		it(
			"the ride path hits no Post and no Brace (raycast along every segment, lifted to the rider's centre)",
			function()
				local f = get()
				local params = rayOf(f, true)
				local rider = {}
				for i = 1, #PATH - 1 do
					local a, b = PATH[i], PATH[i + 1]
					for _, lift in { 0, 0.5, 1.5 } do
						local from = Vector3.new(a[1], a[2] + lift, a[3])
						local delta = Vector3.new(b[1] - a[1], b[2] - a[2], b[3] - a[3])
						local hit = workspace:Raycast(from, delta, params)
						if hit then
							table.insert(rider, `segment {i} lift {lift}: {hit.Instance.Name}`)
						end
					end
				end
				expect(#rider).toBe(0)
			end
		)

		it("riders pass the block because they are anchored and non-colliding (a real ModelFactory slime)", function()
			local model = ModelFactory.build(Fixtures.slime("slidewalk", 1))
			expect(model.PrimaryPart.Anchored).toBe(true)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					expect(d.CanCollide).toBe(false)
				end
			end
			model:Destroy()
		end)

		it("every character collision group collides with the colliders' group", function()
			local f = get()
			local group = f:GetChildren()[1].CollisionGroup
			local names = { "Default", PlotLockGuard.LEAVER_GROUP }
			for index = 1, Config.PLOT_COUNT do
				table.insert(names, PlotLockGuard.ownerGroup(index))
			end
			local registered = 0
			for _, name in names do
				local ok, collidable = pcall(function()
					return PhysicsService:CollisionGroupsAreCollidable(name, group)
				end)
				if ok then
					registered += 1
					expect(collidable).toBe(true)
				end
			end
			expect(registered >= 1).toBe(true) -- Default always exists
		end)

		-- FEATURES.SlidePCD: the slide mesh made as MeshSwap makes it (PreciseConvexDecomposition, slot fit + offset + IMPORT_YAW).
		-- Probe numbers: pipeline/probes/slidepcd/pcd-final.json (published place v224).
		describe("the PCD slide mesh alone (cloud)", function()
			local slide
			local function getSlide()
				if slide then
					return slide
				end
				local MeshAssets = require("../src/shared/MeshAssets")
				local node
				local function find(nodes)
					for _, n in nodes do
						if n.name == "FountainMesh" then
							node = n
						end
						if n.children then
							find(n.children)
						end
					end
				end
				find(WorldLayout.build())
				local entry = MeshAssets.get("fountain_split_slide")
				slide = game:GetService("AssetService"):CreateMeshPartAsync(MeshAssets.meshId("fountain_split_slide"), {
					RenderFidelity = Enum.RenderFidelity.Precise,
					CollisionFidelity = Enum.CollisionFidelity[MeshAssets.collision("fountain_split_slide")],
				})
				local _, k, below = MeshAssets.fit("slime_fountain", node.size)
				slide.Size = Vector3.new(entry.size[1] * k, entry.size[2] * k, entry.size[3] * k)
				slide.CFrame = CFrame.new(node.pos[1], node.pos[2], node.pos[3])
					* CFrame.new(0, -below, 0)
					* CFrame.new(entry.offset[1] * k, entry.offset[2] * k, entry.offset[3] * k)
					* CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
				slide.Anchored = true
				slide.CanCollide = true
				slide.CanQuery = true -- the casts need it; physics collision does not
				slide.Parent = workspace
				return slide
			end
			local function params()
				local p = RaycastParams.new()
				p.FilterType = Enum.RaycastFilterType.Include
				p.FilterDescendantsInstances = { getSlide() }
				return p
			end

			it("is made with PreciseConvexDecomposition", function()
				expect(getSlide().CollisionFidelity).toBe(Enum.CollisionFidelity.PreciseConvexDecomposition)
			end)

			it("Blockcast: the trough walls stop the box from both sides at every ride sample", function()
				local rp = params()
				local blocked = 0
				for i = 3, #KIT - 2 do
					local p, a, b = KIT[i], KIT[i - 1], KIT[i + 1]
					local t = unit({ b[1] - a[1], 0, b[3] - a[3] })
					local right = { -t[3], 0, t[1] }
					for _, side in { -1, 1 } do
						local start = Vector3.new(
							p[1] + right[1] * side * START,
							p[2] + GROUND_ROOT,
							p[3] + right[3] * side * START
						)
						local dir = Vector3.new(-right[1] * side, 0, -right[3] * side)
						local hit = workspace:Blockcast(
							CFrame.lookAt(start, start + dir),
							Vector3.new(2, 5, 1),
							dir * START,
							rp
						)
						expect(hit ~= nil).toBe(true)
						blocked += 1
					end
				end
				expect(blocked > 100).toBe(true)
			end)

			it("Blockcast: every Post and Brace the boxes stood in for is solid in the mesh from four sides", function()
				local rp = params()
				local seen = 0
				for _, e in BOXES do
					local kind = e.spec.kind
					if kind ~= "Post" and kind ~= "Brace" then
						continue
					end
					local c = e.box.c
					local y = if kind == "Post" then GROUND_ROOT else c[2]
					for _, axisIndex in { 1, 3 } do
						for _, sign in { -1, 1 } do
							local axis = e.box.axes[axisIndex]
							local start = Vector3.new(c[1] + axis[1] * sign * START, y, c[3] + axis[3] * sign * START)
							local dir = Vector3.new(-axis[1] * sign, 0, -axis[3] * sign)
							local hit = workspace:Blockcast(
								CFrame.lookAt(start, start + dir),
								Vector3.new(2, 5, 1),
								dir * START,
								rp
							)
							expect(hit ~= nil).toBe(true)
							seen += 1
						end
					end
				end
				expect(seen >= 8).toBe(true)
			end)

			it(
				"the trough floor is a gentle ramp (why the Fill block stays): no ride segment is steeper than 20 degrees",
				function()
					for i = 2, #KIT - 1 do
						local a, b = KIT[i - 1], KIT[i + 1]
						local flat = math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
						expect(math.deg(math.atan2(math.abs(b[2] - a[2]), flat)) < 20).toBe(true) -- Humanoid.MaxSlopeAngle is 89
					end
				end
			)

			it("cleans up the mesh", function()
				if slide then
					slide:Destroy()
					slide = nil
				end
			end)
		end)

		it("cleans up what it made", function()
			if temp then
				temp:Destroy()
				temp = nil
			elseif folder and made then
				folder:Destroy()
			end
			folder = nil
		end)
	end)
end
