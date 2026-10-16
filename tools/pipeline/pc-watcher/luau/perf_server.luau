-- Server datamodel (play): mesh slots after MeshSwap (src/server/MeshSwap.luau) has turned the
-- world's stand-ins into MeshParts. The tracked world/*.rbxmx has no MeshParts, so Edit counts 0.
-- Wild slimes and player characters are counted separately (they are not world mesh slots).
local Players = game:GetService("Players")
local wild = workspace:FindFirstChild("WildSlimes")
local function excluded(d)
	if wild and d:IsDescendantOf(wild) then
		return true
	end
	local model = d:FindFirstAncestorOfClass("Model")
	while model do
		if Players:GetPlayerFromCharacter(model) then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end
local meshParts, unique, uniqueCount, parts, skipped = 0, {}, 0, 0, 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		if excluded(d) then
			if d:IsA("MeshPart") then
				skipped += 1
			end
		else
			parts += 1
			if d:IsA("MeshPart") then
				meshParts += 1
				local id = d.MeshId
				if id ~= "" and not unique[id] then
					unique[id] = true
					uniqueCount += 1
				end
			end
		end
	end
end
return {
	mesh_slots = meshParts,
	unique_meshes = uniqueCount,
	parts = parts,
	slime_and_character_meshes = skipped,
	store_status = workspace:GetAttribute("DataStoreStatus"),
}
