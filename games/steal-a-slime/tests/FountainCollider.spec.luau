--!nocheck
-- Fountain collision in the fake runtime, both MeshSwap outcomes. The fountain
-- mesh is visual-only, so one invisible BasinCollider (flush with BasinRim)
-- is its collision. Mesh loaded: the hidden stand-ins stop colliding. Mesh
-- still loading / failed: the visible stand-ins keep colliding, all inside the
-- collider. Either way no invisible part but the collider can trip a player.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local M = "slime_fountain"
local SOLID_STAND_INS = { "Rock1", "BasinRim", "Column", "Bowl" }

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

-- Upright cylinder (Size = height, d, d; rolled 90): radius and top height.
local function radius(part): number
	return part.Size.Y / 2
end
local function top(part): number
	return part.CFrame.Position.Y + part.Size.X / 2
end

local function expectCollider(volcano)
	local c = volcano:FindFirstChild("BasinCollider")
	expect(c ~= nil).toBe(true)
	expect(c.Shape).toBe(roblox.Enum.PartType.Cylinder)
	expect(c.Anchored).toBe(true)
	expect(c.CanCollide).toBe(true)
	expect(c.Transparency).toBe(1)
	expect(c.CFrame.Position.Y - c.Size.X / 2).toBeCloseTo(0)
	-- Flush with the visible rim: same footprint, same top.
	expect(radius(c)).toBeCloseTo(radius(volcano.BasinRim))
	expect(top(c)).toBeCloseTo(top(volcano.BasinRim))
end

describe("fountain collider, mesh loaded", function()
	it("swaps the mesh in as visual-only", function()
		local mesh = loadedVolcano.FountainMesh:FindFirstChild("Mesh")
		expect(mesh ~= nil).toBe(true)
		expect(mesh.CanCollide).toBe(false)
		expect(mesh.Anchored).toBe(true)
	end)
	it("keeps one anchored invisible cylinder at the basin rim", function()
		expectCollider(loadedVolcano)
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
	it("leaves no invisible step around the base (only BasinCollider collides unseen)", function()
		expect(invisibleColliders(loadedMap)).toEqual({ "BasinCollider" })
	end)
end)

describe("fountain collider, mesh loading or failed", function()
	it("keeps the primitive placeholder (no mesh)", function()
		expect(failedVolcano.FountainMesh:FindFirstChild("Mesh")).toBe(nil)
	end)
	it("keeps one anchored invisible cylinder at the basin rim", function()
		expectCollider(failedVolcano)
	end)
	it("keeps the visible stand-ins solid", function()
		for _, name in SOLID_STAND_INS do
			local part = failedVolcano[name]
			expect(part.Transparency < 1).toBe(true)
			expect(part.CanCollide).toBe(true)
		end
	end)
	it("leaves no invisible step around the base (base stand-ins sit inside the collider)", function()
		expect(invisibleColliders(failedMap)).toEqual({ "BasinCollider" })
		local c = failedVolcano.BasinCollider
		for _, name in { "Rock1", "BasinRim" } do
			local part = failedVolcano[name]
			expect(radius(part) <= radius(c) + 1e-3).toBe(true)
			expect(top(part) <= top(c) + 1e-3).toBe(true)
		end
	end)
end)
