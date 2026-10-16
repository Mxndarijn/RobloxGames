--!strict
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
		expect(string.find(warnings[2], "slime_base", 1, true) ~= nil).toBeTruthy()
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
	it("plans a body kit and an optional accessory per SlimeLooks kit", function()
		local body, acc = SlimeMesh.plan("slime_ears")
		expect(body).toBe("slime_ears")
		expect(acc).toBeNil()
		body, acc = SlimeMesh.plan("slime_acc_crown")
		expect(body).toBe("slime_base")
		expect(acc).toBe("slime_acc_crown")
		expect(SlimeMesh.plan(nil)).toBeNil()
		for _, kit in SlimeLooks.KITS do
			local b = SlimeMesh.plan(kit)
			expect(b ~= nil and MeshAssets.get(b :: string) ~= nil).toBe(true)
		end
	end)

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
		mesh.kits.slime_ears = {} :: any
		mesh.template = {} :: any
		local slime = Fixtures.slime("d")
		slime.species = "bunny_puff"
		local model = SlimeMesh.build(mesh, slime) :: any
		expect(#factory.built).toBe(3)
		expect(factory.built[1].destroyed).toBe(true)
		expect(factory.built[2].destroyed).toBe(true)
		expect(model).toBe(factory.built[3])
		expect(#warnings).toBe(3) -- two dress failures + the fake model's type look
	end)
end)
