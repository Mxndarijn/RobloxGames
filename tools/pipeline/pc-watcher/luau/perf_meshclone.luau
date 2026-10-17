-- Server datamodel (play): clones existing MeshParts (same MeshId, so no new mesh data) into
-- workspace.PcwPerfMeshClones until %%TARGET%% extra MeshParts exist there in total (cumulative; 0 only reports).
-- Spread like perf_stress: seeded random XZ over the annulus 0.3..1.0 of the plot ring (r 140), >= 8 studs apart, random
-- yaw, Y by a downward raycast, anchored, no collision / query, tagged PcwPerfClone, CollectionService tags removed.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RING, GAP = 140, 8
local want = %%TARGET%%
local folder = workspace:FindFirstChild("PcwPerfMeshClones")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "PcwPerfMeshClones"
	folder.Parent = workspace
end
local sources = {}
local wild = workspace:FindFirstChild("WildSlimes")
for _, d in workspace:GetDescendants() do
	if d:IsA("MeshPart") and d.MeshId ~= "" and #sources < 40 and not d:IsDescendantOf(folder)
		and not d:FindFirstAncestor("PcwPerfClones") and not (wild and d:IsDescendantOf(wild))
		and not d:FindFirstChildWhichIsA("LuaSourceContainer") and not d:FindFirstChildWhichIsA("ProximityPrompt")
		and not d:FindFirstChildWhichIsA("ClickDetector") and not d:FindFirstChildWhichIsA("Humanoid")
		and math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 60 then
		local isChar = false
		for _, p in Players:GetPlayers() do
			if p.Character and d:IsDescendantOf(p.Character) then
				isChar = true
			end
		end
		if not isChar then
			table.insert(sources, d)
		end
	end
end
if #sources == 0 then
	return { error = "no MeshPart to clone", added = 0, total = 0 }
end
local rng = Random.new(20240602)
local placed, grid = {}, {}
local function key(x, z)
	return math.floor(x / GAP) .. "," .. math.floor(z / GAP)
end
for _, c in folder:GetChildren() do
	local p = c.Position
	table.insert(placed, p)
	local k = key(p.X, p.Z)
	grid[k] = grid[k] or {}
	table.insert(grid[k], p)
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
params.FilterDescendantsInstances = { folder }
local start, total, fails = #folder:GetChildren(), #folder:GetChildren(), 0
local ids = {}
while total < want and fails < 600 do
	local src = sources[rng:NextInteger(1, #sources)]
	local ang = rng:NextNumber(0, math.pi * 2)
	local r = RING * math.sqrt(rng:NextNumber(0.3 * 0.3, 1))
	local x, z = math.cos(ang) * r, math.sin(ang) * r
	local hit = if free(x, z) then workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params) else nil
	if not hit then
		fails += 1
	else
		local clone = src:Clone()
		clone:ClearAllChildren()
		clone:SetAttribute("PcwPerfClone", true)
		for _, tag in CollectionService:GetTags(clone) do
			CollectionService:RemoveTag(clone, tag)
		end
		clone.Anchored, clone.CanCollide, clone.CanQuery = true, false, false
		clone.CFrame = CFrame.new(x, hit.Position.Y + clone.Size.Y / 2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		clone.Parent = folder
		table.insert(placed, clone.Position)
		local k = key(x, z)
		grid[k] = grid[k] or {}
		table.insert(grid[k], clone.Position)
		ids[clone.MeshId] = true
		total += 1
	end
end
local distinct = 0
for _ in ids do
	distinct += 1
end
return { added = total - start, total = total, target = want, reached = total >= want, sources = #sources, distinct_mesh_ids = distinct }
