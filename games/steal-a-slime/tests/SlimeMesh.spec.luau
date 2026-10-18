--!strict
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local SlimeMesh = require("../src/server/SlimeMesh")
local TestRunner = require("./TestRunner")

local MeshAssets = require("../src/shared/MeshAssets")
local SlimeLooks = require("../src/shared/SlimeLooks")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Stand-in for Archer's ModelFactory: counts builds and returns a fake Model.
local function fakeFactory()
	local factory = { built = {} :: { any } }
	function factory.build(slime: any): any
		local model = { Name = `Slime_{slime.id}`, destroyed = false }
		function model.Destroy(self: any)
			self.destroyed = true
		end
		table.insert(factory.built, model)
		return model
	end
	return factory
end

local function setup(loadAsset: (number) -> any)
	local factory = fakeFactory()
	local warnings: { string } = {}
	local requested: { number } = {}
	local mesh = SlimeMesh.new({
		factory = factory :: any,
		loadAsset = function(assetId: number): any
			table.insert(requested, assetId)
			return loadAsset(assetId)
		end,
		warn = function(message: string)
			table.insert(warnings, message)
		end,
	})
	return mesh, factory, warnings, requested
end

describe("SlimeMesh fallback", function()
	it("uses the procedural factory when LoadAsset errors", function()
		local mesh, factory, warnings, requested = setup(function(): any
			error("HTTP 403 (Forbidden)")
		end)
		expect(SlimeMesh.load(mesh)).toBe("Procedural")
		expect(mesh.look).toBe("Procedural")
		expect(mesh.template).toBeNil()
		expect(requested[1]).toBe(Config.SLIME_MESH_ASSET_ID)
		expect(#warnings).toBe(2) -- shared package + one line for the kit meshes
		expect(string.find(warnings[1], "403", 1, true) ~= nil).toBeTruthy()
		expect(string.find(warnings[2], "slime_gummy", 1, true) ~= nil).toBeTruthy()
		expect(next(mesh.kits)).toBeNil()

		local model = SlimeMesh.build(mesh, Fixtures.slime("a", 3)) :: any
		expect(model).toBe(factory.built[1])
		expect(model.Name).toBe("Slime_a")
		expect(#factory.built).toBe(1)
		expect(model.destroyed).toBe(false)
	end)

	it("falls back when the asset has no MeshPart", function()
		local destroyed = false
		local mesh, factory, warnings = setup(function(): any
			return {
				FindFirstChildWhichIsA = function(_self: any, _className: string, _recursive: boolean): any
					return nil
				end,
				Destroy = function()
					destroyed = true
				end,
			}
		end)
		expect(SlimeMesh.load(mesh)).toBe("Procedural")
		expect(destroyed).toBe(true)
		expect(string.find(warnings[1], "no MeshPart", 1, true) ~= nil).toBeTruthy()
		local model = SlimeMesh.build(mesh, Fixtures.slime("b")) :: any
		expect(model).toBe(factory.built[1])
	end)

	it("rebuilds procedurally when dressing the mesh fails", function()
		local mesh, factory, warnings = setup(function(): any
			error("unused")
		end)
		-- A template that can't be cloned makes dress() error.
		mesh.template = {} :: any
		mesh.look = "Mesh"
		local model = SlimeMesh.build(mesh, Fixtures.slime("c")) :: any
		expect(#factory.built).toBe(2)
		expect(factory.built[1].destroyed).toBe(true)
		expect(model).toBe(factory.built[2])
		expect(model.destroyed).toBe(false)
		expect(string.find(warnings[1], "dress failed for c", 1, true) ~= nil).toBeTruthy()
	end)
end)

-- A fake LoadAsset result holding one MeshPart that clones to itself.
local function meshAsset(): any
	local part = {
		Clone = function(self: any): any
			return self
		end,
	}
	return {
		FindFirstChildWhichIsA = function(): any
			return part
		end,
		Destroy = function() end,
	}
end

describe("SlimeMesh kits", function()
	it("loads every kit by its uploaded assetId, after the shared package", function()
		local mesh, _, warnings, requested = setup(function(): any
			return meshAsset()
		end)
		expect(SlimeMesh.load(mesh)).toBe("Mesh")
		expect(requested[1]).toBe(Config.SLIME_MESH_ASSET_ID)
		expect(#requested).toBe(1 + #SlimeLooks.KITS)
		for i, kit in SlimeLooks.KITS do
			expect(requested[i + 1]).toBe((MeshAssets.get(kit) :: any).assetId)
			expect(mesh.kits[kit] ~= nil).toBe(true)
		end
		expect(#warnings).toBe(0)
	end)

	it("keeps the shared mesh when only the kits fail to load", function()
		local mesh, _, warnings = setup(function(assetId: number): any
			if assetId == Config.SLIME_MESH_ASSET_ID then
				return meshAsset()
			end
			error("HTTP 404")
		end)
		expect(SlimeMesh.load(mesh)).toBe("Mesh")
		expect(mesh.template ~= nil).toBe(true)
		expect(next(mesh.kits)).toBeNil()
		expect(#warnings).toBe(1)
	end)

	it("falls back kit -> shared -> procedural when dressing fails", function()
		local mesh, factory, warnings = setup(function(): any
			error("unused")
		end)
		mesh.kits.slime_lop = {} :: any
		mesh.template = {} :: any
		local slime = Fixtures.slime("d")
		slime.species = "lop"
		local model = SlimeMesh.build(mesh, slime) :: any
		expect(#factory.built).toBe(3)
		expect(factory.built[1].destroyed).toBe(true)
		expect(factory.built[2].destroyed).toBe(true)
		expect(model).toBe(factory.built[3])
		expect(#warnings).toBe(3) -- two dress failures + the fake model's type look
	end)
end)

-- Roblox globals SlimeMesh uses at call time; swapped in only while dressing a real Model.
local GLOBALS = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local function withRobloxGlobals<T>(fn: () -> T): T
	local env = getfenv(SlimeMesh.build)
	local saved = {}
	for name, value in GLOBALS do
		saved[name] = env[name]
		env[name] = value
	end
	local ok, result = pcall(fn)
	for name in GLOBALS do
		env[name] = saved[name]
	end
	if not ok then
		error(result, 0)
	end
	return result
end

-- A procedural slime Model: Body (PrimaryPart) plus a face and a tier rim.
local function slimeModel(): any
	local model = roblox.Instance.new("Model")
	local body = roblox.Instance.new("Part")
	body.Name = "Body"
	body.Size = roblox.Vector3.new(6, 6, 6)
	body.Color = roblox.Color3.fromRGB(120, 200, 90)
	body.Parent = model
	model.PrimaryPart = body
	for _, name in { "EyeL", "MouthMid", "TierRim" } do
		local part = roblox.Instance.new("Part")
		part.Name = name
		part.Parent = model
	end
	return model
end

describe("SlimeMesh species kits", function()
	it("wears a kit with an offset at size-1 scale, Color white, and hides the procedural face", function()
		local kit = "slime_gummy"
		local entry = MeshAssets.get(kit) :: any
		assert(entry and entry.offset and entry.size, "species kit entry with offset + size")
		expect((SlimeLooks.get("gummy") :: any).kit).toBe(kit)
		local model = slimeModel()
		local mesh = SlimeMesh.new({
			factory = {
				build = function(): any
					return model
				end,
			} :: any,
			loadAsset = function(): any
				error("unused")
			end,
			warn = function(message: string)
				error(message)
			end,
		})
		local template = roblox.Instance.new("MeshPart")
		local bone = roblox.Instance.new("Bone")
		bone.Parent = template
		roblox.Instance.new("Weld").Parent = template
		mesh.kits[kit] = template :: any
		local built = withRobloxGlobals(function()
			return SlimeMesh.build(mesh, Fixtures.slime("e", 1, { species = "gummy" }))
		end) :: any
		expect(built).toBe(model)
		local worn = model:FindFirstChild(SlimeMesh.MESH_NAME)
		assert(worn, "species mesh")
		expect(worn.Color == roblox.Color3.new(1, 1, 1)).toBe(true)
		local scale = 6 / Config.SLIME_BASE_DIAMETER
		expect(worn.Size.X).toBeCloseTo(entry.size[1] * scale, 1e-3)
		expect(worn.Size.Y).toBeCloseTo(entry.size[2] * scale, 1e-3)
		expect(worn:FindFirstChildWhichIsA("Bone") ~= nil).toBe(true)
		expect(worn:FindFirstChildWhichIsA("Weld")).toBeNil()
		expect(model.Body.Transparency).toBe(1)
		expect(model.EyeL.Transparency).toBe(1)
		expect(model.MouthMid.Transparency).toBe(1)
		expect(model.TierRim.Transparency).toBe(0)
		expect(SlimeMesh.isReplacedPart("EyeL") and SlimeMesh.isReplacedPart("MouthMid")).toBe(true)
		expect(SlimeMesh.isReplacedPart("TierRim")).toBe(false)
	end)
end)
