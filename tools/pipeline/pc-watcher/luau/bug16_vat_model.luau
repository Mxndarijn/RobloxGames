-- Client datamodel: bug probe 16 (visual, ok = null). "Use the old slime vat model": lists what stands in as the merge vat
-- now: the plot's MergeVat part (class, size, material), the client vat mesh folder workspace.ClientMergeVat and
-- ReplicatedStorage.MergeVatMeshes (name, MeshId, TextureID), and every other MeshPart / SpecialMesh in the workspace and
-- ReplicatedStorage whose name contains "vat" or "cauldron" (name + MeshId), so a reviewer can see which model is in use.
local RS = game:GetService("ReplicatedStorage")
local function meshInfo(d)
	if d:IsA("MeshPart") then
		return { name = d:GetFullName(), mesh = d.MeshId, texture = d.TextureID, size = { d.Size.X, d.Size.Y, d.Size.Z } }
	elseif d:IsA("SpecialMesh") then
		return { name = d:GetFullName(), mesh = d.MeshId, texture = d.TextureId }
	end
end
local found, plotVat = {}, nil
for _, root in { workspace, RS } do
	for _, d in root:GetDescendants() do
		local n = string.lower(d.Name)
		if #found < 20 and (string.find(n, "vat", 1, true) or string.find(n, "cauldron", 1, true)) then
			local info = meshInfo(d)
			if info then
				table.insert(found, info)
			end
		end
		if not plotVat and d.Name == "MergeVat" and d:IsA("BasePart") then
			plotVat = { path = d:GetFullName(), class = d.ClassName, size = { d.Size.X, d.Size.Y, d.Size.Z }, material = d.Material.Name, transparency = d.Transparency }
		end
	end
end
local client = workspace:FindFirstChild("ClientMergeVat")
local stock = RS:FindFirstChild("MergeVatMeshes")
return {
	ok = nil,
	summary = string.format("plot vat %s; %d client vat mesh(es), %d MergeVatMeshes template(s), %d vat-named mesh(es)", plotVat and plotVat.class or "missing", client and #client:GetChildren() or 0, stock and #stock:GetChildren() or 0, #found),
	detail = {
		plot_vat = plotVat,
		client_vat_meshes = client and #client:GetChildren() or 0,
		templates = stock and (function()
			local names = {}
			for _, c in stock:GetChildren() do
				table.insert(names, c.Name)
			end
			return names
		end)() or {},
		meshes = found,
	},
}
