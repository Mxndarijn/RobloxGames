-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwMergeVat" (src/ui/init.client + Panels/Merge,
-- src/visuals/client/VatFx) to %%ON%%: true shows the 3-slime vat panel (opens in 3-slime mode) and stands the
-- vat mesh over my plot's vat disc with FEATURES.MergeVat3 off; false clears it. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local on = %%ON%%
gui:SetAttribute("PcwMergeVat", if on then true else nil)
task.wait(1.2) -- UI re-render + VatFx refresh (2 Hz) + the mesh clone
local folder = workspace:FindFirstChild("ClientMergeVat")
return { found = true, on = gui:GetAttribute("PcwMergeVat") == true, vat_meshes = if folder then #folder:GetChildren() else 0 }
