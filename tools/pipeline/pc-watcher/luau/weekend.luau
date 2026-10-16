-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwWeekend" (src/ui/init.client) to %%ON%%
-- (true = fake a live x2 Weekend window in State.weekend; false clears it), so the HUD chip can be shot
-- on a weekday. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local on = %%ON%%
gui:SetAttribute("PcwWeekend", if on then true else nil)
task.wait(0.3)
return { found = true, weekend = gui:GetAttribute("PcwWeekend") }
