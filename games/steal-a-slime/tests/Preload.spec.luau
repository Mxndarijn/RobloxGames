--!strict
-- v30 C2: kit meshes are drawn whole (RenderFidelity.Precise) and the client
-- preloads every uploaded mesh id, so nothing pops in after the first move.
local fs = require("@lune/fs")

local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("mesh preload (v30 C2)", function()
	it("MeshAssets.allMeshIds lists every uploaded mesh once", function()
		local ids = MeshAssets.allMeshIds()
		local uploaded = 0
		for _, name in MeshAssets.NAMES do
			if MeshAssets.meshId(name) then
				uploaded += 1
			end
		end
		expect(#ids > 0).toBe(true)
		expect(#ids <= uploaded).toBe(true)
		local seen = {}
		for _, id in ids do
			expect(string.match(id, "^rbxassetid://%d+$") ~= nil).toBe(true)
			expect(seen[id]).toBe(nil)
			seen[id] = true
		end
		expect(seen[MeshAssets.meshId("ranch_fence_20") :: string]).toBe(true)
		expect(seen[MeshAssets.meshId("slime_fountain") :: string]).toBe(true)
	end)
	it("MeshSwap draws every swapped mesh at Precise fidelity", function()
		local src = fs.readFile("src/server/MeshSwap.luau")
		expect(string.find(src, "mesh.RenderFidelity = Enum.RenderFidelity.Precise", 1, true) ~= nil).toBe(true)
	end)
	it("VisualsClient starts the preload and the place does not stream", function()
		local init = fs.readFile("src/visuals/client/init.client.luau")
		expect(string.find(init, 'WaitForChild("Preload")', 1, true) ~= nil).toBe(true)
		local project = fs.readFile("default.project.json")
		expect(string.find(project, '"StreamingEnabled": false', 1, true) ~= nil).toBe(true)
		local preload = fs.readFile("src/visuals/client/Preload.luau")
		expect(string.find(preload, "PreloadAsync", 1, true) ~= nil).toBe(true)
	end)
end)
