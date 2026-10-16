-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwBadgeToast" (src/ui/init.client) to
-- %%NAME%% (a badge name), which shows the badge-unlocked toast; "" clears the hook. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
gui:SetAttribute("PcwBadgeToast", "")
task.wait(0.1)
gui:SetAttribute("PcwBadgeToast", %%NAME%%)
task.wait(0.6)
return { found = true, name = gui:GetAttribute("PcwBadgeToast") }
