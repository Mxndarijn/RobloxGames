--!strict
-- Held PvP item looks (src/shared/PvpModels, CONTRACT.md §26.3): one row per Config.PVP_TOOLS id, every mesh name in
-- MeshAssets.NAMES, and a placeholder that stands in until the mesh is uploaded.
local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local PvpModels = require("../src/shared/PvpModels")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SHAPES = { Block = true, Ball = true, Cylinder = true }

describe("PvpModels", function()
	it("has a look for every PvP item and nothing else", function()
		local ids: { [string]: boolean } = {}
		for _, tool in Config.PVP_TOOLS do
			ids[tool.id] = true
			expect(`{tool.id} {PvpModels.get(tool.id) ~= nil}`).toBe(`{tool.id} true`)
		end
		for id in PvpModels.ITEMS do
			expect(`{id} {ids[id] == true}`).toBe(`{id} true`)
		end
	end)
	it("names a distinct MeshAssets mesh per item, listed in NAMES", function()
		local seen: { [string]: boolean } = {}
		for id, item in PvpModels.ITEMS do
			expect(seen[item.mesh]).toBeNil()
			seen[item.mesh] = true
			expect(`{id} {table.find(MeshAssets.NAMES, item.mesh) ~= nil}`).toBe(`{id} true`)
		end
		expect(#PvpModels.MESHES).toBe(#Config.PVP_TOOLS)
	end)
	it("uses the placeholder until a mesh is uploaded (the mesh id comes from MeshAssets)", function()
		for id, item in PvpModels.ITEMS do
			expect(PvpModels.meshId(id)).toBe(MeshAssets.meshId(item.mesh))
		end
		expect(PvpModels.meshId("Nope")).toBeNil()
		expect(PvpModels.meshId(nil)).toBeNil()
	end)
	it("builds every placeholder from a few sane parts near the hand", function()
		for id, item in PvpModels.ITEMS do
			expect(#item.pieces >= 2 and #item.pieces <= 5).toBe(true)
			expect(#item.size).toBe(3)
			expect(#item.grip.pos == 3 and #item.grip.rotDeg == 3).toBe(true)
			for _, piece in item.pieces do
				expect(`{id} {SHAPES[piece.shape] == true}`).toBe(`{id} true`)
				for axis = 1, 3 do
					expect(piece.size[axis] > 0 and piece.size[axis] <= 4).toBe(true)
					expect(math.abs(piece.pos[axis]) <= 4).toBe(true)
					expect(piece.color[axis] >= 0 and piece.color[axis] <= 255).toBe(true)
				end
			end
		end
	end)
	it("shows each glove tier bigger than the last", function()
		for tier = 2, 5 do
			local a = PvpModels.ITEMS[`KnockGlove{tier - 1}`].pieces[1].size[1]
			local b = PvpModels.ITEMS[`KnockGlove{tier}`].pieces[1].size[1]
			expect(b > a).toBe(true)
		end
	end)
	it(
		"fits each uploaded mesh at its native size; only traps and the Bounce Pad are scaled down in the hand",
		function()
			for id, item in PvpModels.ITEMS do
				local entry = MeshAssets.get(item.mesh)
				if entry and entry.size then
					expect(`{id} {table.concat(item.size, ",")}`).toBe(`{id} {table.concat(entry.size, ",")}`)
				end
				local placed = PvpModels.markerMesh(id) ~= nil
				if placed then
					expect(item.held ~= nil and item.held > 0 and item.held < 1).toBe(true)
				else
					expect(`{id} {item.held}`).toBe(`{id} nil`)
				end
			end
		end
	)
	it("welds the mesh with its grip scaled like the mesh, the placeholder on the bare grip attachment", function()
		local trap = PvpModels.ITEMS.GooTrap2
		local mesh = PvpModels.mount(trap, true)
		for axis = 1, 3 do
			expect(mesh.pos[axis]).toBe(trap.grip.pos[axis] * (trap.held :: number))
		end
		expect(mesh.rotDeg).toEqual(trap.grip.rotDeg)
		local glove = PvpModels.ITEMS.KnockGlove1
		expect(PvpModels.mount(glove, true).pos).toEqual(glove.grip.pos)
		expect(PvpModels.mount(glove, true, 2).pos[2]).toBe(glove.grip.pos[2] * 2)
		for _, item in PvpModels.ITEMS do
			local bare = PvpModels.mount(item, false)
			expect(bare.pos).toEqual({ 0, 0, 0 })
			expect(bare.rotDeg).toEqual({ 0, 0, 0 })
		end
		expect(glove.grip.rotDeg[1]).toBe(90) -- the punch turn applies to the mesh only
	end)
	it("offers the trap and pad meshes for placed markers only", function()
		expect(PvpModels.markerMesh("GooTrap2")).toBe("pvp_goo_trap_2")
		expect(PvpModels.markerMesh("FunBouncePad")).toBe("pvp_fun_bounce_pad")
		expect(PvpModels.markerMesh("KnockGlove1")).toBeNil()
		expect(PvpModels.markerMesh(nil)).toBeNil()
	end)
	it("lists every placed-marker mesh for the server's templates, uploaded and sized", function()
		expect(PvpModels.MARKER_MESHES).toEqual({
			"pvp_fun_bounce_pad",
			"pvp_goo_trap_1",
			"pvp_goo_trap_2",
			"pvp_goo_trap_3",
		})
		for _, name in PvpModels.MARKER_MESHES do
			local entry = MeshAssets.get(name)
			expect(`{name} {entry ~= nil and entry.meshId ~= nil and entry.size ~= nil}`).toBe(`{name} true`)
		end
	end)
	it("a placed trap shows its hand placeholder pieces until the mesh is uploaded", function()
		local pieces = PvpModels.markerParts("GooTrap3")
		expect(pieces ~= nil and #pieces > 0).toBe(true)
		expect(pieces).toBe((PvpModels.get("GooTrap3") :: any).pieces)
		expect(PvpModels.markerParts("GooBlaster1")).toBeNil()
	end)
end)
