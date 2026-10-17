-- Server datamodel (play): removes workspace.PcwPerfClones (the perf_stress clones) and workspace.PcwPerfMeshClones
-- (perf_meshclone / perf_unique).
local n = 0
for _, name in { "PcwPerfClones", "PcwPerfMeshClones" } do
	local folder = workspace:FindFirstChild(name)
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		folder:Destroy()
	end
end
return {
	removed_parts = n,
	gone = workspace:FindFirstChild("PcwPerfClones") == nil and workspace:FindFirstChild("PcwPerfMeshClones") == nil,
}
