--!nocheck
-- Bug #16: every plot's MergeVat disc wears the merge_vat model, independent of FEATURES.MergeVat3 (the flag only
-- gates the 3-slime gameplay). Booted in the fake runtime: the mesh stands on the disc via VatDecor.pose, the disc
-- and its Goo are invisible but keep name, position, collision and the MergePrompt; with no mesh template the
-- cylinder stays visible (no invisible vat).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local VatDecor = require("../src/visuals/shared/VatDecor")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-vatmesh-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local function boot(loads: boolean)
	local rt = Runtime.new(path, {
		createMeshPart = function(meshId)
			if loads then
				return roblox.Instance.new("MeshPart")
			end
			error(`livetest: CreateMeshPartAsync({meshId}) failed`)
		end,
	})
	rt:boot()
	rt:advance(2)
	return rt
end

local ok = boot(true)
local failed = boot(false)
fs.removeFile(path)

local function vats(rt)
	local out = {}
	for _, plot in rt.workspace:FindFirstChild(Constants.PLOTS_FOLDER):GetChildren() do
		local vat = plot:FindFirstChild("MergeVat")
		if vat then
			table.insert(out, { plot = plot, vat = vat })
		end
	end
	return out
end

describe("plot vats wear the merge_vat model (bug #16)", function()
	it("is independent of FEATURES.MergeVat3 and covers every plot", function()
		expect(Config.FEATURES.MergeVat3 == false or Config.FEATURES.MergeVat3 == true).toBe(true)
		local list = vats(ok)
		expect(#list).toBe(Config.PLOT_COUNT)
		for _, e in list do
			expect(e.vat:FindFirstChild("VatMesh") ~= nil).toBe(true)
		end
	end)
	it("poses the mesh with VatDecor and keeps it visual-only", function()
		for _, e in vats(ok) do
			local mesh = e.vat:FindFirstChild("VatMesh")
			local p = e.vat.CFrame.Position
			local pose = VatDecor.pose(p.X, p.Y, p.Z)
			expect(math.abs(mesh.CFrame.Position.X - pose.position[1]) < 1e-3).toBe(true)
			expect(math.abs(mesh.CFrame.Position.Y - pose.position[2]) < 1e-3).toBe(true)
			expect(math.abs(mesh.CFrame.Position.Z - pose.position[3]) < 1e-3).toBe(true)
			expect(math.abs(mesh.Size.Y - pose.size[2]) < 1e-3).toBe(true)
			expect(mesh.Anchored).toBe(true)
			expect(mesh.CanCollide).toBe(false)
			expect(mesh.CanQuery).toBe(false)
		end
	end)
	it("keeps the disc with its name, collision and MergePrompt, only invisible with its Goo", function()
		for _, e in vats(ok) do
			expect(e.vat.Transparency).toBe(1)
			expect(e.vat.CanCollide).toBe(true)
			local goo = e.vat:FindFirstChild("Goo")
			expect(goo ~= nil and goo.Transparency == 1).toBe(true)
			local prompt = e.vat:FindFirstChild(Constants.MERGE_PROMPT_NAME)
			expect(prompt ~= nil and prompt:IsA("ProximityPrompt")).toBe(true)
		end
	end)
	it("falls back to the visible cylinder when the mesh cannot load", function()
		local list = vats(failed)
		expect(#list).toBe(Config.PLOT_COUNT)
		for _, e in list do
			expect(e.vat:FindFirstChild("VatMesh") == nil).toBe(true)
			expect(e.vat.Transparency < 1).toBe(true)
			local goo = e.vat:FindFirstChild("Goo")
			expect(goo ~= nil and goo.Transparency < 1).toBe(true)
			expect(e.vat:FindFirstChild(Constants.MERGE_PROMPT_NAME) ~= nil).toBe(true)
		end
	end)
end)
