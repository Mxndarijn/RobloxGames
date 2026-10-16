--!nocheck
-- Fountain colliders (TODO 13, v27 playtest: players walked through the
-- fountain). The silo keeps its Basin / Trim / Silo colliders
-- (FountainCollider.spec); the low slide, which the visual-only mesh left
-- open, gets SlideColliders: floor, walls and skirts along SLIDE_PATH, on
-- in every mesh state. Checked here: the specs block a walking player at
-- the slide, every fountain collider leaves the slime ride path clear
-- (pure, 400 rolled rides), and in the real server (fake runtime, mesh
-- loaded and failed) the Parts exist, are solid, invisible and anchored,
-- survive the MeshSwap switch, and the riding slimes never collide.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Fountain = require("../src/shared/Fountain")
local FountainRide = require("../src/shared/FountainRide")
local Rng = require("../src/shared/Rng")
local Runtime = require("../tools/livetest/Runtime")
local SlideColliders = require("../src/shared/SlideColliders")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PATH = WorldLayout.SLIDE_PATH
local FP = WorldLayout.FOUNTAIN_PROFILE
local SPECS = SlideColliders.build(PATH)
local EPS = 1e-3
local PLAYER_HEIGHT = 5 -- R15 character, feet to head
local BODY_LIFT = 1.5 -- body centre above the pivot for a size-1 slime

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
		if depth(spec, p) > EPS then
			return true, spec.name
		end
	end
	return false, nil
end

-- The silo colliders (FountainCollider.spec checks them against the kit).
local SILO = {
	{ r = FP.plinthRadius, lo = 0, hi = FP.plinthTop },
	{ r = FP.trimRadius, lo = FP.plinthTop, hi = FP.trimTop },
	{ r = FP.wallRadius, lo = FP.plinthTop, hi = FP.eaveTop },
}
local function insideSilo(p): boolean
	local r = math.sqrt(p[1] ^ 2 + p[3] ^ 2)
	for _, c in SILO do
		if r < c.r - EPS and p[2] > c.lo + EPS and p[2] < c.hi - EPS then
			return true
		end
	end
	return false
end

local LOW = {}
for i = 1, #PATH - 1 do
	if SlideColliders.isLow(PATH[i], PATH[i + 1]) then
		table.insert(LOW, i)
	end
end

local function byName(): { [string]: any }
	local out = {}
	for _, spec in SPECS do
		out[spec.name] = spec
	end
	return out
end

describe("SlideColliders specs", function()
	it("cover every low slide segment (floor + both walls), only the low ones", function()
		local names = byName()
		expect(#LOW >= 10).toBe(true)
		for _, i in LOW do
			expect(names[`SlideFloor{i}`] ~= nil).toBe(true)
			expect(names[`SlideWallL{i}`] ~= nil).toBe(true)
			expect(names[`SlideWallR{i}`] ~= nil).toBe(true)
		end
		for _, spec in SPECS do
			expect(SlideColliders.isLow(PATH[spec.segment], PATH[spec.segment + 1])).toBe(true)
		end
	end)
	it("put the floor top exactly on the ride line, the walls either side of it", function()
		local names = byName()
		for _, i in LOW do
			local a, b = PATH[i], PATH[i + 1]
			for _, k in { 0.1, 0.5, 0.9 } do
				local p = { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
				expect(depth(names[`SlideFloor{i}`], p)).toBeCloseTo(0, EPS)
				expect(depth(names[`SlideFloor{i}`], { p[1], p[2] - 0.2, p[3] }) > 0).toBe(true)
				local right = frame(names[`SlideFloor{i}`])
				local half = names[`SlideFloor{i}`].size[1] / 2
				for _, side in { -1, 1 } do
					local wall = names[if side < 0 then `SlideWallL{i}` else `SlideWallR{i}`]
					local q = { p[1] + right[1] * side * (half - 0.3), p[2] + 1, p[3] + right[3] * side * (half - 0.3) }
					expect(depth(wall, q) > 0).toBe(true)
				end
			end
		end
	end)
	it("block a walking player: nothing on the low slide is walk-through from the ground up", function()
		for _, i in LOW do
			local a, b = PATH[i], PATH[i + 1]
			local top = math.min(a[2], b[2])
			if top > PLAYER_HEIGHT then
				continue
			end
			for _, k in { 0.25, 0.5, 0.75 } do
				local x, z = a[1] + (b[1] - a[1]) * k, a[3] + (b[3] - a[3]) * k
				local floorY = a[2] + (b[2] - a[2]) * k
				-- every height a player's body crosses below the floor, plus the walls above it
				local y = 0.1
				while y < floorY - 0.1 do
					expect((insideAny({ x, y, z }))).toBe(true)
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
				expect(skirt ~= nil).toBe(true)
				expect(skirt.forward[2]).toBe(0)
				expect(skirt.centre[2] - skirt.size[2] / 2).toBeCloseTo(0, EPS)
				expect(skirt.centre[2] + skirt.size[2] / 2).toBeCloseTo(bottom, EPS)
			else
				expect(skirt).toBe(nil)
			end
		end
	end)
end)

describe("fountain colliders leave the ride path clear", function()
	local rng = Rng.new(13)
	local rides = {}
	for k = 1, 400 do
		local drop = Fountain.roll(rng, `c{k}`, false)
		local x, z =
			FountainRide.clearLanding(PATH, math.cos(drop.angle) * drop.radius, math.sin(drop.angle) * drop.radius)
		table.insert(rides, FountainRide.new(PATH, { x, 0.15, z }))
	end
	it("no ride point (pivot) is inside a slide or silo collider", function()
		for _, ride in rides do
			for _, p in ride.points do
				local inside, name = insideAny(p)
				if inside then
					error(`ride point ({p[1]}, {p[2]}, {p[3]}) inside {name}`)
				end
				expect(insideSilo(p)).toBe(false)
			end
		end
	end)
	it("the slime body above the pivot stays clear too", function()
		for k = 1, 60 do
			for _, p in rides[k].points do
				local body = { p[1], p[2] + BODY_LIFT, p[3] }
				expect((insideAny(body))).toBe(false)
				expect(insideSilo(body)).toBe(false)
			end
		end
	end)
end)

-- The real server, mesh loaded and failed.
local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-slidecol-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", placePath })
assert(built.ok, `rojo build failed: {built.stderr}`)

local function boot(loaded: boolean)
	local rt = Runtime.new(placePath, {
		createMeshPart = function(meshId)
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
			expect(#parts).toBe(#SPECS)
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
		it(`{state}: riding slimes are anchored and never collide (colliders can't stop them)`, function()
			local rides = if state == "mesh loaded" then loadedRides else failedRides
			expect(#rides > 100).toBe(true)
			for _, r in rides do
				expect(r.solid).toBe(false)
				expect(r.anchored).toBe(true)
			end
		end)
		it(`{state}: no slime pivot ever sits inside a fountain collider Part`, function()
			local rides = if state == "mesh loaded" then loadedRides else failedRides
			local colliders = {}
			for _, d in rt.workspace.Map.Volcano:GetDescendants() do
				if d:IsA("BasePart") and (d:GetAttribute("FountainCollider") or d:GetAttribute("MeshCollider")) then
					table.insert(colliders, d)
				end
			end
			expect(#colliders).toBe(#SPECS + 3)
			for _, r in rides do
				for _, part in colliders do
					local l = part.CFrame:PointToObjectSpace(r.p)
					local s = part.Size
					local inside
					if part.Shape == roblox.Enum.PartType.Cylinder then
						inside = math.abs(l.X) < s.X / 2 - EPS and math.sqrt(l.Y ^ 2 + l.Z ^ 2) < s.Y / 2 - EPS
					else
						inside = math.abs(l.X) < s.X / 2 - EPS
							and math.abs(l.Y) < s.Y / 2 - EPS
							and math.abs(l.Z) < s.Z / 2 - EPS
					end
					if inside then
						error(`slime pivot {r.p} inside {part.Name}`)
					end
				end
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
