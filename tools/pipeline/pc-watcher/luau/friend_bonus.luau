-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwFriendBonus" (src/ui/init.client) to
-- %%COUNT%% friends (0 = the real State), so the friend badge on the HUD and the friend income line in the
-- SlimeDex card can be shot on a solo Studio server. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
gui:SetAttribute("PcwFriendBonus", %%COUNT%%)
task.wait(0.3)
return { found = true, count = gui:GetAttribute("PcwFriendBonus") }
