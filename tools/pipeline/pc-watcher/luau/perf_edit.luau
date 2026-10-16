-- Edit datamodel: mesh slots (MeshPart instances), unique MeshIds, parts.
-- Also makes sure this throwaway session runs on the in-memory store
-- (games/steal-a-slime/CLAUDE.md: never touch production DataStores).
local meshParts, unique, uniqueCount, parts, total = 0, {}, 0, 0, 0
for _, d in workspace:GetDescendants() do
	total += 1
	if d:IsA("BasePart") then
		parts += 1
	end
	if d:IsA("MeshPart") then
		meshParts += 1
		local id = d.MeshId
		if id ~= "" and not unique[id] then
			unique[id] = true
			uniqueCount += 1
		end
	end
end
local before = workspace:GetAttribute("DataStoreMode")
if before ~= "Memory" then
	workspace:SetAttribute("DataStoreMode", "Memory")
end
return {
	mesh_slots = meshParts,
	unique_meshes = uniqueCount,
	parts = parts,
	descendants = total,
	datastore_mode_before = before,
	datastore_mode = workspace:GetAttribute("DataStoreMode"),
	place_name = game.Name,
	place_id = game.PlaceId,
}
