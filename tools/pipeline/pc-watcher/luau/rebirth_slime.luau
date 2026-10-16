-- Client datamodel: sets the Studio-only SlimeUI attribute "PcwRebirthSlime" (src/ui/init.client) to
-- %%STATE%% ("owned" / "missing" force the Rebirth panel's required-slime state, "" gives the real one),
-- so the rebirth menu shot shows both states without a real slime. Never active in live servers.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
gui:SetAttribute("PcwRebirthSlime", %%STATE%%)
task.wait(0.2)
return { found = true, state = gui:GetAttribute("PcwRebirthSlime") }
