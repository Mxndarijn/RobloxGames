--!nocheck
--[[
	terrain_burial.luau (Phoenix): standalone burial probe for Open Cloud Luau Execution (server context, no plugins).
	Run: tools/livetest/cloud/run.sh <this file> <placeVersion>   (or any Luau execution task / a server Script body)

	Under Luau Execution the place's own Scripts do NOT start, so when the world is not booted yet (no Terrain attribute
	GroundTerrain) this script boots it the way init.server.luau does: WorldView.setup, GroundTerrainView.place,
	WorldProps.place, RitualView.setup, FountainColliders.place, ParadeView.place, then BorderTerrainView.place and
	MeshSwap.apply in task.spawn. On a running server (Script / command bar) it measures the live world as is.

	Then: waits for Workspace BorderTerrainReady (or Terrain attribute BorderTerrain), max WAIT_S, settles SETTLE_S,
	and for every visible grounded BasePart (bottom between EMBED_OK (-0.5) and GROUND_BAND above y = 0: plot floors, pads, fence posts, vat,
	signs, fountain base, slide supports, props) raycasts terrain only at the part centre and 4 inset corners.
	buried = highest terrain surface under the part - part bottom (positive = sunk). FAIL if any buried > THRESHOLD.
	Also: named targets (fountain, MergeVat, Sign, spawns, plot bboxes) and a ReadVoxels column at the plaza / plot 1
	(occupancy per 4-stud layer) so a raised surface is visible directly. Returns (and prints) one JSON string.
]]
local THRESHOLD = 0.25
local WAIT_S = 150
local SETTLE_S = 3
local GROUND_BAND = 3
local EMBED_OK = -0.5 -- parts whose bottom is below this were placed sunk on purpose (Map.Decor rocks): skipped
local TOP_N = 25

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local terrain = workspace.Terrain
local t0 = os.clock()
local out = { version = game.PlaceVersion, place = game.PlaceId, booted_by_probe = false, boot_errors = {}, threshold = THRESHOLD }

local function r2(v)
	return v and math.floor(v * 100 + 0.5) / 100 or nil
end

-- 1. boot when the place scripts did not run (Luau Execution)
if terrain:GetAttribute("GroundTerrain") == nil then
	out.booted_by_probe = true
	local Server = ServerScriptService:FindFirstChild("Server")
	local function step(name, fn, spawn)
		local mod = Server and Server:FindFirstChild(name)
		if not mod then
			table.insert(out.boot_errors, name .. ": module missing")
			return
		end
		local run = function()
			local ok, err = pcall(function()
				fn(require(mod))
			end)
			if not ok then
				table.insert(out.boot_errors, name .. ": " .. tostring(err):split("\n")[1])
			end
		end
		if spawn then task.spawn(run) else run() end
	end
	pcall(function()
		require(Server.Remotes).setup()
	end)
	step("WorldView", function(m) m.setup() end)
	step("GroundTerrainView", function(m) m.place() end)
	step("WorldProps", function(m) m.place() end)
	step("RitualView", function(m) m.setup() end)
	step("FountainColliders", function(m) m.place() end)
	step("ParadeView", function(m) m.place() end)
	step("BorderTerrainView", function(m) m.place() end, true)
	step("MeshSwap", function(m) m.apply() end, true)
end

-- 2. wait for terrain, settle
local function ready()
	return workspace:GetAttribute("BorderTerrainReady") == true or terrain:GetAttribute("BorderTerrain") ~= nil
end
while not ready() and os.clock() - t0 < WAIT_S do
	task.wait(0.5)
end
out.terrain_ready = ready()
out.waited_s = r2(os.clock() - t0)
task.wait(SETTLE_S)
out.ground_terrain_attr = terrain:GetAttribute("GroundTerrain")

-- 3. measure
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { terrain }
local function surface(x, z)
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
	if hit then
		return hit.Position.Y, hit.Material.Name
	end
end
local function measure(label, cf, size)
	local bottom = cf.Position.Y
		- (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) / 2
	local hx, hz = size.X * 0.4, size.Z * 0.4
	local top, mat = nil, nil
	for _, o in { Vector3.zero, Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz), Vector3.new(hx, 0, -hz), Vector3.new(-hx, 0, -hz) } do
		local p = (cf * CFrame.new(o)).Position
		local s, m = surface(p.X, p.Z)
		if s and (not top or s > top) then
			top, mat = s, m
		end
	end
	return {
		name = label,
		bottom = r2(bottom),
		terrain = r2(top),
		material = mat,
		buried = top and r2(top - bottom) or nil,
		at = { r2(cf.Position.X), r2(cf.Position.Z) },
	}
end
local function measureInst(inst, label)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return measure(label, cf, size)
	elseif inst:IsA("BasePart") then
		return measure(label, inst.CFrame, inst.Size)
	end
end

local skip = {}
for _, n in { "WildSlimes" } do
	local f = workspace:FindFirstChild(n)
	if f then skip[f] = true end
end
local mapGround = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Ground")
local parts, named = {}, {}
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") and d ~= mapGround and d.Transparency < 1 and not d:FindFirstAncestorWhichIsA("Humanoid") then
		local anc, skipIt = d.Parent, false
		while anc and anc ~= workspace do
			if skip[anc] or anc:FindFirstChildOfClass("Humanoid") then
				skipIt = true
				break
			end
			anc = anc.Parent
		end
		if not skipIt then
			local r = measure(d:GetFullName(), d.CFrame, d.Size)
			if r.bottom and r.bottom >= EMBED_OK and r.bottom <= GROUND_BAND and r.buried then
				table.insert(parts, r)
			end
		end
	end
	local n = d.Name
	if n == "MergeVat" or n == "Sign" or n == "HubSpawn" or d:IsA("SpawnLocation") or n == "Fountain" or n == "FountainMesh" or n == "FountainBase" then
		local r = measureInst(d, n .. ": " .. d:GetFullName())
		if r then table.insert(named, r) end
	end
end
local plots = workspace:FindFirstChild("Plots")
if plots then
	for _, plot in plots:GetChildren() do
		local r = measureInst(plot, "plot bbox: " .. plot.Name)
		if r then table.insert(named, r) end
	end
end
table.sort(parts, function(a, b) return a.buried > b.buried end)
local over = 0
for _, r in parts do
	if r.buried > THRESHOLD then over += 1 end
end
out.grounded_parts = #parts
out.over_threshold = over
out.worst = {}
for i = 1, math.min(TOP_N, #parts) do
	out.worst[i] = parts[i]
end
out.named = named

-- terrain surface samples + voxel columns (occupancy per 4-stud layer from y = -12 to +8)
local function column(x, z)
	local region = Region3.new(Vector3.new(x - 2, -12, z - 2), Vector3.new(x + 2, 8, z + 2)):ExpandToGrid(4)
	local ok, mats, occ = pcall(function()
		return terrain:ReadVoxels(region, 4)
	end)
	if not ok then return { error = tostring(mats) } end
	local rows = {}
	for y = 1, occ.Size.Y do
		table.insert(rows, string.format("y%d..%d %s %.2f", region.CFrame.Position.Y - region.Size.Y / 2 + (y - 1) * 4,
			region.CFrame.Position.Y - region.Size.Y / 2 + y * 4, mats[1][y][1].Name, occ[1][y][1]))
	end
	return rows
end
local samples = { plaza = Vector3.new(30, 0, 30) }
if plots then
	local p1 = plots:FindFirstChild("Plot_1")
	if p1 then
		local cf = p1:GetBoundingBox()
		samples.plot1 = cf.Position
	end
end
out.samples = {}
for name, p in samples do
	local s, m = surface(p.X, p.Z)
	out.samples[name] = { at = { r2(p.X), r2(p.Z) }, surface = r2(s), material = m, column = column(p.X, p.Z) }
end

out.pass = out.terrain_ready and #parts > 0 and over == 0
out.ok = out.pass -- run.sh: exit 0 only when ok == true
out.result = if out.pass then "PASS" else "FAIL"
out.summary = string.format("%s: %d/%d grounded parts buried > %.2f studs; worst %s by %s studs (terrain ready %s after %ss)",
	out.result, over, #parts, THRESHOLD, parts[1] and parts[1].name or "-", tostring(parts[1] and parts[1].buried),
	tostring(out.terrain_ready), tostring(out.waited_s))
print("TERRAIN_BURIAL " .. out.summary)
local json = HttpService:JSONEncode(out)
print(json)
return json
