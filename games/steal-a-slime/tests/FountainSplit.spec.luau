--!nocheck
-- FEATURES.FountainSplit (default on; draft for Merijn's fountain collision choice (a), CONTRACT.md §28): the
-- slime_fountain mesh cut into 5 pieces (shared/modeling-kit/models/slime_fountain_split.py), the four tower pieces
-- PreciseConvexDecomposition, the slide piece decor. Pure data first (tris, bbox, offsets, COLLISION), then the live
-- server in the fake runtime with the flag off (= main's single mesh), on, and on with a piece failing to load.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local Runtime = require("../tools/livetest/Runtime")
local SlideColliders = require("../src/shared/SlideColliders")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local M = "slime_fountain"
local PCD = "PreciseConvexDecomposition"
local TOWER = { "fountain_split_basin", "fountain_split_dome", "fountain_split_eave", "fountain_split_silo" }
local SLIDE = "fountain_split_slide"
local KIT_OUT = "../../shared/modeling-kit/out"
local EPS = 2e-3 -- sizes and offsets are rounded to 3 decimals

local split = serde.decode("json", fs.readFile(`{KIT_OUT}/fountain_split.json`))
local whole = serde.decode("json", fs.readFile(`{KIT_OUT}/slime_fountain.stats.json`))

describe("FountainSplit data", function()
	it("is behind FEATURES.FountainSplit, default on", function()
		expect(Config.FEATURES.FountainSplit).toBe(true)
	end)
	it("the slide is PCD behind FEATURES.SlidePCD, default on", function()
		expect(Config.FEATURES.SlidePCD).toBe(true)
	end)
	it("lists the 5 pieces, all uploaded, none in the world slot list", function()
		expect(#MeshAssets.FOUNTAIN_SPLIT).toBe(5)
		for _, name in MeshAssets.FOUNTAIN_SPLIT do
			expect(MeshAssets.meshId(name) ~= nil).toBe(true)
			expect(table.find(MeshAssets.NAMES, name)).toBe(nil)
			expect(split.pieces[string.gsub(name, "^fountain_split_", "")] ~= nil).toBe(true)
		end
	end)
	it("splits the shipped mesh: the piece triangles add up to the whole", function()
		local sum = 0
		for _, piece in split.pieces do
			sum += piece.tris
		end
		expect(sum).toBe(whole.tris)
		expect(split.tris).toBe(whole.tris)
	end)
	it("MeshAssets size and offset are the split script's numbers", function()
		for _, name in MeshAssets.FOUNTAIN_SPLIT do
			local piece = split.pieces[string.gsub(name, "^fountain_split_", "")]
			local entry = MeshAssets.get(name)
			for i = 1, 3 do
				expect(math.abs(entry.size[i] - piece.size_roblox[i]) <= EPS).toBe(true)
				expect(math.abs(entry.offset[i] - piece.offset_roblox[i]) <= EPS).toBe(true)
			end
		end
	end)
	it("the offsets reconstruct the original bbox", function()
		local native = MeshAssets.get(M).size
		local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
		for _, name in MeshAssets.FOUNTAIN_SPLIT do
			local entry = MeshAssets.get(name)
			for i = 1, 3 do
				lo[i] = math.min(lo[i], entry.offset[i] - entry.size[i] / 2)
				hi[i] = math.max(hi[i], entry.offset[i] + entry.size[i] / 2)
			end
		end
		for i = 1, 3 do
			-- the whole mesh is centred on its bbox centre: -native/2 .. +native/2 on every axis
			expect(math.abs(lo[i] + native[i] / 2) <= EPS).toBe(true)
			expect(math.abs(hi[i] - native[i] / 2) <= EPS).toBe(true)
		end
	end)
	it(
		"the tower pieces and the slide are PreciseConvexDecomposition (the slide only with FEATURES.SlidePCD)",
		function()
			for _, name in TOWER do
				expect(MeshAssets.collision(name)).toBe(PCD)
			end
			expect(MeshAssets.collision(SLIDE)).toBe(PCD)
			expect(MeshAssets.collision(M)).toBe(nil) -- the whole mesh stays decor
		end
	)
	it("keeps the pieces out of the client preload list", function()
		local ids = {}
		for _, id in MeshAssets.allMeshIds() do
			ids[id] = true
		end
		for _, name in MeshAssets.FOUNTAIN_SPLIT do
			expect(ids[MeshAssets.meshId(name)]).toBe(nil)
		end
		expect(ids[MeshAssets.meshId(M)]).toBe(true)
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-fsplit-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local WHOLE_ID = MeshAssets.meshId(M)
local PIECE_BY_ID = {}
for _, name in MeshAssets.FOUNTAIN_SPLIT do
	PIECE_BY_ID[MeshAssets.meshId(name)] = name
end

-- CanCollide of every MeshCollider part (and the solid stand-ins) right now.
local function collision(volcano): { [string]: boolean }
	local out = {}
	for _, d in volcano.Parent:GetDescendants() do
		if d:IsA("BasePart") and (d:GetAttribute("MeshCollider") == M or d:GetAttribute("MeshStandIn") == M) then
			out[d:GetFullName()] = d.CanCollide
		end
	end
	return out
end

-- flag: FEATURES.FountainSplit in the built place's Config; failId: a mesh id whose CreateMeshPartAsync throws.
local function boot(flag: boolean, failId: string?, slidePcd: boolean?)
	local rt
	local asked = {} -- { meshId, fidelity, state = collision while that fetch was in flight }
	rt = Runtime.new(path, {
		createMeshPart = function(meshId, options)
			table.insert(asked, {
				meshId = meshId,
				fidelity = options and options.CollisionFidelity,
				state = collision(rt.workspace.Map.Volcano),
			})
			if meshId == failId then
				error(`livetest: CreateMeshPartAsync({meshId}) failed`)
			end
			local part = roblox.Instance.new("MeshPart")
			if options and options.CollisionFidelity then
				part.CollisionFidelity = options.CollisionFidelity
			end
			return part
		end,
	})
	local config = rt.game:GetService("ReplicatedStorage").Shared.Config
	-- scripts/test-flags forces every flag in the built Config, so set the line either way
	local patched, n = string.gsub(config.Source, "FountainSplit = %a+,", `FountainSplit = {flag},`)
	assert(n == 1, "FEATURES.FountainSplit line not found in Config")
	patched = string.gsub(patched, "SlidePCD = %a+,", `SlidePCD = {slidePcd ~= false},`)
	config.Source = patched
	rt:boot()
	rt:advance(2)
	local map = rt.workspace.Map
	return { rt = rt, map = map, volcano = map.Volcano, slot = map.Volcano.FountainMesh, asked = asked }
end

local off = boot(false)
local on = boot(true)
local broken = boot(true, MeshAssets.meshId("fountain_split_dome")) -- one piece fails to load
local slideBroken = boot(true, MeshAssets.meshId(SLIDE)) -- the slide piece failing counts too
local slideOff = boot(true, nil, false) -- FEATURES.SlidePCD off: decor slide, every box
require("@lune/fs").removeFile(path)

local function askedFor(run, meshId)
	local n = 0
	for _, call in run.asked do
		if call.meshId == meshId then
			n += 1
		end
	end
	return n
end

local function pieces(run): { [string]: any }
	local out = {}
	for _, name in MeshAssets.FOUNTAIN_SPLIT do
		out[name] = run.slot:FindFirstChild(name)
	end
	return out
end

local function expectAll(state, value: boolean)
	local n = 0
	for _, can in state do
		n += 1
		expect(can).toBe(value)
	end
	expect(n > 5).toBe(true)
end

-- main's collision once the whole mesh landed: colliders on, stand-ins off (FountainCollider.spec LOADED)
local function expectWholeMeshState(run)
	for fullName, can in collision(run.volcano) do
		expect(can).toBe(string.find(fullName, "Collider", 1, true) ~= nil)
	end
end

describe("FountainSplit off (the shipped default) is main", function()
	it("boots clean", function()
		expect(#off.rt.errors).toBe(0)
	end)
	it("places the single slime_fountain mesh and no piece", function()
		local mesh = off.slot:FindFirstChild("Mesh")
		expect(mesh ~= nil).toBe(true)
		expect(mesh.CanCollide).toBe(false)
		for _, piece in pieces(off) do
			expect(piece).toBe(nil)
		end
	end)
	it("never asks for a piece mesh", function()
		expect(askedFor(off, WHOLE_ID)).toBe(1)
		for id in PIECE_BY_ID do
			expect(askedFor(off, id)).toBe(0)
		end
	end)
	it("keeps the hand-placed colliders on and the stand-ins off", function()
		expectWholeMeshState(off)
	end)
end)

describe("FountainSplit on", function()
	it("boots clean", function()
		expect(#on.rt.errors).toBe(0)
	end)
	it("places the 5 pieces instead of the single mesh", function()
		expect(on.slot:FindFirstChild("Mesh")).toBe(nil)
		expect(askedFor(on, WHOLE_ID)).toBe(0)
		for name, piece in pieces(on) do
			expect(piece ~= nil).toBe(true)
			expect(piece.Anchored).toBe(true)
			expect(piece.CanQuery).toBe(false)
			expect(piece.CanTouch).toBe(false)
			expect(askedFor(on, MeshAssets.meshId(name))).toBe(1)
		end
	end)
	it("makes the 4 tower pieces and the slide solid PCD (the slide with FEATURES.SlidePCD)", function()
		for _, name in TOWER do
			local piece = on.slot[name]
			expect(piece.CanCollide).toBe(true)
			expect(piece.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.PreciseConvexDecomposition)
		end
		local slideSolid = true -- boot(true) leaves FEATURES.SlidePCD on in the built place
		expect(on.slot[SLIDE].CanCollide).toBe(slideSolid)
		for _, call in on.asked do
			local name = PIECE_BY_ID[call.meshId]
			if name then
				expect(call.fidelity).toBe(
					if name ~= SLIDE or slideSolid
						then roblox.Enum.CollisionFidelity.PreciseConvexDecomposition
						else nil
				)
			end
		end
	end)
	it("sits each piece where the whole mesh drew it: slot centre + offset, native size", function()
		local slot = on.slot
		for name, piece in pieces(on) do
			local entry = MeshAssets.get(name)
			local want = slot.CFrame * roblox.CFrame.new(entry.offset[1], entry.offset[2], entry.offset[3])
			expect((piece.CFrame.Position - want.Position).Magnitude < 1e-3).toBe(true)
			expect(piece.Size.X).toBeCloseTo(entry.size[1], 1e-3)
			expect(piece.Size.Y).toBeCloseTo(entry.size[2], 1e-3)
			expect(piece.Size.Z).toBeCloseTo(entry.size[3], 1e-3)
			-- the same turn as the single mesh (MeshAssets.IMPORT_YAW about the slot's vertical axis)
			local look = piece.CFrame.LookVector
			local ref = (slot.CFrame * roblox.CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)).LookVector
			expect((look - ref).Magnitude < 1e-4).toBe(true)
		end
		-- the slot box is the whole mesh's native size, so the scale is 1 and the stand-on-the-bottom drop is 0
		local native = MeshAssets.get(M).size
		expect(slot.Size.X).toBeCloseTo(native[1], 1e-3)
		expect(slot.Size.Y).toBeCloseTo(native[2], 1e-3)
		expect(slot.Size.Z).toBeCloseTo(native[3], 1e-3)
		expect(WorldLayout.FOUNTAIN_MESH_SIZE[2]).toBeCloseTo(native[2], 1e-3)
	end)
	it("keeps the stand-ins solid while the pieces load, then turns stand-ins and colliders all off", function()
		for _, call in on.asked do
			if PIECE_BY_ID[call.meshId] then
				-- still loading: colliders off, the visible stand-ins collide (some)
				local anyOn, colliderOn = false, false
				for fullName, can in call.state do
					anyOn = anyOn or can
					colliderOn = colliderOn or (can and string.find(fullName, "Collider", 1, true) ~= nil)
				end
				expect(anyOn).toBe(true)
				expect(colliderOn).toBe(false)
			end
		end
		local volcano = on.volcano
		for _, name in { "BasinCollider", "TrimCollider", "SiloCollider", "TopCollider1" } do
			expect(volcano[name].CanCollide).toBe(false)
		end
		-- stand-ins and colliders alike: the PCD pieces are the tower's collision now
		expectAll(collision(volcano), false)
	end)
	it(
		"retires the Floor / Joint / Post / Brace boxes the PCD slide replaces, keeps Fill, JointFill and Skirt",
		function()
			local kinds = {}
			for _, part in on.volcano.SlideColliders:GetChildren() do
				local kind = part:GetAttribute("FountainCollider")
				kinds[kind] = (kinds[kind] or 0) + 1
			end
			for kind in SlideColliders.PCD_RETIRED do
				expect(kinds[kind]).toBe(nil)
			end
			expect(kinds.Fill > 0 and kinds.Skirt > 0).toBe(true)
			local want = SlideColliders.all(
				WorldLayout.SLIDE_PATH,
				WorldLayout.slidePath(WorldLayout.KIT_SLIDE_SAMPLES),
				Config.FEATURES.SlideCollision,
				true
			)
			local fills = 0
			for _, spec in want do
				fills += if spec.kind == "Fill" then 2 else 0 -- the roof wedges
			end
			expect(#on.volcano.SlideColliders:GetChildren()).toBe(#want + fills)
		end
	)
	it("keeps every box when the SlidePCD flag is off in the built place", function()
		local want = SlideColliders.all(
			WorldLayout.SLIDE_PATH,
			WorldLayout.slidePath(WorldLayout.KIT_SLIDE_SAMPLES),
			Config.FEATURES.SlideCollision,
			false
		)
		local fills = 0
		for _, spec in want do
			fills += if spec.kind == "Fill" then 2 else 0 -- the roof wedges
		end
		expect(#slideOff.volcano.SlideColliders:GetChildren()).toBe(#want + fills)
		expect(slideOff.slot[SLIDE].CanCollide).toBe(false)
	end)
	it("leaves the slide's own colliders on", function()
		local slide = on.volcano:FindFirstChild("SlideColliders")
		expect(slide ~= nil).toBe(true)
		local n = 0
		for _, part in slide:GetChildren() do
			n += 1
			expect(part.CanCollide).toBe(true)
		end
		expect(n > 0).toBe(true)
	end)
	it("is idempotent: a second MeshSwap.apply places nothing", function()
		local MeshSwap = on.rt:require(on.rt.game:GetService("ServerScriptService").Server.MeshSwap)
		local before = #on.slot:GetChildren()
		MeshSwap.apply()
		expect(#on.slot:GetChildren()).toBe(before)
	end)
end)

describe("FountainSplit on, a piece fails to load: the single mesh and the colliders stay", function()
	for label, run in { ["tower piece (dome)"] = broken, ["decor piece (slide)"] = slideBroken } do
		it(`{label}: places the whole mesh, no piece`, function()
			expect(run.slot:FindFirstChild("Mesh") ~= nil).toBe(true)
			for _, piece in pieces(run) do
				expect(piece).toBe(nil)
			end
			expect(askedFor(run, WHOLE_ID)).toBe(1)
		end)
		it(`{label}: the hand-placed colliders collide, nothing is left without collision`, function()
			expectWholeMeshState(run)
			local colliders = 0
			for fullName, can in collision(run.volcano) do
				if string.find(fullName, "Collider", 1, true) then
					colliders += 1
					expect(can).toBe(true)
				end
			end
			expect(colliders >= 4).toBe(true)
		end)
	end
end)
