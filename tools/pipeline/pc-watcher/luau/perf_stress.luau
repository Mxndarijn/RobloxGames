-- Server datamodel (play): perf stress. Clones existing decorative world props (workspace.Map.Decor, then
-- Map.Border) into workspace.PcwPerfClones until at least %%TARGET%% extra BaseParts exist in total
-- (cumulative over calls; TARGET = 0 only reports). Candidates are Models of 3-60 BaseParts (single
-- BaseParts as a fallback) with no scripts, ProximityPrompts, ClickDetectors, Humanoids or Seats and no
-- axis > 60 studs. Clones sit on a seeded random XZ spread over the annulus 0.3..OUTER of the plot ring
-- (WorldLayout.PLOT_RING_RADIUS = 140; OUTER = 1.6, ~224 studs) around the plaza centre (the origin),
-- >= GAP (5) studs between pivots, giving up only after MAXFAILS placement misses in a row,
-- random yaw, Y by a downward raycast, Anchored, CanCollide / CanQuery off, tagged PcwPerfClone, with
-- every CollectionService tag removed so no game system picks them up. Runtime only, nothing is saved.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RING, OUTER, GAP, MAXSIZE, MAXFAILS = 140, 1.6, 5, 60, 3000
local want = %%TARGET%%

local folder = workspace:FindFirstChild("PcwPerfClones")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "PcwPerfClones"
	folder.Parent = workspace
end

local function countParts(root, includeRoot)
	local parts, mesh = 0, 0
	local list = root:GetDescendants()
	if includeRoot then
		table.insert(list, root) -- a cloned single BasePart is itself the part
	end
	for _, d in list do
		if d:IsA("BasePart") then
			parts += 1
			if d:IsA("MeshPart") then
				mesh += 1
			end
		end
	end
	return parts, mesh
end

local function usable(inst)
	local parts = 0
	local list = inst:GetDescendants()
	table.insert(list, inst)
	for _, d in list do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Humanoid")
			or d:IsA("Seat") or d:IsA("VehicleSeat") or d:IsA("Sound") then
			return 0
		end
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	if parts == 0 or (inst:IsA("Model") and (parts < 3 or parts > 60)) then
		return 0
	end
	local size = if inst:IsA("Model") then inst:GetExtentsSize() else (inst :: BasePart).Size
	if math.max(size.X, size.Y, size.Z) > MAXSIZE then
		return 0
	end
	return parts
end

local sources = {}
local map = workspace:FindFirstChild("Map")
for _, folderName in { "Decor", "Border" } do
	local f = map and map:FindFirstChild(folderName)
	if f and #sources < 12 then
		for _, c in f:GetChildren() do
			if (c:IsA("Model") or c:IsA("BasePart")) and usable(c) > 0 then
				table.insert(sources, c)
			end
		end
	end
end
if #sources == 0 then
	return { error = "no usable decor prop to clone", added_parts = 0, added_mesh_parts = 0, clones = 0 }
end

local startParts, startMesh = countParts(folder, false)
local total, mesh = startParts, startMesh
local rng = Random.new(20240601)
local placed, grid = {}, {}
for _, c in folder:GetChildren() do
	local p = c:GetPivot().Position
	table.insert(placed, p)
	local key = math.floor(p.X / GAP) .. "," .. math.floor(p.Z / GAP)
	grid[key] = grid[key] or {}
	table.insert(grid[key], p)
end
local function free(x, z)
	local cx, cz = math.floor(x / GAP), math.floor(z / GAP)
	for dx = -1, 1 do
		for dz = -1, 1 do
			for _, p in grid[(cx + dx) .. "," .. (cz + dz)] or {} do
				if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < GAP * GAP then
					return false
				end
			end
		end
	end
	return true
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
local ignore = { folder }
local wild = workspace:FindFirstChild("WildSlimes")
if wild then
	table.insert(ignore, wild)
end
for _, p in Players:GetPlayers() do
	if p.Character then
		table.insert(ignore, p.Character)
	end
end
params.FilterDescendantsInstances = ignore

local sourcesUsed, clones, fails = {}, 0, 0
local n = #placed
while total < want and fails < MAXFAILS do
	local src = sources[rng:NextInteger(1, #sources)]
	local ang = rng:NextNumber(0, math.pi * 2)
	local r = RING * math.sqrt(rng:NextNumber(0.3 * 0.3, OUTER * OUTER))
	local x, z = math.cos(ang) * r, math.sin(ang) * r
	local hit = if free(x, z) then workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params) else nil
	if not hit then
		fails += 1
	else
		fails = 0
		local clone = src:Clone()
		clone:SetAttribute("PcwPerfClone", true)
		local list = clone:GetDescendants()
		table.insert(list, clone)
		for _, d in list do
			for _, tag in CollectionService:GetTags(d) do
				CollectionService:RemoveTag(d, tag)
			end
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		clone.Parent = folder
		local box, size
		if clone:IsA("Model") then
			box, size = clone:GetBoundingBox()
		else
			box, size = (clone :: BasePart).CFrame, (clone :: BasePart).Size
		end
		local drop = clone:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
		clone:PivotTo(CFrame.new(x, hit.Position.Y + drop, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		local p = Vector3.new(x, hit.Position.Y, z)
		table.insert(placed, p)
		local key = math.floor(x / GAP) .. "," .. math.floor(z / GAP)
		grid[key] = grid[key] or {}
		table.insert(grid[key], p)
		local cp, cm = countParts(clone, true)
		total += cp
		mesh += cm
		clones += 1
		sourcesUsed[src.Name] = (sourcesUsed[src.Name] or 0) + 1
	end
end
return {
	added_parts = total - startParts,
	added_mesh_parts = mesh - startMesh,
	clones = clones,
	total_extra_parts = total,
	total_extra_mesh_parts = mesh,
	target = want,
	reached = total >= want,
	candidates = #sources,
	sources = sourcesUsed,
	outer_radius = RING * OUTER,
	gap = GAP,
}
