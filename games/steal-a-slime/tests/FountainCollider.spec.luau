--!nocheck
-- Fountain collision in the fake runtime, both MeshSwap outcomes. The fountain
-- mesh is visual-only, so two invisible cylinders shaped like the mesh's silo
-- profile are its collision: BasinCollider (the walkable plinth) and
-- SiloCollider (the wall up to the eave). Their numbers come from
-- WorldLayout.FOUNTAIN_PROFILE, checked here against the modeling kit source.
-- Mesh loaded: the hidden stand-ins stop colliding. Mesh still loading /
-- failed: the visible stand-ins keep colliding. Either way only the two
-- colliders collide unseen, and the base is a step, not a ledge.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local M = "slime_fountain"
local SOLID_STAND_INS = { "Rock1", "BasinRim", "Column", "Bowl" }
local COLLIDERS = { "BasinCollider", "SiloCollider" }
local EPS = 1e-3 -- Part sizes are float32
local MAX_STEP = 2 -- highest ledge a player may meet unseen
local FP = WorldLayout.FOUNTAIN_PROFILE

-- The kit's silo profile, read from the model source (literal PROF rings,
-- WALL_TOP, wall_r foot radius, Z0 eave edge top offset).
local KIT = (function()
	local src = fs.readFile("../../shared/modeling-kit/models/slime_fountain.py")
	local rings = {}
	for r, z, tag in string.gmatch(src, '%(([%d%.]+), ([%d%.]+), "([%w_]+)", %d%)') do
		rings[tag] = rings[tag] or { r = tonumber(r), z = tonumber(z) }
	end
	local wallTop = tonumber(string.match(src, "\nWALL_TOP = ([%d%.]+)"))
	return {
		rings = rings,
		wallTop = wallTop,
		wallRadius = tonumber(string.match(src, "return ([%d%.]+) %+ [%d%.]+ %* math%.sin")),
		eaveTop = wallTop + tonumber(string.match(src, "\nZ0 = WALL_TOP %+ ([%d%.]+)")),
	}
end)()

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-collider-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local function boot(opts)
	local rt = Runtime.new(path, opts)
	rt:boot()
	rt:advance(2)
	local map = rt.workspace:FindFirstChild("Map")
	return map.Volcano, map
end

local failedVolcano, failedMap = boot({})
local loadedVolcano, loadedMap = boot({
	createMeshPart = function(_meshId)
		return roblox.Instance.new("MeshPart")
	end,
})
require("@lune/fs").removeFile(path)

-- Colliding parts nobody can see, under the fountain and its slide.
local function invisibleColliders(map): { string }
	local out = {}
	for _, root in { map.Volcano, map.Chute } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d.Transparency >= 1 then
				table.insert(out, d.Name)
			end
		end
	end
	table.sort(out)
	return out
end

-- Upright cylinder (Size = height, d, d; rolled 90): radius, bottom, top.
local function radius(part): number
	return part.Size.Y / 2
end
local function bottom(part): number
	return part.CFrame.Position.Y - part.Size.X / 2
end
local function top(part): number
	return part.CFrame.Position.Y + part.Size.X / 2
end

local function expectColliders(volcano)
	for _, name in COLLIDERS do
		local c = volcano:FindFirstChild(name)
		expect(c ~= nil).toBe(true)
		expect(c.Shape).toBe(roblox.Enum.PartType.Cylinder)
		expect(c.Anchored).toBe(true)
		expect(c.CanCollide).toBe(true)
		expect(c.CanQuery).toBe(false)
		expect(c.CanTouch).toBe(false)
		expect(c.Transparency).toBe(1)
		-- On the silo axis (the world origin).
		expect(c.CFrame.Position.X).toBeCloseTo(0, EPS)
		expect(c.CFrame.Position.Z).toBeCloseTo(0, EPS)
	end
	local plinth, wall = volcano.BasinCollider, volcano.SiloCollider
	expect(bottom(plinth)).toBeCloseTo(0, EPS)
	expect(radius(plinth)).toBeCloseTo(KIT.rings.plinth_top.r, EPS)
	expect(top(plinth)).toBeCloseTo(KIT.rings.plinth_top.z, EPS)
	expect(radius(wall)).toBeCloseTo(KIT.wallRadius, EPS)
	expect(bottom(wall)).toBeCloseTo(top(plinth), EPS)
	expect(top(wall) >= KIT.wallTop).toBe(true)
	expect(top(wall) >= KIT.eaveTop - EPS).toBe(true)
end

-- Every unseen ledge a player meets walking in from the ground: the plinth
-- top, then the wall, which must be taller than any jump-free step.
local function expectNoLedge(volcano)
	local plinth, wall = volcano.BasinCollider, volcano.SiloCollider
	expect(top(plinth) <= MAX_STEP).toBe(true)
	expect(radius(wall) < radius(plinth)).toBe(true)
	expect(bottom(wall) <= top(plinth) + EPS).toBe(true)
	expect(top(wall) - top(plinth) > MAX_STEP).toBe(true)
end

describe("fountain profile matches the modeling kit", function()
	it("reads the kit's silo profile", function()
		expect(KIT.rings.plinth ~= nil).toBe(true)
		expect(KIT.rings.plinth_top ~= nil).toBe(true)
		expect(KIT.rings.trim_lo ~= nil).toBe(true)
		expect(KIT.rings.trim ~= nil).toBe(true)
	end)
	it("WorldLayout.FOUNTAIN_PROFILE carries the kit numbers", function()
		expect(FP.plinthRadius).toBeCloseTo(KIT.rings.plinth_top.r)
		expect(FP.plinthTop).toBeCloseTo(KIT.rings.plinth_top.z)
		expect(FP.trimRadius).toBeCloseTo(KIT.rings.trim_lo.r)
		expect(FP.trimTop).toBeCloseTo(KIT.rings.trim.z)
		expect(FP.wallRadius).toBeCloseTo(KIT.wallRadius)
		expect(FP.wallRadius).toBeCloseTo(KIT.rings.trim.r)
		expect(FP.wallTop).toBeCloseTo(KIT.wallTop)
		expect(FP.eaveTop).toBeCloseTo(KIT.eaveTop)
	end)
	it("the plinth is the widest ring below the eave (nothing pokes out past it)", function()
		for _, ring in KIT.rings do
			if ring.z < KIT.wallTop then
				expect(ring.r <= FP.plinthRadius + EPS).toBe(true)
			end
		end
	end)
end)

describe("fountain collider, mesh loaded", function()
	it("swaps the mesh in as visual-only", function()
		local mesh = loadedVolcano.FountainMesh:FindFirstChild("Mesh")
		expect(mesh ~= nil).toBe(true)
		expect(mesh.CanCollide).toBe(false)
		expect(mesh.Anchored).toBe(true)
	end)
	it("keeps the plinth and silo colliders on the kit profile", function()
		expectColliders(loadedVolcano)
	end)
	it("leaves no ledge over 2 studs at the base", function()
		expectNoLedge(loadedVolcano)
	end)
	it("turns every hidden fountain stand-in's collision off", function()
		local n = 0
		for _, d in loadedMap:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("MeshStandIn") == M then
				n += 1
				expect(d.Transparency).toBe(1)
				expect(d.CanCollide).toBe(false)
			end
		end
		expect(n > #SOLID_STAND_INS).toBe(true)
	end)
	it("leaves no invisible step around the base (only the two colliders collide unseen)", function()
		expect(invisibleColliders(loadedMap)).toEqual(COLLIDERS)
	end)
end)

describe("fountain collider, mesh loading or failed", function()
	it("keeps the primitive placeholder (no mesh)", function()
		expect(failedVolcano.FountainMesh:FindFirstChild("Mesh")).toBe(nil)
	end)
	it("keeps the plinth and silo colliders on the kit profile", function()
		expectColliders(failedVolcano)
	end)
	it("keeps the visible stand-ins solid", function()
		for _, name in SOLID_STAND_INS do
			local part = failedVolcano[name]
			expect(part.Transparency < 1).toBe(true)
			expect(part.CanCollide).toBe(true)
		end
	end)
	it("leaves no invisible step around the base (the plinth sits inside the visible base)", function()
		expect(invisibleColliders(failedMap)).toEqual(COLLIDERS)
		local plinth = failedVolcano.BasinCollider
		local rock = failedVolcano.Rock1
		expect(radius(plinth) <= radius(rock) + EPS).toBe(true)
		expect(top(plinth) <= top(rock) + EPS).toBe(true)
	end)
end)
