--!nocheck
--[[
	check-map (owner: Archer)

	  lune run src/visuals/tools/check-map.luau [place.rbxl]   (repo root)

	Without an argument: loads src/visuals/static/Map.rbxm + Plots.rbxm.
	With a place file (e.g. `rojo build -o /tmp/sas.rbxl`): checks
	Workspace.Map / Workspace.Plots in it; if the place doesn't contain them
	yet (static files not mapped in default.project.json), says so and falls
	back to the .rbxm files.

	Asserts: Map.Ground (anchored, CanCollide, covers every plot part),
	Map.Volcano.Crater, Plot_1..PLOT_COUNT (PlotIndex) with Base,
	Pad_1..PADS_MAX (PadIndex, exactly PADS_MAX), HomeZone (no collide,
	invisible), MergeVat, LockButton, Sign, an empty Slimes folder, and every
	BasePart anchored. Exits 1 on any failure.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("./LuneGlobals")

local Config = require("../../shared/Config")
local Constants = require("../../shared/Constants")

local STATIC = "src/visuals/static"

local failed, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		failed += 1
		print(`  FAIL  {msg}`)
	end
end

local function loadModel(name: string)
	local path = `{STATIC}/{name}.rbxm`
	if not fs.isFile(path) then
		return nil
	end
	local roots = roblox.deserializeModel(fs.readFile(path))
	check(#roots == 1 and roots[1].Name == name, `{path} has one root named {name}`)
	return roots[1]
end

local source, map, plots
local placePath = process.args[1]
if placePath then
	local game = roblox.deserializePlace(fs.readFile(placePath))
	local ws = game:GetService("Workspace")
	map, plots = ws:FindFirstChild(Constants.MAP_FOLDER), ws:FindFirstChild(Constants.PLOTS_FOLDER)
	if map and plots then
		source = `{placePath} Workspace`
	else
		print(`check-map: {placePath} has no Workspace.Map / Plots yet (not mapped); checking {STATIC}/*.rbxm`)
		map, plots = nil, nil
	end
end
if not map then
	map, plots = loadModel(Constants.MAP_FOLDER), loadModel(Constants.PLOTS_FOLDER)
	source = `{STATIC}/{Constants.MAP_FOLDER}.rbxm + {Constants.PLOTS_FOLDER}.rbxm`
end
if not (map and plots) then
	print("check-map: Map / Plots missing (run build-map.luau)")
	process.exit(1)
end

-- Ground ------------------------------------------------------------------
local ground = map:FindFirstChild("Ground")
check(ground and ground:IsA("BasePart"), "Map.Ground is a BasePart")
if ground and ground:IsA("BasePart") then
	check(ground.Anchored and ground.CanCollide, "Map.Ground anchored + CanCollide")
	local half = ground.Size / 2
	local top = ground.CFrame.Position.Y + half.Y
	check(math.abs(top) < 0.01, `Map.Ground top at y = 0 (got {top})`)
	for _, inst in plots:GetDescendants() do
		if inst:IsA("BasePart") then
			local p = inst.CFrame.Position - ground.CFrame.Position
			if math.abs(p.X) > half.X or math.abs(p.Z) > half.Z then
				check(false, `{inst:GetFullName()} outside the ground`)
			end
		end
	end
end
local volcano = map:FindFirstChild("Volcano")
check(volcano and volcano:FindFirstChild("Crater") and volcano.Crater:IsA("BasePart"), "Map.Volcano.Crater")

-- Plots -------------------------------------------------------------------
for i = 1, Config.PLOT_COUNT do
	local plot = plots:FindFirstChild(`Plot_{i}`)
	check(plot ~= nil, `Plot_{i} exists`)
	if plot then
		check(plot:GetAttribute(Constants.PLOT_INDEX_ATTRIBUTE) == i, `Plot_{i} PlotIndex = {i}`)
		for _, name in { "Base", "MergeVat", "LockButton", "Sign" } do
			check(plot:FindFirstChild(name), `Plot_{i}.{name}`)
		end
		for j = 1, Config.PADS_MAX do
			local pad = plot:FindFirstChild(`Pad_{j}`)
			check(pad and pad:IsA("BasePart"), `Plot_{i}.Pad_{j}`)
			check(pad and pad:GetAttribute(Constants.PAD_INDEX_ATTRIBUTE) == j, `Plot_{i}.Pad_{j} PadIndex`)
		end
		check(plot:FindFirstChild(`Pad_{Config.PADS_MAX + 1}`) == nil, `Plot_{i} has exactly PADS_MAX pads`)
		local zone = plot:FindFirstChild(Constants.HOME_ZONE)
		check(
			zone and zone:IsA("BasePart") and not zone.CanCollide and zone.Transparency == 1,
			`Plot_{i}.HomeZone non-colliding + invisible`
		)
		local slimes = plot:FindFirstChild(Constants.PLOT_SLIMES_FOLDER)
		check(slimes and slimes:IsA("Folder") and #slimes:GetChildren() == 0, `Plot_{i}.Slimes empty Folder`)
	end
end

-- Anchored ----------------------------------------------------------------
local parts, loose = 0, 0
for _, rootFolder in { map, plots } do
	for _, inst in rootFolder:GetDescendants() do
		if inst:IsA("BasePart") then
			parts += 1
			if not inst.Anchored then
				loose += 1
				check(false, `{inst:GetFullName()} anchored`)
			end
		end
	end
end
check(parts > 0, "has parts")

print(`check-map: {source}: {parts} parts ({loose} unanchored), {passed} passed, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
