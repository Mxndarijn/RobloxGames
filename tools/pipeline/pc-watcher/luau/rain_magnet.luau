-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwRainMagnet" (src/ui/init.client adds the Rain Magnet
-- row to State.upgrades, src/visuals/client/RainMagnetFx stands the magnet prop on Plot_1) to %%ON%%: true shows
-- both with FEATURES.RainMagnet off; false clears it. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local on = %%ON%%
gui:SetAttribute("PcwRainMagnet", if on then true else nil)
task.wait(1.2) -- UI re-render + RainMagnetFx refresh (2 Hz) + the mesh clone
local folder = workspace:FindFirstChild("ClientRainMagnet")
return { found = true, on = gui:GetAttribute("PcwRainMagnet") == true, magnet_meshes = if folder then #folder:GetChildren() else 0 }
