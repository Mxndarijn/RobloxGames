--!nocheck
-- WorldProps skins keep their mesh proportions (v27 gate B3). MeshSwap used
-- to fit Map.LeaderboardBoard and Map.ShopStand to their Model's bounding box
-- per axis (board 0.711 / 0.978 / 0.317 = anisotropy 3.08, stand 1.17).
-- Booted in the fake runtime with every mesh upload answered, each skin is
-- native x one scale (WorldLayout.meshSize), as tall as its Model and
-- standing on the Model's bottom.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
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

-- Half the vertical extent of a part, turned by its CFrame (an upright cylinder is tall along its X).
local function halfHeight(part): number
	local cf, size = part.CFrame, part.Size
	return (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z)
		/ 2
end

-- Lowest Y of the Model's own parts (the Mesh child excluded).
local function modelBottom(model): number
	local lo = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Mesh" then
			lo = math.min(lo, d.CFrame.Position.Y - halfHeight(d))
		end
	end
	return lo
end

-- The stands WorldProps places: the single ShopStand, or the Item + Upgrade stands with FEATURES.WorldShops on.
local STANDS = if Config.FEATURES.WorldShops
	then { Constants.SHOP_STAND_ITEM, Constants.SHOP_STAND_UPGRADE }
	else { Constants.SHOP_STAND }

describe("WorldProps skins keep their mesh proportions (gate B3)", function()
	local names = { Constants.LEADERBOARD_BOARD }
	table.move(STANDS, 1, #STANDS, 2, names)
	for _, name in names do
		local stand = WorldLayout.SHOP_STANDS[name]
		local meshName = if stand then stand.mesh else WorldLayout.PROP_MESHES[name]
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
					top = math.max(top, d.CFrame.Position.Y + halfHeight(d))
				end
			end
			expect(mesh.Size.Y).toBeCloseTo(top - bottom, EPS)
			expect(mesh.CFrame.Position.Y - mesh.Size.Y / 2).toBeCloseTo(bottom, EPS)
		end)
	end

	for _, standName in STANDS do
		it(`puts the {standName} SHOP text on its own skin's sign face (v29 B4)`, function()
			local model = map:FindFirstChild(standName)
			local sign = model:FindFirstChild("Sign")
			local stand = WorldLayout.SHOP_STANDS[standName]
			local native = (MeshAssets.get(stand.mesh) :: any).size
			local face = stand.face
			-- Roblox orients Model:GetBoundingBox to the pivot (the fake runtime's is
			-- axis-aligned), so the skin's box is rebuilt here in the pivot's frame.
			local inv = model:GetPivot():Inverse()
			local lo, hi = math.huge, -math.huge
			local bottom, top, front, back = math.huge, -math.huge, math.huge, -math.huge
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "Mesh" then
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local c = inv:PointToWorldSpace(
									d.CFrame:PointToWorldSpace(
										roblox.Vector3.new(sx * d.Size.X / 2, sy * d.Size.Y / 2, sz * d.Size.Z / 2)
									)
								)
								lo, hi = math.min(lo, c.X), math.max(hi, c.X)
								bottom, top = math.min(bottom, c.Y), math.max(top, c.Y)
								front, back = math.min(front, c.Z), math.max(back, c.Z)
							end
						end
					end
				end
			end
			local k = (top - bottom) / native[2]
			-- the skin stands on the box bottom, its front (-Z) on the box front
			local meshZ = front + native[3] * k / 2
			local text =
				inv:PointToWorldSpace(sign.CFrame:PointToWorldSpace(roblox.Vector3.new(0, 0, -sign.Size.Z / 2)))
			local kitFace = meshZ - face.front * k -- kit +Z is local -Z
			if math.abs(text.Z - kitFace) > 0.05 then
				error(`SHOP text at z {text.Z}, sign face at {kitFace}`)
			end
			expect(math.abs(text.X - (lo + hi) / 2 - face.x * k) <= 0.05).toBe(true)
			expect(math.abs(text.Y - bottom - face.y * k) <= 0.05).toBe(true)
			expect(sign.Size.X).toBeCloseTo(face.width * k, 0.05)
			expect(sign.Size.Y).toBeCloseTo(face.height * k, 0.05)
			-- the text faces out of the skin's front
			expect(inv:VectorToWorldSpace(sign.CFrame.LookVector).Z < -0.99).toBe(true)
		end)
	end

	describe("Top Earners text is on the board's own face (v30 C7)", function()
		local model = map:FindFirstChild(Constants.LEADERBOARD_BOARD)
		local board = model:FindFirstChild("Board")
		local gui = board and board:FindFirstChild("BoardGui")
		local mesh = model:FindFirstChild("Mesh")
		local inv = model:GetPivot():Inverse()
		local native = (MeshAssets.get("phoenix_top_earners_board") :: any).size
		local k = mesh.Size.Y / native[2]
		local face = WorldLayout.DEX_FACE

		it("hangs the SurfaceGui on the board part, front face, adornee set", function()
			expect(gui ~= nil).toBe(true)
			expect(gui.ClassName).toBe("SurfaceGui")
			expect(gui.Parent).toBe(board)
			expect(gui.Adornee).toBe(board)
			expect(gui.Face).toBe(roblox.Enum.NormalId.Front)
			expect(model.PrimaryPart ~= nil).toBe(true)
		end)

		it("has no slab: no part but the board carries a SurfaceGui, and none is sized like a slab", function()
			for _, d in model:GetDescendants() do
				if d:IsA("SurfaceGui") then
					expect(d.Parent).toBe(board)
				end
			end
			local seen = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Board" then
					seen += 1
					-- thin face panel, not the old 14 x 16 x 0.8 slab
					expect(d.Size.Z <= 0.05).toBe(true)
				end
			end
			expect(seen).toBe(1)
		end)

		it("is the skin's front cream panel: size, place and orientation", function()
			expect(board.Size.X).toBeCloseTo(face.width * k, 0.02)
			expect(board.Size.Y).toBeCloseTo(face.height * k, 0.02)
			local c = inv:PointToWorldSpace(board.CFrame.Position)
			local meshC = inv:PointToWorldSpace(mesh.CFrame.Position)
			local meshBottom = meshC.Y - mesh.Size.Y / 2
			-- kit front +Z is the Model's -Z (x mirrors with it)
			-- (the fake runtime's bounding box is axis-aligned, so x is read in the
			-- pivot's own frame, whose build x = 0 is the skin's box centre)
			expect(c.X).toBeCloseTo(-face.x * k, 0.02)
			expect(c.Y - meshBottom).toBeCloseTo(face.y * k, 0.02)
			-- the skin's front is flush with the Model's front (the Collider's)
			local collider = model:FindFirstChild("Collider")
			local front = inv:PointToWorldSpace(collider.CFrame.Position).Z - collider.Size.Z / 2
			local kitFace = front + mesh.Size.Z / 2 - face.front * k
			expect(math.abs(c.Z - kitFace) < 0.05).toBe(true)
			-- the Front face (and the text) looks out of the skin's front, -Z
			expect(inv:VectorToWorldSpace(board.CFrame.LookVector).Z < -0.99).toBe(true)
			-- behind the skin's front, so the mesh does not cover it
			expect(c.Z > front).toBe(true)
		end)
	end)

	it("WorldLayout.meshSize is native x one scale (the helper WorldProps uses)", function()
		local native = (MeshAssets.get("phoenix_top_earners_board") :: any).size
		local size = WorldLayout.meshSize("phoenix_top_earners_board", 0.5)
		for i = 1, 3 do
			expect(size[i]).toBeCloseTo(native[i] * 0.5, 1e-9)
		end
	end)
end)
