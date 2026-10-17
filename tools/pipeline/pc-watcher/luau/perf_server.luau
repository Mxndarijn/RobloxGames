-- Server datamodel (play): mesh slots after MeshSwap (src/server/MeshSwap.luau) has turned the
-- world's stand-ins into MeshParts. The tracked world/*.rbxmx has no MeshParts, so Edit counts 0.
-- Wild slimes and player characters are counted separately (they are not world mesh slots).
-- runtime_parts counts the WORLD BaseParts in Workspace (same set as tests/RuntimeParts.spec) once the parade
-- lane and the slide colliders have spawned: wild slimes, pad slimes (plot "Slimes" folders), player characters
-- and the drain splash holder are transient play objects and go to runtime_parts_transient, so the cap does not
-- flap with play. Budgets (fixed caps, no ratchet) live in tools/pipeline/pc-watcher/budgets.json; the shot's
-- runtime_parts_max mirrors runtime_parts.fail. Triangles cannot be computed from Luau: CI counts them (pr-gate budget.sh).
local Players = game:GetService("Players")
local wild = workspace:FindFirstChild("WildSlimes")
local function excluded(d)
	if wild and d:IsDescendantOf(wild) then
		return true
	end
	if d.Name == "DrainSplash" then
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
local meshParts, unique, uniqueCount, parts, skipped, runtimeParts, transient = 0, {}, 0, 0, 0, 0, 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		if excluded(d) or d:FindFirstAncestor("Slimes") then
			transient += 1
		else
			runtimeParts += 1
		end
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
	runtime_parts = runtimeParts,
	runtime_parts_transient = transient,
	parade_lane = workspace:FindFirstChild("ParadeLane", true) ~= nil,
	slide_colliders = workspace:FindFirstChild("SlideColliders", true) ~= nil,
	slime_and_character_meshes = skipped,
	store_status = workspace:GetAttribute("DataStoreStatus"),
}
