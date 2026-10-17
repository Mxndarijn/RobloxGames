-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwRain" (src/ui/init.client) to %%ON%%
-- (true = fake a running Slime Rain with ~97 s left for the HUD's bottom-right status slot, whatever the
-- workspace RainActive attributes say; false clears it). Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local on = %%ON%%
gui:SetAttribute("PcwRain", if on then true else nil)
task.wait(0.3)
return { found = true, rain = gui:GetAttribute("PcwRain") }
