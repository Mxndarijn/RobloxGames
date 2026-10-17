--!nocheck
-- Fountain slide collision (TODO 13; Merijn #9: players walked up the slide and stood inside the
-- trough). The silo keeps its Basin / Trim / Silo colliders (FountainCollider.spec); the slide, which
-- the visual-only mesh leaves open, gets SlideColliders: per segment a floor slab with a solid fill on
-- top, from the head to the mouth, on in every mesh state. Checked here: no point of the trough is
-- open to a player (nothing hollow, nothing standable, the top out of a jump), no gap at any join or
-- bend, the low stretch blocks a walker from the ground, and in the real server (fake runtime, mesh
-- loaded and failed) the Parts exist, are solid, invisible and anchored, survive the MeshSwap switch,
-- and the riding slimes (anchored, never colliding) pass through the block.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local FountainRide = require("../src/shared/FountainRide")
local Runtime = require("../tools/livetest/Runtime")
local SlideColliders = require("../src/shared/SlideColliders")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PATH = WorldLayout.SLIDE_PATH
local Config = require("../src/shared/Config")
local SPECS = SlideColliders.build(PATH, true)
local EPS = 1e-3
local PLAYER_HEIGHT = 5 -- R15 character, feet to head
local JUMP_REACH = 7.5 -- a default Roblox jump clears ~7.2 studs; stay above it

local function sub(a, b)
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function dot(a, b): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function normalize(v)
	local len = math.sqrt(dot(v, v))
	return { v[1] / len, v[2] / len, v[3] / len }
end

-- lookAt frame of a spec (same maths as CFrame.lookAt, no roll).
local function frame(spec)
	local f = spec.forward
	local right = normalize({ -f[3], 0, f[1] })
	local up =
		{ right[2] * f[3] - right[3] * f[2], right[3] * f[1] - right[1] * f[3], right[1] * f[2] - right[2] * f[1] }
	return right, up, f
end

-- How deep p is inside the spec box (> 0 inside, <= 0 outside or on it).
local function depth(spec, p): number
	local right, up, f = frame(spec)
	local d = sub(p, spec.centre)
	local s = spec.size
	return math.min(s[1] / 2 - math.abs(dot(d, right)), s[2] / 2 - math.abs(dot(d, up)), s[3] / 2 - math.abs(dot(d, f)))
end

local function insideAny(p): (boolean, string?)
	for _, spec in SPECS do
		if depth(spec, p) > 0.05 then
			return true, spec.name
		end
	end
	return false, nil
end

local function byName(): { [string]: any }
	local out = {}
	for _, spec in SPECS do
		out[spec.name] = spec
	end
	return out
end

local function along(i: number, k: number)
	local a, b = PATH[i], PATH[i + 1]
	return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

local LOW = {}
for i = 1, #PATH - 1 do
	if SlideColliders.isLow(PATH[i], PATH[i + 1]) then
		table.insert(LOW, i)
	end
end

describe("SlideColliders specs", function()
	it("cover every slide segment (floor + fill), top to mouth, and nothing else but skirts and joints", function()
		local names = byName()
		expect(#LOW >= 10).toBe(true)
		expect(PATH[1][2] > SlideColliders.WALK_UNDER * 4).toBe(true) -- the top really is high
		for i = 1, #PATH - 1 do
			expect(names[`SlideFloor{i}`] ~= nil).toBe(true)
			expect(names[`SlideFill{i}`] ~= nil).toBe(true)
		end
		for _, spec in SPECS do
			expect(spec.segment >= 1 and spec.segment <= #PATH - 1).toBe(true)
			expect(spec.kind == "Floor" or spec.kind == "Fill" or spec.kind == "Skirt" or spec.kind == "Joint").toBe(
				true
			)
		end
	end)
	it("flag off keeps the old low-only stretch", function()
		for _, spec in SlideColliders.build(PATH) do
			expect(SlideColliders.isLow(PATH[spec.segment], PATH[spec.segment + 1])).toBe(true)
		end
		expect(#SlideColliders.build(PATH) < #SPECS).toBe(true)
		expect(Config.FEATURES.SlideCollision).toBe(true)
	end)
	it("put the floor top exactly on the ride line, the fill straight on top of it", function()
		local names = byName()
		for i = 1, #PATH - 1 do
			for _, k in { 0.1, 0.5, 0.9 } do
				local p = along(i, k)
				expect(depth(names[`SlideFloor{i}`], p)).toBeCloseTo(0, EPS)
				expect(depth(names[`SlideFloor{i}`], { p[1], p[2] - 0.2, p[3] }) > 0).toBe(true)
				expect(depth(names[`SlideFill{i}`], { p[1], p[2] + 0.2, p[3] }) > 0).toBe(true)
			end
		end
	end)
	it("block a walking player: nothing on the low slide is walk-through from the ground up", function()
		for _, i in LOW do
			local a, b = PATH[i], PATH[i + 1]
			if math.min(a[2], b[2]) > PLAYER_HEIGHT then
				continue
			end
			for _, k in { 0.25, 0.5, 0.75 } do
				local p = along(i, k)
				-- every height a player's body crosses below the ride line
				local y = 0.1
				while y < p[2] - 0.1 do
					expect((insideAny({ p[1], y, p[3] }))).toBe(true)
					y += 0.25
				end
			end
		end
	end)
	it("give every low segment too low to walk under a skirt from the ground to its trough bottom", function()
		local names = byName()
		for _, i in LOW do
			local a, b = PATH[i], PATH[i + 1]
			local bottom = math.min(a[2], b[2]) - SlideColliders.FLOOR
			local skirt = names[`SlideSkirt{i}`]
			if bottom > 0.05 and bottom <= SlideColliders.WALK_UNDER then
				-- (a skirt the segment's own floor slab holds whole is not spawned: see "merged colliders")
				local raw = nil
				for _, spec in SlideColliders.buildRaw(PATH, true) do
					if spec.name == `SlideSkirt{i}` then
						raw = spec
					end
				end
				expect(raw ~= nil).toBe(true)
				expect(raw.forward[2]).toBe(0)
				expect(raw.centre[2] - raw.size[2] / 2).toBeCloseTo(0, EPS)
				expect(raw.centre[2] + raw.size[2] / 2).toBeCloseTo(bottom, EPS)
				if skirt == nil then
					expect(SlideColliders.contains(names[`SlideFloor{i}`], raw)).toBe(true)
				end
			else
				expect(skirt).toBe(nil)
			end
		end
	end)
end)

-- Merijn #9: nobody walks on or in the slide.
describe("the slide is solid: players cannot enter, climb or stand on it", function()
	local WIDTHS = { -1, -0.5, 0, 0.5, 1 }
	it("is solid across the whole trough, from just under the ride line up to the fill top, at every k", function()
		local names = byName()
		for i = 1, #PATH - 1 do
			local right, up = frame(names[`SlideFloor{i}`])
			local half = SlideColliders.HALF_WIDTH
			for _, k in { 0.1, 0.25, 0.5, 0.75, 0.9 } do
				local p = along(i, k)
				for _, w in WIDTHS do
					-- a column along the segment's own up axis, from just under the ride line to near the fill top
					local h = -0.2
					while h < SlideColliders.FILL * 0.9 do
						local q = {
							p[1] + right[1] * w * half + up[1] * h,
							p[2] + right[2] * w * half + up[2] * h,
							p[3] + right[3] * w * half + up[3] * h,
						}
						if not insideAny(q) then
							error(`open space in the slide: segment {i} k={k} width {w} height {h}`)
						end
						h += 0.5
					end
				end
			end
		end
	end)
	it("is unbroken at every join, bends included, from the trough floor to the fill top", function()
		for i = 1, #PATH - 2 do
			local j = PATH[i + 1]
			local y = j[2] - 0.2
			while y < j[2] + SlideColliders.FILL * 0.9 do
				if not insideAny({ j[1], y, j[3] }) then
					error(`open space at join {i} height {y - j[2]}`)
				end
				y += 0.5
			end
		end
	end)
	it("tops out beyond a jump: the highest solid point over the centreline is above JUMP_REACH", function()
		local names = byName()
		for i = 1, #PATH - 1 do
			local p = along(i, 0.5)
			local fill = names[`SlideFill{i}`]
			-- fill centre lift above the ride line plus half its height, along the segment's up axis
			local _, up = frame(fill)
			local top = dot(sub(fill.centre, p), up) + fill.size[2] / 2
			expect(top >= JUMP_REACH + 2).toBe(true)
		end
	end)
	it("has no hollow: no spec is a hollow tube, a wall or a ceiling (the old tube let players walk in it)", function()
		for _, spec in SPECS do
			expect(spec.kind ~= "Wall" and spec.kind ~= "Ceiling").toBe(true)
		end
	end)
	it("slabs are thick enough for a falling player, nothing is a thin sheet", function()
		for _, spec in SPECS do
			if spec.kind == "Floor" then
				expect(spec.size[2] >= SlideColliders.MIN_THICK).toBe(true)
			elseif spec.kind == "Fill" then
				expect(spec.size[2] >= JUMP_REACH + 2).toBe(true)
			end
		end
	end)
	it("a player dropped from above lands on top of the solid, never inside it", function()
		for i = 1, #PATH - 1 do
			local p = along(i, 0.5)
			local y = p[2] + 40
			local landedIn = nil
			while y > p[2] - 10 do
				if insideAny({ p[1], y, p[3] }) then
					landedIn = y
					break
				end
				y -= 0.25
			end
			expect(landedIn ~= nil).toBe(true)
			-- first contact is the top face of the fill, FILL above the ride line, not the floor
			expect(landedIn >= p[2] + SlideColliders.FILL - 1).toBe(true)
		end
	end)
	it("stays out of FountainRide's way: the ride points are meant to pass through (anchored, no collision)", function()
		local ride = FountainRide.new(PATH, { PATH[#PATH][1], 0.15, PATH[#PATH][3] })
		expect(#ride.points > 0).toBe(true)
	end)
end)

-- The real server, mesh loaded and failed.
local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-slidecol-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", placePath })
assert(built.ok, `rojo build failed: {built.stderr}`)

local function boot(loaded: boolean)
	local rt = Runtime.new(placePath, {
		createMeshPart = function(meshId, _options)
			if loaded then
				return roblox.Instance.new("MeshPart")
			end
			error(`livetest: CreateMeshPartAsync({meshId}) failed`)
		end,
	})
	rt:boot()
	local rides = {}
	for _ = 1, 25 * 30 do
		rt:step(1 / 30)
		local folder = rt.workspace:FindFirstChild("WildSlimes")
		for _, model in (if folder then folder:GetChildren() else {}) do
			local solid = false
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then
					solid = true
				end
			end
			local p = model:GetPivot().Position
			table.insert(rides, { p = p, solid = solid, anchored = model.PrimaryPart.Anchored })
		end
	end
	return rt, rides
end
local loadedRt, loadedRides = boot(true)
local failedRt, failedRides = boot(false)
require("@lune/fs").removeFile(placePath)

local function folderOf(rt)
	return rt.workspace.Map.Volcano:FindFirstChild(SlideColliders.FOLDER)
end

describe("SlideColliders in the live server", function()
	for _, case in { { "mesh loaded", loadedRt }, { "mesh failed", failedRt } } do
		local state, rt = case[1], case[2]
		it(`{state}: Map.Volcano.SlideColliders holds every spec as an invisible, solid, anchored Part`, function()
			expect(#rt.errors).toBe(0)
			local folder = folderOf(rt)
			expect(folder ~= nil).toBe(true)
			local parts = folder:GetChildren()
			local fillCount = 0
			for _, spec in SPECS do
				if spec.kind == "Fill" then
					fillCount += 1
				end
			end
			expect(#parts).toBe(#SPECS + 2 * fillCount) -- every Fill is the box plus two roof wedges (bug #9)
			local names = byName()
			for _, part in parts do
				local spec = names[part.Name]
				if spec == nil and part:IsA("WedgePart") then
					spec = names[string.sub(part.Name, 1, -2)] -- SlideFill<i>L / R
					expect(spec ~= nil and spec.kind == "Fill").toBe(true)
					expect(part.CustomPhysicalProperties.Friction).toBe(0)
					expect(part.Anchored and part.CanCollide and not part.CanQuery and part.Transparency == 1).toBe(
						true
					)
					continue
				end
				expect(spec ~= nil).toBe(true)
				expect(part.Anchored).toBe(true)
				expect(part.CanCollide).toBe(true)
				expect(part.CanQuery).toBe(false)
				expect(part.CanTouch).toBe(false)
				expect(part.Transparency).toBe(1)
				expect(part:GetAttribute("FountainCollider")).toBe(spec.kind)
				local c = part.CFrame.Position
				expect((c - roblox.Vector3.new(spec.centre[1], spec.centre[2], spec.centre[3])).Magnitude < EPS).toBe(
					true
				)
				local look = part.CFrame.LookVector
				expect(look:Dot(roblox.Vector3.new(spec.forward[1], spec.forward[2], spec.forward[3])) > 1 - EPS).toBe(
					true
				)
				expect(math.abs(part.Size.X - spec.size[1]) < EPS).toBe(true)
				expect(math.abs(part.Size.Y - spec.size[2]) < EPS).toBe(true)
				expect(math.abs(part.Size.Z - spec.size[3]) < EPS).toBe(true)
			end
		end)
		it(`{state}: riding slimes are anchored and never collide (they pass through the solid slide)`, function()
			local rides = if state == "mesh loaded" then loadedRides else failedRides
			expect(#rides > 100).toBe(true)
			for _, r in rides do
				expect(r.solid).toBe(false)
				expect(r.anchored).toBe(true)
			end
		end)
	end
	it("the MeshSwap switch leaves the slide colliders on (both directions)", function()
		local rt = loadedRt
		local MeshSwap = rt:require(rt.game:GetService("ServerScriptService").Server.MeshSwap)
		for _, loaded in { false, true } do
			MeshSwap.setMeshCollision(rt.workspace.Map, "slime_fountain", loaded)
			for _, part in folderOf(rt):GetChildren() do
				expect(part.CanCollide).toBe(true)
			end
		end
		expect(rt.workspace.Map.Volcano.SiloCollider.CanCollide).toBe(true)
	end)
	it("the silo blocks players once the mesh is in (Basin / Trim / Silo on), stand-ins when it failed", function()
		for _, name in { "BasinCollider", "TrimCollider", "SiloCollider" } do
			expect(loadedRt.workspace.Map.Volcano[name].CanCollide).toBe(true)
			expect(failedRt.workspace.Map.Volcano[name].CanCollide).toBe(false)
		end
		for _, name in { "Rock1", "BasinRim", "Column" } do
			expect(failedRt.workspace.Map.Volcano[name].CanCollide).toBe(true)
		end
	end)
end)

-- Part-count cut: the colliders that other colliders hold whole are not spawned. The segment boxes lie
-- along a spiral (no two are coplanar), so containment is the only exact merge.
describe("merged slide colliders keep the collision envelope exactly", function()
	local RAW = SlideColliders.buildRaw(PATH, true)
	local STEP = 0.1
	local function inside(specs, p)
		for _, spec in specs do
			if depth(spec, p) >= -1e-6 then
				return true
			end
		end
		return false
	end
	it("drop only skirts, and fewer Parts than before", function()
		expect(#SPECS < #RAW).toBe(true)
		local kept = {}
		for _, spec in SPECS do
			kept[spec.name] = spec
		end
		for _, spec in RAW do
			if kept[spec.name] == nil then
				expect(spec.kind).toBe("Skirt")
			else
				expect(kept[spec.name].kind).toBe(spec.kind) -- kept specs are untouched (values checked below)
			end
		end
	end)
	it("keep every kept Part's properties (kind, segment, forward, size) as built", function()
		local byRaw = {}
		for _, spec in RAW do
			byRaw[spec.name] = spec
		end
		for _, spec in SPECS do
			local raw = byRaw[spec.name]
			expect(spec.kind).toBe(raw.kind)
			expect(spec.segment).toBe(raw.segment)
			for k = 1, 3 do
				expect(spec.centre[k]).toBe(raw.centre[k])
				expect(spec.size[k]).toBe(raw.size[k])
				expect(spec.forward[k]).toBe(raw.forward[k])
			end
		end
	end)
	it("fill the same volume: every sampled point is solid after exactly when it was before", function()
		-- every dropped box sampled on a 0.1 grid, plus a ring of points just outside it (nothing may be added either)
		local kept = {}
		for _, spec in SPECS do
			kept[spec.name] = true
		end
		local checked = 0
		for _, spec in RAW do
			if not kept[spec.name] then
				local right, up, f = frame(spec)
				local nx, ny, nz =
					math.ceil(spec.size[1] / STEP), math.ceil(spec.size[2] / STEP), math.ceil(spec.size[3] / STEP)
				for a = 0, nx do
					for b = 0, ny do
						for c = 0, nz do
							local x, y, z =
								(a / nx - 0.5) * spec.size[1],
								(b / ny - 0.5) * spec.size[2],
								(c / nz - 0.5) * spec.size[3]
							local p = {
								spec.centre[1] + right[1] * x + up[1] * y + f[1] * z,
								spec.centre[2] + right[2] * x + up[2] * y + f[2] * z,
								spec.centre[3] + right[3] * x + up[3] * y + f[3] * z,
							}
							expect(inside(SPECS, p)).toBe(true)
							checked += 1
						end
					end
				end
			end
		end
		expect(checked > 0).toBe(true)
		-- and on a grid over the neighbourhood of the dropped boxes, both sets agree point by point
		local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
		for _, spec in RAW do
			if not kept[spec.name] then
				for k = 1, 3 do
					lo[k] = math.min(lo[k], spec.centre[k] - spec.size[3] / 2 - 3)
					hi[k] = math.max(hi[k], spec.centre[k] + spec.size[3] / 2 + 3)
				end
			end
		end
		lo[2] = -1
		local x = lo[1]
		while x <= hi[1] do
			local z = lo[3]
			while z <= hi[3] do
				local y = lo[2]
				while y <= hi[2] do
					local p = { x, y, z }
					expect(inside(SPECS, p)).toBe(inside(RAW, p))
					y += 0.7
				end
				z += 0.7
			end
			x += 0.7
		end
	end)
	it("keep the slide surface: the floor top height along the path is the ride line, before and after", function()
		for i = 1, #PATH - 1 do
			for _, k in { 0.1, 0.3, 0.5, 0.7, 0.9 } do
				local p = along(i, k)
				-- solid under the ride line, before and after the merge (the fill above it is checked above)
				for _, set in { RAW, SPECS } do
					expect(inside(set, { p[1], p[2] - 0.05, p[3] })).toBe(true)
				end
			end
		end
	end)
end)
