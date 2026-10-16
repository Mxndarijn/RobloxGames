--!nocheck
-- Fountain collision in the fake runtime, every MeshSwap state. The fountain
-- mesh is visual-only, so three invisible cylinders shaped like the mesh's silo
-- profile are its collision: BasinCollider (the walkable plinth),
-- TrimCollider (the bevel at the foot of the staves) and SiloCollider (the
-- wall up to the eave). Their numbers come from
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
local COLLIDERS = { "BasinCollider", "SiloCollider", "TrimCollider" }
local TIERS = WorldLayout.fountainTopTiers()
local TOP_COLLIDERS = {}
for i = 1, #TIERS do
	table.insert(TOP_COLLIDERS, `TopCollider{i}`)
end
local ALL_COLLIDERS = table.clone(COLLIDERS)
for _, name in TOP_COLLIDERS do
	table.insert(ALL_COLLIDERS, name)
end
table.sort(ALL_COLLIDERS)
local EPS = 1e-3 -- Part sizes are float32
local MAX_STEP = 2 -- highest ledge a player may meet unseen
local FP = WorldLayout.FOUNTAIN_PROFILE
local BASIN = FP.eaveTop + FP.domeRise -- 35.9: the dome's top, the basin floor
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

local STATE_PARTS = { "BasinCollider", "TrimCollider", "SiloCollider", "Rock1", "BasinRim", "Column", "Bowl" }
for _, name in TOP_COLLIDERS do
	table.insert(STATE_PARTS, name)
end

-- CanCollide of the colliders and the solid stand-ins, right now.
local function collision(volcano): { [string]: boolean }
	local out = {}
	for _, name in STATE_PARTS do
		out[name] = volcano[name].CanCollide
	end
	return out
end

local LOADING = {
	BasinCollider = false,
	TrimCollider = false,
	SiloCollider = false,
	Rock1 = true,
	BasinRim = true,
	Column = true,
	Bowl = true,
}
for _, name in TOP_COLLIDERS do
	LOADING[name] = false
end
local LOADED = {
	BasinCollider = true,
	TrimCollider = true,
	SiloCollider = true,
	Rock1 = false,
	BasinRim = false,
	Column = false,
	Bowl = false,
}
for _, name in TOP_COLLIDERS do
	LOADED[name] = true
end

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
-- Colliding parts nobody can see, under the fountain and its slide. The
-- low slide's own colliders (Volcano.SlideColliders, on in every state where
-- the slide is drawn) are checked in SlideColliders.spec.
local function invisibleColliders(map): { string }
	local out = {}
	local slide = map.Volcano:FindFirstChild("SlideColliders")
	for _, root in { map.Volcano, map.Chute } do
		for _, d in root:GetDescendants() do
			if slide and d:IsDescendantOf(slide) then
				continue
			end
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
	local plinth, trim, wall = volcano.BasinCollider, volcano.TrimCollider, volcano.SiloCollider
	expect(bottom(plinth)).toBeCloseTo(0, EPS)
	expect(radius(plinth)).toBeCloseTo(KIT.rings.plinth_top.r, EPS)
	expect(top(plinth)).toBeCloseTo(KIT.rings.plinth_top.z, EPS)
	expect(radius(trim)).toBeCloseTo(KIT.rings.trim_lo.r, EPS)
	expect(bottom(trim)).toBeCloseTo(top(plinth), EPS)
	expect(top(trim)).toBeCloseTo(KIT.rings.trim.z, EPS)
	expect(radius(wall)).toBeCloseTo(KIT.wallRadius, EPS)
	expect(bottom(wall)).toBeCloseTo(top(plinth), EPS)
	expect(top(wall) >= KIT.wallTop).toBe(true)
	expect(top(wall) >= KIT.eaveTop - EPS).toBe(true)
end

-- Every unseen ledge a player meets walking in from the ground: the plinth
-- top, the trim bevel, then the wall, which must be taller than any
-- jump-free step.
local function expectNoLedge(volcano)
	local plinth, trim, wall = volcano.BasinCollider, volcano.TrimCollider, volcano.SiloCollider
	expect(top(plinth) <= MAX_STEP).toBe(true)
	expect(radius(trim) < radius(plinth)).toBe(true)
	expect(radius(wall) < radius(trim)).toBe(true)
	expect(top(trim) - top(plinth) <= MAX_STEP).toBe(true)
	expect(bottom(wall) <= top(plinth) + EPS).toBe(true)
	expect(top(wall) - top(trim) > MAX_STEP).toBe(true)
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
	it("starts with no mesh and every collider off, on the kit profile", function()
		expect(loadingVolcano.FountainMesh:FindFirstChild("Mesh")).toBe(nil)
		expectColliders(loadingVolcano, false)
	end)
	it("tags only the colliders MeshCollider = slime_fountain", function()
		local tagged = {}
		for _, d in loadingMap:GetDescendants() do
			if d:GetAttribute("MeshCollider") ~= nil then
				expect(d:GetAttribute("MeshCollider")).toBe(M)
				table.insert(tagged, d.Name)
			end
		end
		table.sort(tagged)
		expect(tagged).toEqual(ALL_COLLIDERS)
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
	it("switches all three colliders on and the stand-ins off in the same step", function()
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
	it("leaves no invisible step around the base (only the base and top colliders collide unseen)", function()
		expect(invisibleColliders(loadedMap)).toEqual(ALL_COLLIDERS)
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
	it("keeps every collider off, on the kit profile", function()
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
		local rock = failedVolcano.Rock1
		for _, name in { "BasinCollider", "TrimCollider" } do
			local c = failedVolcano[name]
			expect(radius(c) <= radius(rock) + EPS).toBe(true)
			expect(top(c) <= top(rock) + EPS).toBe(true)
		end
	end)
end)

-- The Studio report numbers (kit PROF, studs): feet sank ~1.1 between h1.5
-- and h2.4 because nothing filled the trim bevel. Literal numbers on purpose.
local REAL = {
	BasinCollider = { r = 13.1, bottom = 0, top = 1.5 },
	TrimCollider = { r = 12.3, bottom = 1.5, top = 2.4 },
	SiloCollider = { r = 11.2, bottom = 1.5, top = 31.3 },
}

-- Highest colliding top a foot meets at distance `r` from the silo axis.
local function surfaceAt(volcano, r: number): number
	local h = 0
	for _, name in COLLIDERS do
		local c = volcano[name]
		if c.CanCollide and radius(c) >= r then
			h = math.max(h, top(c))
		end
	end
	return h
end

describe("fountain bevel collider, real numbers", function()
	for _, case in { { "loading", loading, false }, { "loaded", loaded, true }, { "failed", failed, false } } do
		local state, run, on = case[1], case[2], case[3]
		it(`{state}: plinth r13.1 h0-1.5, bevel r12.3 h1.5-2.4, wall r11.2 h1.5-31.3`, function()
			for name, want in REAL do
				local c = run.volcano[name]
				expect(radius(c)).toBeCloseTo(want.r, EPS)
				expect(bottom(c)).toBeCloseTo(want.bottom, EPS)
				expect(top(c)).toBeCloseTo(want.top, EPS)
				expect(c:GetAttribute("MeshCollider")).toBe(M)
				expect(c.CanCollide).toBe(on)
				expect(c.Transparency).toBe(1)
			end
		end)
	end
	it("loaded: the collision silhouette follows the profile (no sink between h1.5 and h2.4)", function()
		local v = loadedVolcano
		expect(surfaceAt(v, 13.0)).toBeCloseTo(1.5, EPS)
		expect(surfaceAt(v, 12.5)).toBeCloseTo(1.5, EPS)
		expect(surfaceAt(v, 12.2)).toBeCloseTo(2.4, EPS)
		expect(surfaceAt(v, 11.5)).toBeCloseTo(2.4, EPS)
		expect(surfaceAt(v, 11.1)).toBeCloseTo(31.3, EPS)
		expect(surfaceAt(v, 13.2)).toBe(0)
	end)
	it("loading / failed: no collider collides, the stand-ins carry the collision", function()
		for _, run in { loading, failed } do
			for _, r in { 13.0, 12.2, 11.1 } do
				expect(surfaceAt(run.volcano, r)).toBe(0)
			end
			expect(run.volcano.Rock1.CanCollide).toBe(true)
		end
	end)
	it("the switch flips the bevel with the other colliders", function()
		local run = toggled
		local MeshSwap = run.rt:require(run.rt.game:GetService("ServerScriptService").Server.MeshSwap)
		MeshSwap.setMeshCollision(run.map, M, false)
		expect(run.volcano.TrimCollider.CanCollide).toBe(false)
		MeshSwap.setMeshCollision(run.map, M, true)
		expect(run.volcano.TrimCollider.CanCollide).toBe(true)
	end)
end)

-- The top of the fountain (v30 C10): above the silo wall (31.3) the mesh has
-- the eave, the red dome shoulder and the basin floor; none of it collided, so
-- players walked through the top. Kit numbers, read from the model source.
local TOP = (function()
	local src = fs.readFile("../../shared/modeling-kit/models/slime_fountain.py")
	assert(string.find(src, "8.9 + 4.5 * math.cos(phi), Z0 + 4.6 * math.sin(phi)", 1, true), "kit dome formula changed")
	return { floor = KIT.eaveTop + 4.6 }
end)()

-- Height of the kit's solid top at distance r from the axis (dome outline, then the basin floor).
local function profileTop(r: number): number
	if r > FP.eaveRadius then
		return 0
	end
	if r <= FP.domeCentre then
		return BASIN
	end
	local c = (r - FP.domeCentre) / FP.domeSpan
	return FP.eaveTop + FP.domeRise * math.sqrt(1 - c * c)
end

describe("fountain top collider, profile", function()
	it("reads the dome top (the basin floor) from the kit", function()
		expect(BASIN).toBeCloseTo(TOP.floor, EPS)
		expect(FP.domeCentre).toBe(8.9)
		expect(FP.domeSpan).toBe(4.5)
		expect(FP.domeRise).toBe(4.6)
		expect(FP.eaveRadius).toBeCloseTo(13.4)
	end)
	it("stacks invisible upright cylinders on the silo axis from the eave to the basin floor", function()
		local prevTop = FP.wallTop
		for i, name in TOP_COLLIDERS do
			local c = loadedVolcano[name]
			expect(c.ClassName).toBe("Part")
			expect(c.Shape).toBe(roblox.Enum.PartType.Cylinder)
			expect(c.Anchored).toBe(true)
			expect(c.CanCollide).toBe(true)
			expect(c.CanQuery).toBe(false)
			expect(c.Transparency).toBe(1)
			expect(c.CFrame.Position.X).toBeCloseTo(0, EPS)
			expect(c.CFrame.Position.Z).toBeCloseTo(0, EPS)
			expect(c:GetAttribute("MeshCollider")).toBe(M)
			expect(bottom(c)).toBeCloseTo(FP.wallTop, EPS) -- full columns from the eave underside: no gap, no thin slab
			expect(top(c) - bottom(c) >= 1.3 - EPS).toBe(true) -- a falling body never meets a slab it can sink through
			expect(top(c) > prevTop).toBe(true)
			expect(i == 1 or top(c) - prevTop <= 0.7).toBe(true) -- no unseen step above the eave
			expect(i == 1 or radius(c) <= radius(loadedVolcano[TOP_COLLIDERS[i - 1]]) + EPS).toBe(true) -- never wider as it rises
			prevTop = top(c)
			expect(i <= #TIERS).toBe(true)
		end
		expect(prevTop).toBeCloseTo(BASIN, EPS)
		expect(bottom(loadedVolcano.TopCollider1)).toBeCloseTo(FP.wallTop, EPS)
		expect(radius(loadedVolcano.TopCollider1)).toBeCloseTo(FP.eaveRadius, EPS)
	end)
	it("adds no mesh (invisible Parts only)", function()
		for _, name in TOP_COLLIDERS do
			expect(loadedVolcano[name]:IsA("MeshPart")).toBe(false)
		end
	end)
end)

-- Highest colliding top over distance r, among colliders that collide now (silo included).
local function surfaceNow(volcano, r: number): number
	local h = 0
	for _, name in ALL_COLLIDERS do
		local c = volcano[name]
		if c.CanCollide and radius(c) >= r then
			h = math.max(h, top(c))
		end
	end
	return h
end

describe("fountain top collider, no holes", function()
	-- Dense grid over the top, every 0.05 stud out from the axis to the eave edge.
	it("loaded: the collision covers the dome, never under the profile, never far over it", function()
		local worstUnder, worstOver = 0, 0
		local samples = 0
		for i = 0, 268 do
			local r = i * 0.05
			if r < 0.01 then
				continue
			end
			local want = if r <= FP.wallRadius then math.max(profileTop(r), FP.eaveTop) else profileTop(r)
			local got = surfaceNow(loadedVolcano, r)
			samples += 1
			worstUnder = math.min(worstUnder, got - want)
			worstOver = math.max(worstOver, got - want)
		end
		expect(samples > 250).toBe(true)
		expect(worstUnder >= -EPS).toBe(true) -- feet never sink under the visible top
		expect(worstOver <= 0.5).toBe(true) -- and no bump over half a stud
	end)
	it("loaded: every radius from the axis to the eave edge has a collider top above the wall", function()
		for i = 1, 268 do
			expect(surfaceNow(loadedVolcano, i * 0.05) >= FP.eaveTop).toBe(true)
		end
		expect(surfaceNow(loadedVolcano, FP.eaveRadius + 0.2) <= FP.trimTop).toBe(true)
	end)
	it("states: loading and failed keep the top colliders off, the visible bowl solid", function()
		for _, run in { loading, failed } do
			for _, name in TOP_COLLIDERS do
				expect(run.volcano[name].CanCollide).toBe(false)
			end
			expect(run.volcano.Bowl.CanCollide).toBe(true)
			expect(run.volcano.Column.CanCollide).toBe(true)
		end
	end)
	it("states: loaded and loading are never both off or both on", function()
		for _, name in TOP_COLLIDERS do
			expect(loadedVolcano[name].CanCollide).toBe(true)
			expect(loadingVolcano[name].CanCollide).toBe(false)
			expect(loadedVolcano[name]:GetAttribute("MeshCollider")).toBe(M)
		end
	end)
	it("the switch flips the whole top with the rest", function()
		local run = toggled
		local MeshSwap = run.rt:require(run.rt.game:GetService("ServerScriptService").Server.MeshSwap)
		MeshSwap.setMeshCollision(run.map, M, false)
		for _, name in TOP_COLLIDERS do
			expect(run.volcano[name].CanCollide).toBe(false)
		end
		MeshSwap.setMeshCollision(run.map, M, true)
		for _, name in TOP_COLLIDERS do
			expect(run.volcano[name].CanCollide).toBe(true)
		end
	end)
	it(
		"keeps the slide head enterable: the basin floor sits under the slide's first point, so the ride starts in the open",
		function()
			local head = WorldLayout.SLIDE_PATH[1]
			expect(head[2] >= BASIN and head[2] - BASIN <= 1).toBe(true)
			expect(math.sqrt(head[1] ^ 2 + head[3] ^ 2) < FP.domeCentre).toBe(true)
		end
	)
end)
