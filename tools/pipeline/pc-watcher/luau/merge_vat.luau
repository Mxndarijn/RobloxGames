-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwMergeVat" (src/ui/init.client + Panels/Merge,
-- to %%ON%%: true shows the 3-slime vat panel (opens in 3-slime mode) with FEATURES.MergeVat3 off; false clears it.
-- The vat model itself no longer needs forcing (server MeshSwap.swapPlotVats, every plot, flag-independent); vat_meshes
-- reports the plots whose MergeVat disc carries it. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local on = %%ON%%
gui:SetAttribute("PcwMergeVat", if on then true else nil)
task.wait(1.2) -- UI re-render
local vats = 0
local plots = workspace:FindFirstChild("Plots")
for _, plot in if plots then plots:GetChildren() else {} do
	local vat = plot:FindFirstChild("MergeVat")
	if vat and vat:FindFirstChild("VatMesh") then
		vats += 1
	end
end
return { found = true, on = gui:GetAttribute("PcwMergeVat") == true, vat_meshes = vats }
