-- Server datamodel: phone_perf set-up. Makes sure at least %%TARGET%% tagged wild/pad slimes (the
-- ones SlimeLife animates) stand within 70 studs of the first player's character; clones existing
-- ones when short (the live World is a local of src/server, so Spawner.spawnOne cannot be called
-- from here). Clones carry PcwFill, a unique SlimeId (SlimeLife keys on it) and are put on the
-- ground in a ring around the character. TARGET = 0 only removes earlier clones.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local NEAR = 70
for _, m in CollectionService:GetTagged("Slime") do
	if m:GetAttribute("PcwFill") then
		m:Destroy()
	end
end
local want = %%TARGET%%
if want <= 0 then
	return { removed = true }
end
local player = Players:GetPlayers()[1]
local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if not root then
	return { error = "no character" }
end
local function life(m)
	local s = m:GetAttribute("State")
	return m:IsA("Model") and (s == "Wild" or s == "Pad") and m:GetAttribute("DespawnAt") == nil
end
local near, sources = 0, {}
for _, m in CollectionService:GetTagged("Slime") do
	if life(m) then
		local pos = m:GetPivot().Position
		if (pos - root.Position).Magnitude <= NEAR then
			near += 1
		end
		table.insert(sources, m)
	end
end
local before = near
if #sources == 0 then
	return { error = "no slime to clone", near_before = 0, sources = 0 }
end
local wild = workspace:FindFirstChild("WildSlimes") or workspace
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { wild, player.Character }
local added, n = 0, 0
while near < want and n < want * 3 do
	n += 1
	local src = sources[(n - 1) % #sources + 1]
	local ang = n * 2.399963
	local r = 10 + (n * 7) % 40
	local x, z = root.Position.X + math.cos(ang) * r, root.Position.Z + math.sin(ang) * r
	local hit = workspace:Raycast(Vector3.new(x, root.Position.Y + 30, z), Vector3.new(0, -80, 0), params)
	if hit then
		local clone = src:Clone()
		clone:SetAttribute("PcwFill", true)
		clone:SetAttribute("SlimeId", "pcw-fill-" .. n)
		clone:SetAttribute("State", "Wild")
		clone.Parent = wild
		local cf, size = clone:GetBoundingBox()
		local drop = clone:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
		clone:PivotTo(CFrame.new(x, hit.Position.Y + drop, z) * clone:GetPivot().Rotation)
		near += 1
		added += 1
	end
end
return { near_before = before, added = added, near_after = near, sources = #sources }
