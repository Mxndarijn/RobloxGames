--!nocheck
-- Fountain collision in the fake runtime, every MeshSwap state. The fountain
-- mesh is visual-only, so two invisible cylinders shaped like the mesh's silo
-- profile are its collision: BasinCollider (the walkable plinth) and
-- SiloCollider (the wall up to the eave). Their numbers come from
-- WorldLayout.FOUNTAIN_PROFILE, checked here against the modeling kit source.
-- One switch (MeshSwap.setMeshCollision) hands collision over: the colliders
-- start off and go on at the moment the mesh lands, when the stand-ins go
-- off. Loading (before / during CreateMeshPartAsync) or failed: colliders off,
-- the visible stand-ins collide. Every state: the base is a step, not a ledge.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local MeshAssets = require("../src/shared/MeshAssets")
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
local FOUNTAIN_MESH_ID = MeshAssets.meshId(M)

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

local STATE_PARTS = { "BasinCollider", "SiloCollider", "Rock1", "BasinRim", "Column", "Bowl" }

-- CanCollide of the colliders and the solid stand-ins, right now.
local function collision(volcano): { [string]: boolean }
	local out = {}
	for _, name in STATE_PARTS do
		out[name] = volcano[name].CanCollide
	end
	return out
end

local LOADING =
	{ BasinCollider = false, SiloCollider = false, Rock1 = true, BasinRim = true, Column = true, Bowl = true }
local LOADED =
	{ BasinCollider = true, SiloCollider = true, Rock1 = false, BasinRim = false, Column = false, Bowl = false }

-- `create` stands in for CreateMeshPartAsync; each call snapshots the
-- fountain's collision while that fetch is in flight (still loading).
local function boot(create: ((string) -> any)?, noBoot: boolean?)
	local rt
	local inFlight = {}
	rt = Runtime.new(path, {
		createMeshPart = function(meshId)
			table.insert(inFlight, { meshId = meshId, state = collision(rt.workspace.Map.Volcano) })
			if create then
				return create(meshId)
			end
			error(`livetest: CreateMeshPartAsync({meshId}) failed`)
		end,
	})
	if not noBoot then
		rt:boot()
		rt:advance(2)
	end
	local map = rt.workspace:FindFirstChild("Map")
	return { volcano = map.Volcano, map = map, rt = rt, inFlight = inFlight }
end

-- Loading: the map as the server starts it, before MeshSwap ran.
local loading = boot(nil, true)
local failed = boot(nil)
local loaded = boot(function(_meshId)
	return roblox.Instance.new("MeshPart")
end)
-- A second loaded run for the switch test to flip back and forth.
local toggled = boot(function(_meshId)
	return roblox.Instance.new("MeshPart")
end)
local loadingVolcano, loadingMap = loading.volcano, loading.map
local failedVolcano, failedMap = failed.volcano, failed.map
local loadedVolcano, loadedMap = loaded.volcano, loaded.map
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

local function expectColliders(volcano, on: boolean)
	for _, name in COLLIDERS do
		local c = volcano:FindFirstChild(name)
		expect(c ~= nil).toBe(true)
		expect(c.Shape).toBe(roblox.Enum.PartType.Cylinder)
		expect(c.Anchored).toBe(true)
		expect(c.CanCollide).toBe(on)
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

-- Fountain stand-ins that don't collide even with no mesh (Pool, Crater,
-- the chute spans): the switch must give them back their own CanCollide.
local function decorStandIns(map): { string }
	local out = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("MeshStandIn") == M and not d.CanCollide then
			table.insert(out, d:GetFullName())
		end
	end
	table.sort(out)
	return out
end

describe("fountain collider, mesh loading", function()
	it("starts with no mesh and both colliders off, on the kit profile", function()
		expect(loadingVolcano.FountainMesh:FindFirstChild("Mesh")).toBe(nil)
		expectColliders(loadingVolcano, false)
	end)
	it("tags only the two colliders MeshCollider = slime_fountain", function()
		local tagged = {}
		for _, d in loadingMap:GetDescendants() do
			if d:GetAttribute("MeshCollider") ~= nil then
				expect(d:GetAttribute("MeshCollider")).toBe(M)
				table.insert(tagged, d.Name)
			end
		end
		table.sort(tagged)
		expect(tagged).toEqual(COLLIDERS)
	end)
	it("keeps the visible stand-ins solid", function()
		expect(collision(loadingVolcano)).toEqual(LOADING)
		for _, name in SOLID_STAND_INS do
			expect(loadingVolcano[name].Transparency < 1).toBe(true)
		end
	end)
	it("has no unseen collision", function()
		expect(invisibleColliders(loadingMap)).toEqual({})
	end)
	it("stays that way while the fountain's CreateMeshPartAsync is in flight", function()
		for _, run in { loaded, failed } do
			local n = 0
			for _, call in run.inFlight do
				if call.meshId == FOUNTAIN_MESH_ID then
					n += 1
					expect(call.state).toEqual(LOADING)
				end
			end
			expect(n).toBe(1)
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
	it("switches both colliders on and the stand-ins off in the same step", function()
		expect(collision(loadedVolcano)).toEqual(LOADED)
	end)
	it("keeps the plinth and silo colliders on the kit profile", function()
		expectColliders(loadedVolcano, true)
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
	it("setMeshCollision is the one switch: off restores the stand-ins, on again matches MeshSwap", function()
		local run = toggled
		local MeshSwap = run.rt:require(run.rt.game:GetService("ServerScriptService").Server.MeshSwap)
		expect(collision(run.volcano)).toEqual(LOADED)
		MeshSwap.setMeshCollision(run.map, M, false)
		expect(collision(run.volcano)).toEqual(LOADING)
		expect(decorStandIns(run.map)).toEqual(decorStandIns(loadingMap))
		MeshSwap.setMeshCollision(run.map, M, true)
		expect(collision(run.volcano)).toEqual(LOADED)
	end)
end)

describe("fountain collider, mesh failed", function()
	it("keeps the primitive placeholder (no mesh)", function()
		expect(failedVolcano.FountainMesh:FindFirstChild("Mesh")).toBe(nil)
	end)
	it("keeps both colliders off, on the kit profile", function()
		expectColliders(failedVolcano, false)
	end)
	it("keeps the visible stand-ins solid", function()
		expect(collision(failedVolcano)).toEqual(LOADING)
		for _, name in SOLID_STAND_INS do
			expect(failedVolcano[name].Transparency < 1).toBe(true)
		end
	end)
	it("has no unseen collision (the plinth sits inside the visible base)", function()
		expect(invisibleColliders(failedMap)).toEqual({})
		local plinth = failedVolcano.BasinCollider
		local rock = failedVolcano.Rock1
		expect(radius(plinth) <= radius(rock) + EPS).toBe(true)
		expect(top(plinth) <= top(rock) + EPS).toBe(true)
	end)
end)
