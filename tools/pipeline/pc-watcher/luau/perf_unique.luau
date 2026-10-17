-- Server datamodel (play): best effort, %%COUNT%% MeshParts with a NEW MeshId made at runtime without uploading anything:
-- AssetService:CreateEditableMeshAsync / CreateEditableMesh from an existing MeshPart, then CreateMeshPartAsync.
-- Every step is pcall'd; if no MeshPart with a MeshId different from every existing one can be produced the result is
-- {skipped = true, reason}. Parts go to workspace.PcwPerfMeshClones (removed by perf_clean), tagged PcwPerfClone.
local AssetService = game:GetService("AssetService")
local COUNT = %%COUNT%%
local folder = workspace:FindFirstChild("PcwPerfMeshClones")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "PcwPerfMeshClones"
	folder.Parent = workspace
end
local known, src = {}, nil
for _, d in workspace:GetDescendants() do
	if d:IsA("MeshPart") and d.MeshId ~= "" then
		known[d.MeshId] = true
		src = src or d
	end
end
if not src then
	return { skipped = true, reason = "no MeshPart with a MeshId to start from" }
end
local steps = {}
local ok, em = pcall(function()
	return AssetService:CreateEditableMeshAsync(Content.fromUri(src.MeshId))
end)
if not ok or not em then
	steps.createEditableMeshAsync = tostring(em):sub(1, 200)
	ok, em = pcall(function()
		return AssetService:CreateEditableMesh()
	end)
	if not ok or not em then
		steps.createEditableMesh = tostring(em):sub(1, 200)
		return { skipped = true, reason = "no EditableMesh API usable on the server: " .. steps.createEditableMesh, steps = steps }
	end
end
local made, newIds, lastErr = 0, {}, nil
for i = 1, COUNT do
	local okP, mp = pcall(function()
		local e = em
		if i > 1 then
			e = em:Clone() -- distinct EditableMesh instance per part so each gets its own mesh content
		end
		return AssetService:CreateMeshPartAsync(Content.fromObject(e))
	end)
	if okP and mp then
		local id = mp.MeshId
		mp.Anchored, mp.CanCollide, mp.CanQuery = true, false, false
		mp:SetAttribute("PcwPerfClone", true)
		mp.CFrame = CFrame.new((i % 20) * 10 - 100, 20, math.floor(i / 20) * 10 - 100)
		mp.Parent = folder
		made += 1
		if id ~= "" and not known[id] and not newIds[id] then
			newIds[id] = true
		end
	else
		lastErr = tostring(mp):sub(1, 200)
		steps.createMeshPartAsync = lastErr
		break
	end
end
local distinct = 0
for _ in newIds do
	distinct += 1
end
if distinct == 0 then
	return { skipped = true, reason = "CreateMeshPartAsync gave no MeshId different from the existing ones (made " .. made .. ", " .. tostring(lastErr) .. ")", steps = steps, made = made }
end
return { skipped = false, requested = COUNT, made = made, new_mesh_ids = distinct, steps = steps }
