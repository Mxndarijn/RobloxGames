--!nocheck
-- WorldProps skins keep their mesh proportions (v27 gate B3). MeshSwap used
-- to fit Map.LeaderboardBoard and Map.ShopStand to their Model's bounding box
-- per axis (board 0.711 / 0.978 / 0.317 = anisotropy 3.08, stand 1.17).
-- Booted in the fake runtime with every mesh upload answered, each skin is
-- native x one scale (WorldLayout.meshSize), as tall as its Model and
-- standing on the Model's bottom.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Constants = require("../src/shared/Constants")
local MeshAssets = require("../src/shared/MeshAssets")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local EPS = 1e-3 -- Part sizes are float32

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-propmesh-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {
	createMeshPart = function(_meshId)
		return roblox.Instance.new("MeshPart")
	end,
})
rt:boot()
rt:advance(2)
require("@lune/fs").removeFile(path)
local map = rt.workspace:FindFirstChild("Map")

-- Per-axis scale of a mesh against its native size, and max / min of those.
local function anisotropy(size, native): (number, { number })
	local s = { size.X / native[1], size.Y / native[2], size.Z / native[3] }
	return math.max(s[1], s[2], s[3]) / math.min(s[1], s[2], s[3]), s
end

-- Lowest Y of the Model's own parts (the Mesh child excluded).
local function modelBottom(model): number
	local lo = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Mesh" then
			lo = math.min(lo, d.CFrame.Position.Y - d.Size.Y / 2)
		end
	end
	return lo
end

describe("WorldProps skins keep their mesh proportions (gate B3)", function()
	for _, name in { Constants.LEADERBOARD_BOARD, Constants.SHOP_STAND } do
		local meshName = WorldLayout.PROP_MESHES[name]
		local native = (MeshAssets.get(meshName) :: any).size

		it(`Map.{name} ({meshName}) has anisotropy 1`, function()
			local model = map:FindFirstChild(name)
			expect(model ~= nil).toBe(true)
			local mesh = model:FindFirstChild("Mesh")
			expect(mesh ~= nil).toBe(true)
			local aniso, s = anisotropy(mesh.Size, native)
			if math.abs(aniso - 1) > EPS then
				error(string.format("%s scale %.4f / %.4f / %.4f, anisotropy %.4f", name, s[1], s[2], s[3], aniso))
			end
		end)

		it(`Map.{name} skin is as tall as the Model and stands on its bottom`, function()
			local model = map:FindFirstChild(name)
			local mesh = model:FindFirstChild("Mesh")
			local fixed = model:GetAttribute("MeshSize")
			expect(typeof(fixed)).toBe("Vector3")
			expect(mesh.Size.X).toBeCloseTo(fixed.X, EPS)
			expect(mesh.Size.Y).toBeCloseTo(fixed.Y, EPS)
			expect(mesh.Size.Z).toBeCloseTo(fixed.Z, EPS)
			local bottom = modelBottom(model)
			local top = -math.huge
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "Mesh" then
					top = math.max(top, d.CFrame.Position.Y + d.Size.Y / 2)
				end
			end
			expect(mesh.Size.Y).toBeCloseTo(top - bottom, EPS)
			expect(mesh.CFrame.Position.Y - mesh.Size.Y / 2).toBeCloseTo(bottom, EPS)
		end)
	end

	it("WorldLayout.meshSize is native x one scale (the helper WorldProps uses)", function()
		local native = (MeshAssets.get("phoenix_top_earners_board") :: any).size
		local size = WorldLayout.meshSize("phoenix_top_earners_board", 0.5)
		for i = 1, 3 do
			expect(size[i]).toBeCloseTo(native[i] * 0.5, 1e-9)
		end
	end)
end)
