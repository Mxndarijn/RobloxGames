--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local SlimeMesh = require("../src/server/SlimeMesh")
local TestRunner = require("./TestRunner")

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
		expect(#warnings).toBe(1)
		expect(string.find(warnings[1], "403", 1, true) ~= nil).toBeTruthy()

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
