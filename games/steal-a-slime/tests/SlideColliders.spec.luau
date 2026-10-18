--!nocheck
-- Fountain slide collision. The silo keeps its Basin / Trim / Silo colliders (FountainCollider.spec); the slide, which the
-- visual-only mesh leaves open, gets SlideColliders: per segment a floor slab whose top is the ride line plus a rail on each
-- side, from the head to the mouth, on in every mesh state. Checked here: players can walk the slide (solid just under the ride
-- line, clear head room over it, no gap at any join or bend, rails they cannot step over but can jump off), the low stretch
-- blocks a walker from the ground, and in the real server (fake runtime, mesh loaded and failed) the Parts exist, are solid,
-- invisible and anchored, survive the MeshSwap switch, and the riding slimes (anchored, never colliding) pass through walkers.
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
-- What the server places: SPECS plus the ground posts and staves brackets (SlideColliders.supports).
local LIVE = SlideColliders.all(PATH, WorldLayout.slidePath(WorldLayout.KIT_SLIDE_SAMPLES), true)
-- With FEATURES.SlidePCD the loaded mesh is the slide's collision and MeshSwap retires Floor / Joint / Post / Brace.
local LIVE_PCD = SlideColliders.all(PATH, WorldLayout.slidePath(WorldLayout.KIT_SLIDE_SAMPLES), true, true)
local EPS = 1e-3
local PLAYER_HEIGHT = 5 -- R15 character, feet to head
local JUMP_REACH = 7.2 -- a default Roblox jump clears ~7.2 studs
local STEP_UP = 2.5 -- a Humanoid walks up a ledge lower than this

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
	for _, spec in LIVE do
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
	it(
		"cover every slide segment (floor + both rails), top to mouth, and nothing else but skirts and joints",
		function()
			local names = byName()
			expect(#LOW >= 10).toBe(true)
			expect(PATH[1][2] > SlideColliders.WALK_UNDER * 4).toBe(true) -- the top really is high
			for i = 1, #PATH - 1 do
				expect(names[`SlideFloor{i}`] ~= nil).toBe(true)
				expect(names[`SlideRail{i}L`] ~= nil and names[`SlideRail{i}R`] ~= nil).toBe(true)
			end
			for _, spec in SPECS do
				expect(spec.segment >= 1 and spec.segment <= #PATH - 1).toBe(true)
				expect(spec.kind == "Floor" or spec.kind == "Rail" or spec.kind == "Skirt" or spec.kind == "Joint").toBe(
					true
				)
			end
		end
	)
	it("SlidePCD drops exactly the Post / Brace boxes and keeps the walk surface, the rails and the skirts", function()
		local kinds = {}
		for _, spec in LIVE_PCD do
			kinds[spec.kind] = (kinds[spec.kind] or 0) + 1
			expect(SlideColliders.PCD_RETIRED[spec.kind]).toBe(nil)
		end
		expect(kinds.Floor > 0 and kinds.Joint > 0 and kinds.Rail > 0 and kinds.Skirt > 0).toBe(true)
		local retired = 0
		for _, spec in LIVE do
			if SlideColliders.PCD_RETIRED[spec.kind] then
				retired += 1
			end
		end
		expect(retired > 0).toBe(true)
		expect(#LIVE_PCD).toBe(#LIVE - retired)
		expect(#SlideColliders.all(PATH, WorldLayout.slidePath(WorldLayout.KIT_SLIDE_SAMPLES), true, false)).toBe(#LIVE)
	end)
	it("flag off keeps the old low-only stretch", function()
		for _, spec in SlideColliders.build(PATH) do
			expect(SlideColliders.isLow(PATH[spec.segment], PATH[spec.segment + 1])).toBe(true)
		end
		expect(#SlideColliders.build(PATH) < #SPECS).toBe(true)
		expect(Config.FEATURES.SlideCollision).toBe(true)
	end)
	it("put the floor top exactly on the ride line", function()
		local names = byName()
		for i = 1, #PATH - 1 do
			for _, k in { 0.1, 0.5, 0.9 } do
				local p = along(i, k)
				expect(depth(names[`SlideFloor{i}`], p)).toBeCloseTo(0, EPS)
				expect(depth(names[`SlideFloor{i}`], { p[1], p[2] - 0.2, p[3] }) > 0).toBe(true)
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

-- Players walk the slide from the mouth to the head.
describe("the slide is walkable: a smooth ramp with rails", function()
	local CHAR_HALF_WIDTH = 1 -- an R15 character is ~2 studs wide
	local SEAM = 1 -- a Humanoid walks over a ledge this low (straight slabs leave <= 0.85 on the two sharp head bends, <= 0.25 elsewhere)
	-- Every collider the server places (the floors and rails are there with SlidePCD on and off).
	local function solidLive(q): (boolean, string?)
		for _, spec in LIVE do
			if depth(spec, q) > 0.05 then
				return true, spec.name
			end
		end
		return false, nil
	end
	local function offset(i: number, k: number, w: number, h: number)
		local right, up = frame(byName()[`SlideFloor{i}`])
		local p = along(i, k)
		return {
			p[1] + right[1] * w + up[1] * h,
			p[2] + right[2] * w + up[2] * h,
			p[3] + right[3] * w + up[3] * h,
		}
	end
	it("is solid just under the ride line and clear above it, across the walk width, at every k", function()
		local half = SlideColliders.HALF_WIDTH - CHAR_HALF_WIDTH
		for i = 1, #PATH - 1 do
			for _, k in { 0, 0.1, 0.25, 0.5, 0.75, 0.9, 1 } do
				for _, w in { -1, -0.5, 0, 0.5, 1 } do
					if not insideAny(offset(i, k, w * half, -0.2)) then
						error(`hole in the walk surface: segment {i} k={k} width {w}`)
					end
					local h = SEAM
					while h <= PLAYER_HEIGHT + 0.5 do
						local hit, name = solidLive(offset(i, k, w * half, h))
						if hit then
							error(`head room blocked by {name}: segment {i} k={k} width {w} height {h}`)
						end
						h += 0.25
					end
				end
			end
		end
	end)
	it("is unbroken at every join, bends included", function()
		for i = 1, #PATH - 2 do
			local j = PATH[i + 1]
			expect((insideAny({ j[1], j[2] - 0.2, j[3] }))).toBe(true)
			expect((solidLive({ j[1], j[2] + 0.1, j[3] }))).toBe(false)
		end
	end)
	it("a player dropped from above lands on the ride line, nothing over it", function()
		for i = 1, #PATH - 1 do
			local p = along(i, 0.5)
			local y = p[2] + 15
			local landedAt = nil
			while y > p[2] - 10 do
				if solidLive({ p[1], y, p[3] }) then
					landedAt = y
					break
				end
				y -= 0.05
			end
			expect(landedAt ~= nil).toBe(true)
			expect(math.abs(landedAt - p[2]) < 0.15).toBe(true)
		end
	end)
	it("has rails on both sides, too tall to step over and low enough to jump off, along the whole length", function()
		expect(SlideColliders.RAIL >= STEP_UP).toBe(true)
		expect(SlideColliders.RAIL < JUMP_REACH).toBe(true)
		local names = byName()
		for i = 1, #PATH - 1 do
			-- (the free ends are left out: the head opens onto the basin top, the mouth onto the ground)
			for _, k in { if i > 1 then 0 else 0.05, 0.05, 0.25, 0.5, 0.75, 0.95, if i < #PATH - 1 then 1 else 0.95 } do
				for _, side in { -1, 1 } do
					-- a walker stepping sideways off the centreline keeps its feet on the floor below it and meets a rail before
					-- the floor runs out (the mouth flares wider than HALF_WIDTH; on a bend the next segment's rail is the one met)
					local start = offset(i, k, 0, 0)
					local right = frame(names[`SlideFloor{i}`])
					local feet, w, met = start[2], 0, false
					while not met do
						w += 0.1
						local x, z = start[1] + right[1] * side * w, start[3] + right[3] * side * w
						local floor = nil
						local y = feet + SEAM
						while y > feet - SEAM do
							for _, spec in LIVE do
								if spec.kind ~= "Rail" and depth(spec, { x, y, z }) > 0 then
									floor = y
								end
							end
							if floor then
								break
							end
							y -= 0.05
						end
						if not floor then
							error(`walked off the slide: segment {i} k={k} side {side} after {w} studs`)
						end
						feet = floor
						for _, h in { 1.2, 2 } do -- shins and knees: what meets the rail (its top is checked below)
							for _, spec in LIVE do
								if spec.kind == "Rail" and depth(spec, { x, feet + h, z }) > 0 then
									met = true
								end
							end
						end
					end
				end
			end
			-- the rail's top is RAIL over the ride line: a jump clears it
			for _, side in { "L", "R" } do
				local rail = names[`SlideRail{i}{side}`]
				local _, up = frame(rail)
				local top = dot(sub(rail.centre, along(i, 0.5)), up) + rail.size[2] / 2
				expect(top).toBeCloseTo(SlideColliders.RAIL, EPS)
			end
		end
	end)
	it("slabs are thick enough for a falling player, nothing is a thin sheet", function()
		for _, spec in SPECS do
			if spec.kind == "Floor" then
				expect(spec.size[2] >= SlideColliders.MIN_THICK).toBe(true)
			end
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
			local live = if state == "mesh loaded" and Config.FEATURES.SlidePCD then LIVE_PCD else LIVE
			expect(#parts).toBe(#live)
			local names = byName()
			for _, part in parts do
				local spec = names[part.Name]
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
		it(`{state}: riding slimes are anchored and never collide (they pass through walkers on the slide)`, function()
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
				-- solid under the ride line, before and after the merge
				for _, set in { RAW, SPECS } do
					expect(inside(set, { p[1], p[2] - 0.05, p[3] })).toBe(true)
				end
			end
		end
	end)
end)
