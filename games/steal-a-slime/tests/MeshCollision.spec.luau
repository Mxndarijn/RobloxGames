--!nocheck
-- Real mesh collision (Merijn #10, #11): the big slimes stacked at the fountain top
-- (slime_fountain_emerge) are solid, so a player is pushed out of them or stands on top,
-- never inside. MeshSwap passes MeshAssets.COLLISION to CreateMeshPartAsync (the only place a
-- fidelity sticks on a script-made MeshPart) and turns CanCollide on for exactly those meshes;
-- every other swapped mesh stays decor (CanCollide off). docs/COLLISION.md has the rules.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local VALID = { Box = true, Hull = true, Default = true, PreciseConvexDecomposition = true }

describe("MeshAssets.COLLISION", function()
	it("names only uploaded meshes and real Enum.CollisionFidelity values", function()
		for name, fidelity in MeshAssets.COLLISION do
			expect(MeshAssets.meshId(name) ~= nil).toBe(true)
			expect(VALID[fidelity]).toBe(true)
			expect(MeshAssets.collision(name)).toBe(fidelity)
		end
	end)
	it("makes the shop stands solid with a hull (CONTRACT.md §27.2)", function()
		expect(MeshAssets.collision("ranch_shop_stand")).toBe("Hull")
	end)
	it("makes the fountain-top slimes solid with a hull (cheap, no standing in the gaps)", function()
		expect(MeshAssets.collision("slime_fountain_emerge")).toBe("Hull")
		expect(MeshAssets.collision("ranch_well")).toBe(nil) -- decor stays non-colliding
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-meshcol-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local asked = {} -- meshId -> the CollisionFidelity option CreateMeshPartAsync got
local rt = Runtime.new(path, {
	createMeshPart = function(meshId, options)
		asked[meshId] = options and options.CollisionFidelity
		local part = roblox.Instance.new("MeshPart")
		-- like the engine: the fidelity in the options is what the part has
		if options and options.CollisionFidelity then
			part.CollisionFidelity = options.CollisionFidelity
		end
		return part
	end,
})
rt:boot()
rt:advance(2)
require("@lune/fs").removeFile(path)

describe("MeshSwap collision in the live server", function()
	it("boots clean", function()
		expect(#rt.errors).toBe(0)
	end)
	it("asks CreateMeshPartAsync for the fidelity, and only for meshes that have one", function()
		local emerge = MeshAssets.meshId("slime_fountain_emerge")
		expect(asked[emerge]).toBe(roblox.Enum.CollisionFidelity.Hull)
		local solid = {}
		local want = 0
		for name, fidelity in MeshAssets.COLLISION do
			solid[MeshAssets.meshId(name)] = (roblox.Enum.CollisionFidelity :: any)[fidelity]
			want += 1
		end
		local count = 0
		for meshId, fidelity in asked do
			if fidelity ~= nil then
				count += 1
				expect(fidelity).toBe(solid[meshId])
			end
		end
		expect(count).toBe(want)
	end)
	it("the shop stands are solid Hull MeshParts (no extra collider boxes)", function()
		local names = if Config.FEATURES.WorldShops then { "ItemShopStand", "UpgradeShopStand" } else { "ShopStand" }
		for _, name in names do
			local mesh = rt.workspace.Map[name]:FindFirstChild("Mesh")
			expect(mesh ~= nil).toBe(true)
			expect(mesh.CanCollide).toBe(true)
			expect(mesh.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.Hull)
			expect(mesh.CanQuery).toBe(false)
		end
	end)
	it("the emerge slimes on the fountain are a solid Hull MeshPart", function()
		local mesh = rt.workspace.Map.Volcano.EmergeMesh:FindFirstChild("Mesh")
		expect(mesh ~= nil).toBe(true)
		expect(mesh.CanCollide).toBe(true)
		expect(mesh.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.Hull)
		expect(mesh.Anchored).toBe(true)
		expect(mesh.CanQuery).toBe(false)
		expect(mesh.CanTouch).toBe(false)
	end)
	it("every plot's merge vat is a solid Hull MeshPart over its disc (bug #16)", function()
		expect(MeshAssets.collision("merge_vat")).toBe("Hull")
		local vats = 0
		for _, plot in rt.workspace.Plots:GetChildren() do
			local vat = plot:FindFirstChild("MergeVat")
			local mesh = vat and vat:FindFirstChild("VatMesh")
			if mesh then
				vats += 1
				expect(mesh.CanCollide).toBe(true)
				expect(mesh.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.Hull)
				expect(mesh.CanQuery).toBe(false)
				expect(mesh.CanTouch).toBe(false)
			end
		end
		expect(vats > 0).toBe(true)
	end)
	it("every other swapped mesh stays decor: CanCollide off", function()
		local decor = 0
		for _, root in { rt.workspace.Map, rt.workspace.Plots } do
			for _, d in root:GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "Mesh" and d.Parent.Name ~= "EmergeMesh" then
					-- the shop stands are solid too (CONTRACT.md §27.2, Hull)
					local stand = d.Parent.Name == "ItemShopStand"
						or d.Parent.Name == "UpgradeShopStand"
						or d.Parent.Name == "ShopStand"
					expect(d.CanCollide).toBe(stand)
					if not stand then
						decor += 1
					end
				end
			end
		end
		expect(decor > 10).toBe(true)
	end)
end)
