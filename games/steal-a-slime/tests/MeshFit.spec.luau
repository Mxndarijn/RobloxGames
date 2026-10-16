--!nocheck
-- Every mesh MeshSwap puts in the world keeps its native proportions (one
-- uniform scale, MeshAssets.fit), including the WorldProps-built Models
-- (Map.ShopStand, Map.LeaderboardBoard): their bounding box is the primitive
-- prop's, and stretching the mesh to it squashed the board 3.08:1 and the
-- shop stand 1.17:1 (Phoenix gate B3). Booted in the fake runtime with every
-- CreateMeshPartAsync answered, so every uploaded slot swaps.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Constants = require("../src/shared/Constants")
local MeshAssets = require("../src/shared/MeshAssets")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local REL = 1e-3 -- float32 sizes

local function uniform(size: { number }, native: { number }): (boolean, string)
	local a, b, c = size[1] / native[1], size[2] / native[2], size[3] / native[3]
	local ok = math.abs(a - b) <= REL * a and math.abs(a - c) <= REL * a
	return ok, string.format("%.4f %.4f %.4f", a, b, c)
end

describe("MeshAssets.fit", function()
	it("fits the native box at one scale, limited by the tightest axis", function()
		local native = MeshAssets.get("phoenix_top_earners_board").size
		local size, scale, drop = MeshAssets.fit("phoenix_top_earners_board", { 30, 10, 30 })
		expect(scale).toBeCloseTo(math.min(30 / native[1], 10 / native[2], 30 / native[3]))
		expect((uniform(size, native))).toBe(true)
		for k = 1, 3 do
			expect(size[k] <= ({ 30, 10, 30 })[k] + 1e-9).toBe(true)
		end
		expect(drop).toBeCloseTo((10 - size[2]) / 2)
	end)
	it("is exact on a WorldLayout slot (native x scale): no shrink, no drop", function()
		local native = MeshAssets.get("ranch_well").size
		local size, scale, drop = MeshAssets.fit("ranch_well", { native[1] * 1.2, native[2] * 1.2, native[3] * 1.2 })
		expect(scale).toBeCloseTo(1.2)
		expect(size[2]).toBeCloseTo(native[2] * 1.2)
		expect(drop).toBeCloseTo(0)
	end)
	it("keeps the box for a name without a native size", function()
		local size, scale, drop = MeshAssets.fit("no_such_mesh", { 1, 2, 3 })
		expect(size).toEqual({ 1, 2, 3 })
		expect(scale).toBe(nil)
		expect(drop).toBe(0)
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-meshfit-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local rt = Runtime.new(path, {
	createMeshPart = function(_meshId)
		return roblox.Instance.new("MeshPart")
	end,
})
rt:boot()
rt:advance(2)

-- Every swapped mesh in the world: { mesh, target, name }.
local swapped = {}
for _, rootName in { "Map", "Plots" } do
	local root = rt.workspace:FindFirstChild(rootName)
	for _, d in root:GetDescendants() do
		if d.Name == "Mesh" and d:IsA("MeshPart") then
			local target = d.Parent
			table.insert(swapped, { mesh = d, target = target, name = target:GetAttribute("MeshAsset") })
		end
	end
end

describe("MeshSwap uniform scale (live boot, every upload answered)", function()
	it("swaps every uploaded MeshAsset slot", function()
		local slots = 0
		for _, rootName in { "Map", "Plots" } do
			for _, d in rt.workspace[rootName]:GetDescendants() do
				local name = d:GetAttribute("MeshAsset")
				if name and MeshAssets.meshId(name) and (d:IsA("BasePart") or d:IsA("Model")) then
					slots += 1
				end
			end
		end
		expect(slots > 0).toBe(true)
		expect(#swapped).toBe(slots)
	end)
	it("keeps every swapped mesh at its native proportions", function()
		local bad = {}
		for _, s in swapped do
			local native = MeshAssets.get(s.name).size
			local size = s.mesh.Size
			local ok, ratios = uniform({ size.X, size.Y, size.Z }, native)
			if not ok then
				table.insert(bad, `{s.target:GetFullName()} ({s.name}) {ratios}`)
			end
		end
		expect(bad).toEqual({})
	end)
	it("routes every WorldProps-built mesh at native proportions, on its bottom (MeshSize or the fit)", function()
		local seen = 0
		for name, mesh in WorldLayout.PROP_MESHES do
			local model = rt.workspace.Map:FindFirstChild(name)
			expect(model ~= nil).toBe(true)
			expect(model:GetAttribute("MeshAsset")).toBe(mesh)
			local m = model:FindFirstChild("Mesh")
			expect(m ~= nil).toBe(true)
			seen += 1
			-- The box as MeshSwap saw it (all parts but the mesh).
			m.Parent = nil
			local cf, box = model:GetBoundingBox()
			m.Parent = model
			local native = MeshAssets.get(mesh).size
			local ok, ratios = uniform({ m.Size.X, m.Size.Y, m.Size.Z }, native)
			expect(ok).toBe(true)
			-- The old stretch would have been off by more than 1 %: this test bites.
			local stretched = uniform({ box.X, box.Y, box.Z }, native)
			expect(stretched).toBe(false)
			local rel = cf:ToObjectSpace(m.CFrame)
			expect(rel.Position.X).toBeCloseTo(0, 3)
			expect(rel.Position.Y - m.Size.Y / 2).toBeCloseTo(-box.Y / 2, 3)
			local fixed = model:GetAttribute("MeshSize")
			if typeof(fixed) == "Vector3" then
				-- WorldProps MeshSize (gate B3, tests/PropMesh.spec): as tall as
				-- the Model, front (-Z) face on the box's front.
				expect(m.Size.Y).toBeCloseTo(box.Y, 3)
				expect(rel.Position.Z - m.Size.Z / 2).toBeCloseTo(-box.Z / 2, 3)
			else
				local fits = m.Size.X <= box.X + 1e-3 and m.Size.Y <= box.Y + 1e-3 and m.Size.Z <= box.Z + 1e-3
				expect(fits).toBe(true)
				-- one axis touches the box (largest uniform fit)
				local touch = math.max(m.Size.X / box.X, m.Size.Y / box.Y, m.Size.Z / box.Z)
				expect(touch).toBeCloseTo(1, 3)
				expect(rel.Position.Z).toBeCloseTo(0, 3)
			end
			if not ok then
				print(name, ratios)
			end
		end
		expect(seen).toBe(2)
		expect(WorldLayout.PROP_MESHES[Constants.SHOP_STAND] ~= nil).toBe(true)
		expect(WorldLayout.PROP_MESHES[Constants.LEADERBOARD_BOARD] ~= nil).toBe(true)
	end)
end)
