--!nocheck
--[[
	build-map (owner: Archer)

	  lune run src/visuals/tools/build-map.luau      (from the repo root)

	Runs the real WorldBuilder (WorldLayout) against @lune/roblox instances
	and writes the static world as two Roblox model files, one root each
	(Rojo maps a .rbxm with exactly one root instance):

	  src/visuals/static/Map.rbxm     workspace.Map
	  src/visuals/static/Plots.rbxm   workspace.Plots

	Every BasePart is anchored; the script refuses to write otherwise. Run
	check-map.luau afterwards. Re-run whenever WorldLayout changes.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("./LuneGlobals")

local Constants = require("../../shared/Constants")
local WorldBuilder = require("../shared/WorldBuilder")
local WorldLayout = require("../shared/WorldLayout")

local OUT = "src/visuals/static"

if not fs.isFile("default.project.json") then
	print("build-map: run from the repo root")
	process.exit(1)
end

local root = roblox.Instance.new("Folder")
root.Name = "Workspace"
local built = WorldBuilder.build(root)
-- A second build must adopt everything (idempotent).
local count = #root:GetDescendants()
WorldBuilder.build(root)
assert(#root:GetDescendants() == count, "WorldBuilder.build is not idempotent")

local parts = 0
for _, inst in root:GetDescendants() do
	if inst:IsA("BasePart") then
		parts += 1
		assert(inst.Anchored, `{inst:GetFullName()} is not anchored`)
	end
end

fs.writeDir(OUT)
for name, folder in { [WorldLayout.MAP_NAME] = built.map, [Constants.PLOTS_FOLDER] = built.plots } do
	assert(folder.Name == name, `unexpected root {folder.Name}`)
	local path = `{OUT}/{name}.rbxm`
	fs.writeFile(path, roblox.serializeModel({ folder }))
	print(`build-map: wrote {path} ({#folder:GetDescendants()} instances)`)
end
print(`build-map: {parts} anchored parts`)
