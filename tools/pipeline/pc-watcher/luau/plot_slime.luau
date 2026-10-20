-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwPlotSlime" (src/ui/init.client) to
-- %%STATE%% ("1" = show one fake owned slime in the My Plot panel when the real list is empty, ""
-- = real state), so the plot row shot has a row. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
gui:SetAttribute("PcwPlotSlime", %%STATE%% == "1")
task.wait(0.2)
return { found = true, state = gui:GetAttribute("PcwPlotSlime") }
